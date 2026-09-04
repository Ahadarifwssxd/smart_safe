import 'package:another_telephony/telephony.dart';

/// Drop-in replacement for the abandoned `flutter_sms` package's `sendSMS`.
///
/// flutter_sms 2.x used the removed Flutter v1 embedding (won't compile), and
/// 3.x dropped silent sending (it only opens the SMS composer). The SOS dispatch
/// MUST be able to fire SMS silently in the background, so we send via the SIM's
/// SmsManager using `another_telephony` (which keeps that capability) and keep
/// the exact same call signature so the rest of the app is unchanged.
///
/// - [sendDirect] true  → sends SILENTLY from the SIM (needs SEND_SMS perm).
///   No user interaction — required during an emergency.
/// - [sendDirect] false → opens the device's SMS app pre-filled (fallback when
///   the permission isn't granted), so the user just taps Send.
///
/// Returns a short status string ('sent' / 'composer') to mirror flutter_sms,
/// which returned a String result.
final Telephony _telephony = Telephony.instance;

Future<String> sendSMS({
  required String message,
  required List<String> recipients,
  bool sendDirect = true,
}) async {
  final targets = recipients.where((r) => r.trim().isNotEmpty).toList();
  if (targets.isEmpty) return 'no-recipients';

  if (sendDirect) {
    // Make sure THIS plugin actually holds the SMS permission (some OEMs need it
    // requested through the plugin's own channel, not just permission_handler).
    bool permitted = true;
    try {
      permitted = (await _telephony.requestSmsPermissions) ?? true;
    } catch (_) {}

    if (permitted) {
      // Silent SIM send to every recipient. A per-recipient try/catch means one
      // blocked/failed send never aborts the rest of the SOS dispatch.
      var sentAny = false;
      for (final to in targets) {
        try {
          await _telephony.sendSms(to: to, message: message);
          sentAny = true;
        } catch (_) {
          // Silent SMS can be blocked by the OEM security layer (e.g. MIUI /
          // Xiaomi). Keep going and fall back to the composer below.
        }
      }
      if (sentAny) return 'sent';
    }

    // Silent send unavailable/blocked → open the SMS app pre-filled so the
    // message still goes out with a single tap.
    try {
      await _telephony.sendSmsByDefaultApp(to: targets.first, message: message);
    } catch (_) {}
    return 'composer';
  }

  // Fallback: open the default SMS app pre-filled (one address via the intent).
  await _telephony.sendSmsByDefaultApp(to: targets.first, message: message);
  return 'composer';
}
