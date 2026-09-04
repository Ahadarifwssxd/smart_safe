import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'local_notification_service.dart';

/// Registers this device for Firebase Cloud Messaging and stores its token on
/// the user's profile so the backend can push Community-SOS alerts even when
/// the app is backgrounded.
///
/// Tokens live in `users/{uid}.fcmTokens` (an array — a person may have several
/// devices). A Cloud Function reads them to deliver nearby-SOS pushes.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  String? _registeredUid;
  bool _listenersBound = false;

  /// Call once a user is signed in. Safe to call repeatedly; it only does work
  /// when the uid changes.
  Future<void> registerForUser(String uid) async {
    if (kIsWeb) return; // web push needs a VAPID key + SW setup — skip for now.
    if (_registeredUid == uid) return;
    _registeredUid = uid;

    try {
      await _fcm.requestPermission();

      final token = await _fcm.getToken();
      if (token != null) {
        await _saveToken(uid, token);
      }

      if (!_listenersBound) {
        _listenersBound = true;

        // Token rotation.
        _fcm.onTokenRefresh.listen((t) {
          final u = _registeredUid;
          if (u != null) _saveToken(u, t);
        });

        // Foreground messages → surface as a local heads-up notification
        // (FCM does not display them automatically while the app is open).
        FirebaseMessaging.onMessage.listen((msg) {
          // AVOID DUPLICATES: while the app is in the foreground, the
          // CommunitySosWatcher already shows SOS alerts from Firestore. If we
          // ALSO showed the FCM copy, the user would get the SAME alert twice.
          // So skip SOS types here — the FCM push still shows in the tray when
          // the app is CLOSED (handled by the system, not this handler).
          final type = msg.data['type']?.toString() ?? '';
          if (type == 'sos_alert' || type == 'sos_personal') return;

          final n = msg.notification;
          final title = n?.title ?? msg.data['title'] ?? '🆘 SmartSafe alert';
          final body = n?.body ?? msg.data['body'] ?? 'Someone nearby needs help.';
          LocalNotificationService.instance.show(
            id: 2500 + (msg.messageId.hashCode % 1000),
            title: title,
            body: body,
          );
        });
      }
    } catch (e) {
      debugPrint('[PushService] register failed: $e');
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      debugPrint('[PushService] token saved for $uid');
    } catch (e) {
      debugPrint('[PushService] token save failed: $e');
    }
  }

  /// Remove this device's token on logout so the user stops receiving pushes
  /// on a device they signed out of.
  Future<void> unregister(String uid) async {
    _registeredUid = null;
    if (kIsWeb) return;
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[PushService] unregister failed: $e');
    }
  }
}
