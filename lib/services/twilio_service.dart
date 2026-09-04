import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class TwilioService {
  TwilioService._privateConstructor();
  static final TwilioService instance = TwilioService._privateConstructor();

  final String _accountSid = 'ACeab0b8d5371125e5cd59c2695c4359d8';
  final String _authToken = 'd99dd16f617aa55995073290a8e813a8';
  final String _twilioNumber = '+15053936316'; // Twilio trial number

  /// Twilio WhatsApp sender. By default this is the free Twilio Sandbox number.
  /// IMPORTANT: every recipient must first join the sandbox ONCE by sending
  /// `join <your-sandbox-code>` to this number on WhatsApp. After that, alerts
  /// are delivered automatically. Replace with your approved WhatsApp Business
  /// sender once you have one.
  final String _whatsappFrom = 'whatsapp:+14155238886';

  /// Converts local Pakistan numbers to international E.164 format.
  /// e.g. 03132441066 → +923132441066
  String _toE164(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Already in international format
    if (cleaned.startsWith('+')) return cleaned;
    // Pakistan local format (0XXXXXXXXXX)
    if (cleaned.startsWith('0') && cleaned.length == 11) {
      return '+92${cleaned.substring(1)}';
    }
    // Pakistan without leading zero (3XXXXXXXXX)
    if (cleaned.startsWith('3') && cleaned.length == 10) {
      return '+92$cleaned';
    }
    // Already has country code without + (923XXXXXXXXX)
    if (cleaned.startsWith('92') && cleaned.length == 12) {
      return '+$cleaned';
    }
    return cleaned;
  }

  /// Sends an SMS message to the given [to] phone number.
  Future<bool> sendSms(String to, String message) async {
    final toFormatted = _toE164(to);
    debugPrint('[Twilio] Sending SMS to $toFormatted');

    final url = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$_accountSid/Messages.json');
    final authStr = '$_accountSid:$_authToken';
    final base64Str = base64.encode(utf8.encode(authStr));

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Basic $base64Str',
        },
        body: {
          'From': _twilioNumber,
          'To': toFormatted,
          'Body': message,
        },
      );

      if (response.statusCode == 201) {
        debugPrint('[Twilio] ✅ SMS sent successfully to $toFormatted');
        return true;
      } else {
        debugPrint('[Twilio] ❌ SMS failed ($toFormatted): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[Twilio] ❌ SMS exception ($toFormatted): $e');
      return false;
    }
  }

  /// Sends a WhatsApp message to the given [to] number via Twilio.
  /// Returns true on success (HTTP 201).
  Future<bool> sendWhatsApp(String to, String message) async {
    final toFormatted = 'whatsapp:${_toE164(to)}';
    debugPrint('[Twilio] Sending WhatsApp to $toFormatted');

    final url = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$_accountSid/Messages.json');
    final authStr = '$_accountSid:$_authToken';
    final base64Str = base64.encode(utf8.encode(authStr));

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Basic $base64Str',
        },
        body: {
          'From': _whatsappFrom,
          'To': toFormatted,
          'Body': message,
        },
      );

      if (response.statusCode == 201) {
        debugPrint('[Twilio] ✅ WhatsApp sent to $toFormatted');
        return true;
      } else {
        debugPrint('[Twilio] ❌ WhatsApp failed ($toFormatted): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[Twilio] ❌ WhatsApp exception ($toFormatted): $e');
      return false;
    }
  }

  /// Makes a phone call to the given [to] phone number and plays a TwiML message.
  Future<bool> makeCall(String to, {String? customMessage}) async {
    final toFormatted = _toE164(to);
    debugPrint('[Twilio] Initiating call to $toFormatted');

    final url = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$_accountSid/Calls.json');
    final authStr = '$_accountSid:$_authToken';
    final base64Str = base64.encode(utf8.encode(authStr));

    final message = customMessage ??
        'This is an emergency S O S alert from Smart Safe. A user needs immediate help. Please check your messages for their location.';
    final twiml = '<Response><Say voice="alice">$message</Say></Response>';

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Basic $base64Str',
        },
        body: {
          'From': _twilioNumber,
          'To': toFormatted,
          'Twiml': twiml,
        },
      );

      if (response.statusCode == 201) {
        debugPrint('[Twilio] ✅ Call initiated successfully to $toFormatted');
        return true;
      } else {
        debugPrint('[Twilio] ❌ Call failed ($toFormatted): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[Twilio] ❌ Call exception ($toFormatted): $e');
      return false;
    }
  }
}
