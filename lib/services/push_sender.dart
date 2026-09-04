import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Delivers SOS pushes to contacts even when their SmartSafe app is CLOSED, by
/// calling our free Vercel endpoint (a drop-in replacement for the Blaze-only
/// Cloud Function). The endpoint holds the Firebase service account and sends
/// the real FCM message; this client just says "push these user ids".
///
/// Fire-and-forget: any failure is logged, never thrown, so an SOS never breaks
/// because the push server was slow or unreachable.
class PushSender {
  PushSender._();
  static final PushSender instance = PushSender._();

  /// Our free Vercel push endpoint (holds the Firebase service account and
  /// sends the real FCM message so contacts get alerted even when their app is
  /// closed). Deployed from `push-server/`.
  static const String endpoint =
      'https://push-server-alpha.vercel.app/api/send-sos';

  bool get _configured =>
      endpoint.startsWith('http') && !endpoint.contains('PASTE_YOUR');

  /// Push an SOS alert to one or more SmartSafe users by their uid.
  Future<void> pushSos({
    required List<String> targetUserIds,
    required String type, // 'sos_personal' | 'sos_alert'
    required String senderName,
    String sosUserId = '',
    String latitude = '',
    String longitude = '',
  }) async {
    if (!_configured) {
      debugPrint('[PushSender] endpoint not set — skipping closed-app push');
      return;
    }
    final targets = targetUserIds.where((e) => e.isNotEmpty).toSet().toList();
    if (targets.isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();

      final res = await http
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'idToken': idToken,
              'targetUserIds': targets,
              'type': type,
              'senderName': senderName,
              'sosUserId': sosUserId,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(const Duration(seconds: 12));
      debugPrint('[PushSender] ${res.statusCode}: ${res.body}');
    } catch (e) {
      debugPrint('[PushSender] failed: $e');
    }
  }
}
