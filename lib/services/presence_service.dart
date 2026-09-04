import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:smartsafe/utils/phone_utils.dart';

import 'web_presence_listener_stub.dart'
    if (dart.library.html) 'web_presence_listener_web.dart';

/// Online status keyed by normalized phone (`presence_by_phone/{phone}`).
class PresenceService {
  static final PresenceService instance = PresenceService._internal();
  PresenceService._internal() {
    bindTabVisibilityHeartbeat(() => heartbeat());
  }

  static const _onlineWindow = Duration(minutes: 15);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  Timer? _heartbeatTimer;
  String? _activeUid;
  String? _lastPublishedPhone;

  // Cache of the signed-in user's phone so the heartbeat doesn't re-read
  // the `users` doc from Firestore on EVERY tick (1 read per tick per user,
  // forever, was pure waste — the phone almost never changes).
  String? _cachedUid;
  String? _cachedPhone;
  String? _cachedRawPhone;

  // The `users` doc only needs its isOnline/lastSeen refreshed occasionally —
  // the live status lives in `presence` + `presence_by_phone`. Writing the user
  // doc on every heartbeat was 3× the necessary write volume.
  int _heartbeatTickCount = 0;
  static const _usersDocWriteEvery = 7; // 7 × 45s ≈ 5 minutes

  CollectionReference<Map<String, dynamic>> get _presence =>
      _db.collection('presence');
  CollectionReference<Map<String, dynamic>> get _presenceByPhone =>
      _db.collection('presence_by_phone');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  void startHeartbeat() {
    final uid = _uid;
    if (uid == null) return;
    if (_activeUid == uid && _heartbeatTimer != null) return;
    _activeUid = uid;
    _heartbeatTimer?.cancel();
    _heartbeatTickCount = 0;
    heartbeat();
    // 45s cadence: the "online" window is 15 minutes, so a status written
    // every 45s stays fresh 20× over inside it — while cutting per-user
    // Firestore writes ~44% vs the old 25s tick (bandwidth + battery).
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 45), (_) => heartbeat());
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activeUid = null;
  }

  /// Reads the user's phone once and caches it for the session. Only re-reads
  /// when the signed-in user changes or the cache is empty.
  Future<(String? normalized, String raw)> _resolvePhone() async {
    final uid = _uid;
    if (uid == null) return (null, '');
    if (_cachedUid == uid && _cachedPhone != null) {
      return (_cachedPhone, _cachedRawPhone ?? '');
    }
    final user = FirebaseAuth.instance.currentUser;
    final snap = await _db.collection('users').doc(uid).get();
    final phone = snap.data()?['phone']?.toString().trim() ??
        user?.phoneNumber?.trim() ??
        '';
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) return (null, phone);
    _cachedUid = uid;
    _cachedPhone = normalized;
    _cachedRawPhone = phone;
    return (normalized, phone);
  }

  Future<void> heartbeat() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final (normalized, phoneRaw) = await _resolvePhone();
      if (normalized == null) {
        debugPrint(
          'Presence: Save your phone number in Settings > Profile.',
        );
        return;
      }

      if (_lastPublishedPhone != null && _lastPublishedPhone != normalized) {
        await _markPhoneOffline(_lastPublishedPhone!);
      }
      _lastPublishedPhone = normalized;

      final payload = <String, dynamic>{
        'uid': uid,
        'phoneNormalized': normalized,
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      };

      _heartbeatTickCount++;
      final futures = <Future<void>>[
        _presence.doc(uid).set(payload, SetOptions(merge: true)),
        _presenceByPhone.doc(normalized).set(payload, SetOptions(merge: true)),
      ];
      // Refresh the `users` doc only occasionally — the always-fresh status is
      // in `presence`/`presence_by_phone` above.
      if (_heartbeatTickCount % _usersDocWriteEvery == 1) {
        futures.add(_db.collection('users').doc(uid).set({
          'phone': phoneRaw,
          'phoneNormalized': normalized,
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)));
      }
      await Future.wait(futures);
    } catch (e) {
      debugPrint('Presence heartbeat error: $e');
    }
  }

  Future<void> _markPhoneOffline(String normalized) async {
    try {
      await _presenceByPhone.doc(normalized).set({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Presence mark phone offline error: $e');
    }
  }

  Future<void> goOffline() async {
    final uid = _uid;
    stopHeartbeat();
    if (uid == null) return;
    try {
      String? normalized = _lastPublishedPhone;
      if (normalized == null) {
        final (cached, _) = await _resolvePhone();
        normalized = cached;
      }
      final offline = {
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      await _presence.doc(uid).set(offline, SetOptions(merge: true));
      await _db
          .collection('users')
          .doc(uid)
          .set(offline, SetOptions(merge: true));
      if (normalized != null) {
        await _presenceByPhone
            .doc(normalized)
            .set(offline, SetOptions(merge: true));
      }
      _lastPublishedPhone = null;
    } catch (e) {
      debugPrint('Presence goOffline error: $e');
    }
  }

  Stream<Map<String, bool>> watchOnlineByPhone() {
    return _presenceByPhone.snapshots().map(_onlineMapFromPhoneIndex);
  }

  Stream<Map<String, bool>> watchOnlineForPhones(List<String> phones) {
    if (phones.isEmpty) return Stream.value({});
    return _presenceByPhone
        .where(FieldPath.documentId, whereIn: phones)
        .snapshots()
        .map(_onlineMapFromPhoneIndex);
  }

  /// Streams presence info for a single phone: {'isOnline': bool, 'lastSeen': DateTime?}
  Stream<Map<String, dynamic>> watchUserPresence(String phone) {
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) {
      return Stream.value({'isOnline': false, 'lastSeen': null});
    }
    return _presenceByPhone.doc(normalized).snapshots().map((snap) {
      if (!snap.exists) return {'isOnline': false, 'lastSeen': null};
      final d = snap.data()!;
      final now = DateTime.now();
      final isOnline = _docIsOnline(d, now);
      final ts = d['lastSeen'];
      final lastSeen = ts is Timestamp ? ts.toDate() : null;
      return {'isOnline': isOnline, 'lastSeen': lastSeen};
    });
  }

  Map<String, bool> _onlineMapFromPhoneIndex(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final map = <String, bool>{};
    final now = DateTime.now();

    for (final doc in snap.docs) {
      final phone = doc.id;
      if (phone.isEmpty) continue;
      map[phone] = _docIsOnline(doc.data(), now);
    }
    return map;
  }

  bool _docIsOnline(Map<String, dynamic> d, DateTime now) {
    if (d['isOnline'] != true) return false;
    final lastSeen = d['lastSeen'];
    if (lastSeen is! Timestamp) return true;
    return now.difference(lastSeen.toDate()) <= _onlineWindow;
  }
}
