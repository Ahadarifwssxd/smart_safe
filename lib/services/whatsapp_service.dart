import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/phone_utils.dart';

/// Free WhatsApp dispatch via the public wa.me deep link — no Twilio, no paid
/// account. It opens WhatsApp with the message pre-filled to a given number;
/// the user taps Send. WhatsApp only allows ONE chat to open at a time, so for
/// multiple contacts we open the primary one and expose a helper to open the
/// rest one-by-one from the UI.
class WhatsAppService {
  static final WhatsAppService instance = WhatsAppService._();
  WhatsAppService._();

  /// Builds the EXACT same person's international number that the SIM call/SMS
  /// reach, so WhatsApp never opens a different/broken number (the "mismatch").
  ///
  /// wa.me needs full international digits with the country code and NO leading
  /// 0 (e.g. "0300-1234567" and "+92 300 1234567" must both become
  /// "923001234567"). The old version only stripped the 0 — it dropped the 92
  /// country code, so WhatsApp opened a wrong number while the call dialled the
  /// right one.
  String _waNumber(String phone) {
    var d = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('00')) d = d.substring(2); // 0092… -> 92…
    // Already a full international Pakistani number? Keep it.
    if (d.startsWith('92') && d.length >= 12) return d;
    // Local format → take the canonical last-10 digits and prepend PK code 92,
    // matching how the call/SMS resolve the same contact.
    final core = normalizePhone(phone); // last 10 digits, strips 0 / 92
    if (core.length == 10) return '92$core';
    return d; // fallback: best-effort digits
  }

  /// Public access to the same international-number normalisation used for
  /// wa.me, so the WhatsApp Business API auto-send reaches the EXACT same
  /// person (e.g. "0300-1234567" → "923001234567").
  String intlNumber(String phone) => _waNumber(phone);

  /// Opens WhatsApp with [message] pre-filled for [phone]. Returns whether the
  /// WhatsApp app/web could be launched.
  Future<bool> openChat(String phone, String message) async {
    final num = _waNumber(phone);
    if (num.isEmpty) return false;
    final uri =
        Uri.parse('https://wa.me/$num?text=${Uri.encodeComponent(message)}');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[WhatsApp] launch failed for $phone: $e');
      return false;
    }
  }
}
