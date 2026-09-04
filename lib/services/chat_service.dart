import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartsafe/services/cloudinary_service.dart';
import 'package:smartsafe/models/chat_message.dart';
import 'package:smartsafe/utils/phone_utils.dart';

class ChatService {
  static final ChatService instance = ChatService._internal();
  ChatService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  String getConversationId(String phone1, String phone2) {
    final p1 = normalizePhone(phone1);
    final p2 = normalizePhone(phone2);
    return p1.compareTo(p2) < 0 ? '${p1}_$p2' : '${p2}_$p1';
  }

  Stream<List<ChatMessage>> watchChatMessages({
    required String myPhone,
    required String otherPhone,
  }) {
    final myPhoneNormalized = normalizePhone(myPhone);
    final otherPhoneNormalized = normalizePhone(otherPhone);
    final rawMyPhone = myPhone.trim();
    final rawOtherPhone = otherPhone.trim();

    return _db.collection('user_chats')
        .where(Filter.or(
          Filter('senderPhone', isEqualTo: myPhoneNormalized),
          Filter('receiverPhone', isEqualTo: myPhoneNormalized),
          Filter('senderPhone', isEqualTo: rawMyPhone),
          Filter('receiverPhone', isEqualTo: rawMyPhone),
        ))
        .snapshots()
        .map((snap) {
          final messages = snap.docs.map((doc) {
            return ChatMessage.fromFirestore(doc.id, doc.data());
          }).where((m) {
            final sNorm = normalizePhone(m.senderPhone);
            final rNorm = normalizePhone(m.receiverPhone);
            final isPeerSender = sNorm == otherPhoneNormalized || m.senderPhone.trim() == rawOtherPhone;
            final isPeerReceiver = rNorm == otherPhoneNormalized || m.receiverPhone.trim() == rawOtherPhone;
            return isPeerSender || isPeerReceiver;
          }).toList();
          // Sort in memory by timestamp to avoid requiring composite indexes in Firestore
          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return messages;
        });
  }

  Stream<List<ChatMessage>> watchAllMyMessages(String myPhone) {
    final myPhoneNormalized = normalizePhone(myPhone);
    final rawPhone = myPhone.trim();
    return _db.collection('user_chats')
        .where(Filter.or(
          Filter('senderPhone', isEqualTo: myPhoneNormalized),
          Filter('receiverPhone', isEqualTo: myPhoneNormalized),
          Filter('senderPhone', isEqualTo: rawPhone),
          Filter('receiverPhone', isEqualTo: rawPhone),
        ))
        .snapshots()
        .map((snap) {
          final messages = snap.docs.map((doc) {
            return ChatMessage.fromFirestore(doc.id, doc.data());
          }).toList();
          // Sort in memory by timestamp to avoid requiring composite indexes in Firestore
          messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return messages;
        });
  }

  Future<void> sendMessage({
    required String myPhone,
    required String otherPhone,
    required String message,
    required bool isOfflineSms,
  }) async {
    final uid = currentUid;
    if (uid == null) return;

    final roomId = getConversationId(myPhone, otherPhone);
    final docRef = _db.collection('user_chats').doc();

    await docRef.set({
      'conversationId': roomId,
      'senderId': uid,
      'senderPhone': normalizePhone(myPhone),
      'receiverPhone': normalizePhone(otherPhone),
      'message': message.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'isOfflineSms': isOfflineSms,
      'isRead': false,
      'type': 'text',
    });
  }

  Future<void> sendImageMessage({
    required String myPhone,
    required String otherPhone,
    required String imageUrl,
  }) async {
    final uid = currentUid;
    if (uid == null) return;

    final roomId = getConversationId(myPhone, otherPhone);
    final docRef = _db.collection('user_chats').doc();

    await docRef.set({
      'conversationId': roomId,
      'senderId': uid,
      'senderPhone': normalizePhone(myPhone),
      'receiverPhone': normalizePhone(otherPhone),
      'message': '📷 Photo',
      'timestamp': FieldValue.serverTimestamp(),
      'isOfflineSms': false,
      'isRead': false,
      'type': 'image',
      'imageUrl': imageUrl,
    });
  }

  /// Permanently deletes a single chat message by its document id.
  Future<void> deleteMessage(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      await _db.collection('user_chats').doc(messageId).delete();
    } catch (e) {
      throw Exception('Could not delete message: $e');
    }
  }

  /// Deletes EVERY message in the conversation between the two phones.
  Future<void> clearConversation({
    required String myPhone,
    required String otherPhone,
  }) async {
    final roomId = getConversationId(myPhone, otherPhone);
    final snap = await _db
        .collection('user_chats')
        .where('conversationId', isEqualTo: roomId)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // ── Per-user contact display name (alias) ──────────────────────────────────
  // Lets a user rename ANY chat (even one that isn't a saved emergency
  // contact). Keyed by my uid + the other person's normalized phone so it
  // persists and shows every time the chat is opened.
  String _aliasId(String otherPhone) =>
      '${currentUid ?? ''}_${normalizePhone(otherPhone)}';

  Future<void> setContactAlias(String otherPhone, String name) async {
    final uid = currentUid;
    if (uid == null) return;
    await _db.collection('contact_aliases').doc(_aliasId(otherPhone)).set({
      'ownerId': uid,
      'phoneNormalized': normalizePhone(otherPhone),
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> getContactAlias(String otherPhone) async {
    if (currentUid == null) return null;
    try {
      final doc =
          await _db.collection('contact_aliases').doc(_aliasId(otherPhone)).get();
      final n = doc.data()?['name']?.toString();
      return (n != null && n.isNotEmpty) ? n : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> uploadChatImage(Uint8List bytes, String extension) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$extension';
    // Free media storage via Cloudinary (no Firebase Storage / Blaze needed).
    try {
      return await CloudinaryService.instance.uploadBytes(
        bytes,
        fileName,
        type: 'image',
        folder: 'chat_files',
      );
    } on TimeoutException {
      throw Exception('Upload timed out. Please check your internet connection.');
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
  }

  Future<void> markMessagesAsRead({
    required String myPhone,
    required String otherPhone,
  }) async {
    try {
      final myPhoneNormalized = normalizePhone(myPhone);
      final otherPhoneNormalized = normalizePhone(otherPhone);
      final rawMyPhone = myPhone.trim();
      final rawOtherPhone = otherPhone.trim();

      // Fetch only UNREAD messages for the user. Without the `isRead` filter
      // this pulled the ENTIRE received history (twice — normalized + raw)
      // and filtered in memory; the read set stays tiny so the query stays
      // cheap forever. Both filters are equalities, so no composite index is
      // needed (Firestore merges the single-field indexes).
      final snap = await _db.collection('user_chats')
          .where('receiverPhone', isEqualTo: myPhoneNormalized)
          .where('isRead', isEqualTo: false)
          .get();

      final snapRaw = await _db.collection('user_chats')
          .where('receiverPhone', isEqualTo: rawMyPhone)
          .where('isRead', isEqualTo: false)
          .get();

      final allDocs = [...snap.docs, ...snapRaw.docs];

      // Filter in memory for messages sent by the peer (the query is already
      // unread-only, this just scopes it to THIS conversation's sender).
      final unreadDocs = allDocs.where((doc) {
        final data = doc.data();
        if (data['isRead'] == true) return false;

        final sender = data['senderPhone']?.toString() ?? '';
        final senderNormalized = normalizePhone(sender);
        final isPeerSender = senderNormalized == otherPhoneNormalized || sender.trim() == rawOtherPhone;

        return isPeerSender;
      }).toList();

      print('DEBUG ChatService: markMessagesAsRead. Found ${unreadDocs.length} unread docs.');

      if (unreadDocs.isEmpty) return;

      final batch = _db.batch();
      final uniqueDocIds = <String>{};
      for (final doc in unreadDocs) {
        if (uniqueDocIds.add(doc.id)) {
          batch.update(doc.reference, {'isRead': true});
        }
      }
      await batch.commit();
      print('DEBUG ChatService: Successfully marked ${uniqueDocIds.length} messages as read.');
    } catch (e) {
      print('DEBUG ChatService ERROR in markMessagesAsRead: $e');
    }
  }
}
