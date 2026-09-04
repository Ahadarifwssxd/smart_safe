import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// SOS Alert Service
/// Calls the Firebase Cloud Function "triggerSos" which handles:
/// ✅ Real Twilio Phone Calls  (to all emergency contacts)
/// ✅ Real Twilio SMS messages (to all emergency contacts)
/// ✅ Email alerts via Resend  (to contacts who have email set)
///
/// Works on Web, Android, and iOS — no CORS issues because
/// the Twilio API is called from Firebase servers, not the browser.
class SosAlertService {
  static final SosAlertService instance = SosAlertService._internal();
  SosAlertService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fetch emergency contacts and call the cloud function.
  Future<SosAlertResult> triggerAlert({
    required String senderName,
    required String location,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return SosAlertResult(success: false, error: 'User not logged in');
    }

    try {
      // 1. Fetch all emergency contacts for this user
      final snap = await _db
          .collection('emergency_contacts')
          .where('userId', isEqualTo: uid)
          .get();

      if (snap.docs.isEmpty) {
        return SosAlertResult(
          success: false,
          error: 'Koi emergency contact nahi mila. Pehle contacts add karein.',
        );
      }

      // Build the contacts list with phone + email
      final contacts = snap.docs
          .map((doc) {
            final d = doc.data();
            return {
              'name': d['name']?.toString() ?? 'Contact',
              'phone': d['phone']?.toString() ?? '',
              'email': d['email']?.toString() ?? '',
            };
          })
          .where((c) => (c['phone'] ?? '').toString().isNotEmpty)
          .toList();

      if (contacts.isEmpty) {
        return SosAlertResult(
          success: false,
          error: 'Contacts mein phone numbers nahi hain.',
        );
      }

      debugPrint(
          '[SosAlertService] Calling "triggerSos" for ${contacts.length} contacts...');
      for (final c in contacts) {
        debugPrint(
            '  → ${c['name']} | phone: ${c['phone']} | email: ${c['email']}');
      }

      // 2. Call the Firebase Cloud Function "triggerSos"
      //    This runs on Firebase servers → calls Twilio → sends emails
      final callable = FirebaseFunctions.instance.httpsCallable(
        'triggerSos',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

      final result = await callable.call({
        'contacts': contacts,
        'senderName': senderName,
        'location': location,
      });

      final data = result.data as Map<dynamic, dynamic>?;
      final success = data?['success'] == true;
      final rawResults = data?['results'] as List<dynamic>? ?? [];

      int callsSent = 0, smsSent = 0, emailsSent = 0;
      for (final r in rawResults) {
        if (r['callSent'] == true) callsSent++;
        if (r['smsSent'] == true) smsSent++;
        if (r['emailSent'] == true) emailsSent++;
      }

      debugPrint(
          '[SosAlertService] ✅ Done: calls=$callsSent, sms=$smsSent, emails=$emailsSent');

      return SosAlertResult(
        success: success,
        contactsNotified: contacts.length,
        callsSent: callsSent,
        smsSent: smsSent,
        emailsSent: emailsSent,
        message:
            '🚨 SOS bhej diya!\n📞 Calls: $callsSent\n💬 SMS: $smsSent\n📧 Emails: $emailsSent',
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[SosAlertService] FirebaseFunctionsException: ${e.code} — ${e.message}');
      return SosAlertResult(success: false, error: 'Function error: ${e.message}');
    } catch (e) {
      debugPrint('[SosAlertService] Error: $e');
      return SosAlertResult(success: false, error: e.toString());
    }
  }
}

class SosAlertResult {
  final bool success;
  final String? error;
  final String? message;
  final int contactsNotified;
  final int callsSent;
  final int smsSent;
  final int emailsSent;

  SosAlertResult({
    required this.success,
    this.error,
    this.message,
    this.contactsNotified = 0,
    this.callsSent = 0,
    this.smsSent = 0,
    this.emailsSent = 0,
  });
}
