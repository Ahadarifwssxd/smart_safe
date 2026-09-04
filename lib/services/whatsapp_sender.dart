import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Auto-sends the SOS message over WhatsApp — WITHOUT any redirect / without
/// opening WhatsApp — via our Vercel endpoint, which uses the WhatsApp Business
/// Cloud API (Meta). Every contact receives the sender's name, phone number and
/// live location. Fire-and-forget: failures are logged, never thrown.
class WhatsAppSender {
  WhatsAppSender._();
  static final WhatsAppSender instance = WhatsAppSender._();

  static const String endpoint =
      'https://push-server-alpha.vercel.app/api/send-whatsapp';

  Future<void> send({
    required List<String> recipients, // international digits, e.g. 923001234567
    required String senderName,
    required String senderPhone,
    required String location,
  }) async {
    final to = recipients.where((e) => e.isNotEmpty).toSet().toList();
    if (to.isEmpty) return;

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
              'recipients': to,
              'senderName': senderName,
              'senderPhone': senderPhone,
              'location': location,
            }),
          )
          .timeout(const Duration(seconds: 20));
      debugPrint('[WhatsAppSender] ${res.statusCode}: ${res.body}');
    } catch (e) {
      debugPrint('[WhatsAppSender] failed: $e');
    }
  }
}
