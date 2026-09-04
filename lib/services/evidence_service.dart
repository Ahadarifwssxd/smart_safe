import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

import 'cloudinary_service.dart';

class EvidenceService {
  EvidenceService._privateConstructor();
  static final EvidenceService instance = EvidenceService._privateConstructor();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  /// Upload an evidence file (photo, video or audio) and save metadata.
  Future<void> uploadEvidence({
    required File file,
    required String type, // 'photo' | 'video' | 'audio'
    required String note,
    required String locationString,
    required double lat,
    required double lng,
    required String fileSizeStr,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    String fileUrl = '';
    final evidenceId = _uuid.v4();

    if (!kIsWeb) {
      try {
        if (type == 'photo') {
          // Photos are stored INLINE (base64 in the Firestore doc) — zero setup,
          // works on every phone with no media host. Capture is already
          // resolution-capped so it fits under the document limit.
          final bytes = await file.readAsBytes();
          fileUrl = await CloudinaryService.instance
              .storeImage(bytes, folder: 'evidences/${user.uid}');
        } else if (type == 'audio') {
          // Voice notes + the SOS auto-recording are small (short clips), so
          // store them INLINE (base64) too — no Cloudinary needed. Larger clips
          // fall back to the media host automatically inside storeMedia().
          final bytes = await file.readAsBytes();
          fileUrl = await CloudinaryService.instance
              .storeMedia(bytes, type: 'audio', folder: 'evidences/${user.uid}');
        } else {
          // Video is too large to inline → media host (if configured).
          fileUrl = await CloudinaryService.instance.uploadFile(
            file,
            type: type, // 'video'
            folder: 'evidences/${user.uid}',
          );
        }
      } catch (e) {
        // Surface the REAL reason instead of silently logging an empty entry.
        if (kDebugMode) {
          // ignore: avoid_print
          print('[Evidence] file upload failed: $e');
        }
        final label = type == 'audio'
            ? 'voice note'
            : type == 'video'
                ? 'video'
                : 'photo';
        throw Exception(
            'Could not save $label. Media upload failed — check your internet '
            'and that Cloudinary is set up. ($e)');
      }
    } else {
      fileUrl = "web_local_file_or_mock_url";
    }

    final userName = user.displayName ?? 'Unknown User';

    await _firestore.collection('evidences').doc(evidenceId).set({
      'id': evidenceId,
      'userId': user.uid,
      'userName': userName,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'location': locationString,
      'latitude': lat,
      'longitude': lng,
      'note': note,
      'fileUrl': fileUrl,
      'size': fileSizeStr,
    });
  }

  /// Save a note evidence to Firestore without any file upload.
  Future<void> saveNoteEvidence({
    required String note,
    required String locationString,
    required double lat,
    required double lng,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final evidenceId = _uuid.v4();
    final userName = user.displayName ?? 'Unknown User';

    await _firestore.collection('evidences').doc(evidenceId).set({
      'id': evidenceId,
      'userId': user.uid,
      'userName': userName,
      'type': 'note',
      'timestamp': FieldValue.serverTimestamp(),
      'location': locationString,
      'latitude': lat,
      'longitude': lng,
      'note': note,
      'fileUrl': '',
      'size': '—',
    });
  }

  /// Get stream of evidences for current user
  Stream<QuerySnapshot> getUserEvidencesStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _firestore
        .collection('evidences')
        .where('userId', isEqualTo: user.uid)
        .snapshots();
  }

  /// Get stream of ALL evidences for Admin Dashboard
  Stream<QuerySnapshot> getAllEvidencesStream() {
    return _firestore
        .collection('evidences')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
