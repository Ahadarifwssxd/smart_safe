import 'dart:convert';

import 'package:emailjs/emailjs.dart' as emailjs;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/email_config.dart';

class EmailSendOutcome {
  final bool success;
  final String? errorMessage;
  const EmailSendOutcome({required this.success, this.errorMessage});
}

class EmailSendService {
  static final EmailSendService instance = EmailSendService._internal();
  EmailSendService._internal();

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Private Key') ||
        text.contains('strict mode') ||
        text.contains('Forbidden') ||
        text.contains('[403]')) {
      return 'EmailJS Strict Mode is on — copy your Private Key from EmailJS Account > API Keys into email_config.dart.';
    }
    if (text.contains('template ID not found') || text.contains('template_id')) {
      return 'The Template ID is incorrect. Copy it from EmailJS > Email Templates > Settings.';
    }
    if (text.contains('parameters are invalid') || text.contains('[400]')) {
      if (!EmailConfig.isPrivateKeyConfigured) {
        return 'Private Key required. Add it to email_config.dart from EmailJS Account > API Keys.';
      }
      return 'EmailJS parameter error. Save the template and try again.';
    }
    return text.replaceFirst('Exception: ', '').replaceFirst('Error: ', '');
  }

  emailjs.Options get _emailOptions => emailjs.Options(
        publicKey: EmailConfig.emailJsPublicKey,
        privateKey: EmailConfig.isPrivateKeyConfigured
            ? EmailConfig.emailJsPrivateKey
            : null,
      );

  // ── Direct send via Brevo (full control of subject + HTML from code) ──────
  Future<EmailSendOutcome> _sendViaBrevo({
    required String to,
    required String subject,
    required String html,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('https://api.brevo.com/v3/smtp/email'),
            headers: {
              'api-key': EmailConfig.brevoApiKey,
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode({
              'sender': {
                'name': EmailConfig.brevoSenderName,
                'email': EmailConfig.brevoSenderEmail,
              },
              'to': [
                {'email': to}
              ],
              'subject': subject,
              'htmlContent': html,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 || res.statusCode == 201) {
        debugPrint('[Brevo] ✅ email sent to $to');
        return const EmailSendOutcome(success: true);
      }
      debugPrint('[Brevo] ❌ ${res.statusCode}: ${res.body}');
      return EmailSendOutcome(
          success: false, errorMessage: 'Email failed (${res.statusCode})');
    } catch (e) {
      debugPrint('[Brevo] ❌ error: $e');
      return EmailSendOutcome(success: false, errorMessage: e.toString());
    }
  }

  // ── Professional, branded HTML builder ───────────────────────────────────
  // All emails share one clean responsive layout so they look like a real
  // product email, not a raw "verification code" line. The EmailJS template
  // only needs to render {{{message_html}}} (triple braces = raw HTML).

  static const String _brandTeal = '#0E7C7B';
  static const String _alertRed = '#E63946';
  static const String _safeGreen = '#2E9E5B';

  String _shell({
    required String accent,
    required String preheader,
    required String headerTitle,
    required String bodyInner,
  }) {
    return '''
<div style="margin:0;padding:0;background:#f4f6f8;">
  <span style="display:none;max-height:0;overflow:hidden;opacity:0;">$preheader</span>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f8;padding:24px 0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:14px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.06);">
        <tr><td style="background:$accent;padding:22px 28px;">
          <table role="presentation" width="100%"><tr>
            <td style="color:#ffffff;font-size:20px;font-weight:700;letter-spacing:0.3px;">🛡️ SmartSafe</td>
            <td align="right" style="color:rgba(255,255,255,0.85);font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:1px;">$headerTitle</td>
          </tr></table>
        </td></tr>
        <tr><td style="padding:32px 28px;color:#1f2933;font-size:15px;line-height:1.6;">
          $bodyInner
        </td></tr>
        <tr><td style="padding:18px 28px;background:#f0f2f4;color:#90a0ad;font-size:12px;line-height:1.5;text-align:center;">
          This is an automated message from SmartSafe — your personal safety companion.<br/>
          Please do not reply to this email.
        </td></tr>
      </table>
      <div style="color:#aab4bd;font-size:11px;margin-top:14px;">© SmartSafe · One Tap Emergency App</div>
    </td></tr>
  </table>
</div>''';
  }

  String _verificationHtml(String name, String code) => _shell(
        accent: _brandTeal,
        preheader: 'Your SmartSafe verification code is $code',
        headerTitle: 'Account Verification',
        bodyInner: '''
          <p style="margin:0 0 8px;font-size:17px;font-weight:600;">Hi $name,</p>
          <p style="margin:0 0 24px;color:#52606d;">Use the verification code below to confirm your account. This keeps your SmartSafe account secure.</p>
          <div style="text-align:center;margin:0 0 24px;">
            <div style="display:inline-block;background:#e9f5f5;border:1px solid #bfe0df;border-radius:12px;padding:18px 28px;">
              <div style="font-size:34px;font-weight:800;letter-spacing:10px;color:$_brandTeal;">$code</div>
            </div>
          </div>
          <p style="margin:0 0 6px;color:#52606d;">This code expires in <strong>10 minutes</strong>.</p>
          <p style="margin:0;color:#90a0ad;font-size:13px;">If you didn't request this, you can safely ignore this email.</p>
        ''',
      );

  String _sosHtml(String contactName, String senderName, String location,
      [String kind = 'sos']) {
    final isCrash = kind == 'crash';
    final isLink = location.startsWith('http');
    final locationBlock = isLink
        ? '<a href="$location" style="display:inline-block;background:$_alertRed;color:#ffffff;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:10px;font-size:15px;">📍 View live location</a>'
        : '<div style="font-size:15px;color:#1f2933;"><strong>Location:</strong> $location</div>';
    final heading = isCrash
        ? '🚗 $senderName may be in a road accident'
        : '$senderName needs help now';
    final intro = isCrash
        ? 'Hi $contactName, SmartSafe detected a possible crash. Please act immediately.'
        : 'Hi $contactName, an emergency SOS was just triggered from SmartSafe. Please act immediately.';
    return _shell(
      accent: _alertRed,
      preheader: isCrash
          ? '$senderName may have been in a road accident — needs help'
          : '$senderName has triggered an emergency SOS and needs help',
      headerTitle: isCrash ? 'Road Accident Alert' : 'Emergency Alert',
      bodyInner: '''
          <p style="margin:0 0 8px;font-size:20px;font-weight:800;color:$_alertRed;">$heading</p>
          <p style="margin:0 0 18px;color:#52606d;">$intro</p>
          <div style="background:#fdecee;border-left:4px solid $_alertRed;border-radius:8px;padding:16px 18px;margin:0 0 22px;">
            <p style="margin:0 0 12px;font-size:14px;color:#1f2933;">Their last known location:</p>
            $locationBlock
          </div>
          <p style="margin:0 0 6px;font-weight:600;">What you should do:</p>
          <ul style="margin:0 0 14px;padding-left:20px;color:#52606d;">
            <li>Open the live location above to track $senderName.</li>
            <li>Call $senderName right away.</li>
            <li>If you can't reach them, contact emergency services${isCrash ? ' / Rescue 1122' : ''}.</li>
          </ul>
          <p style="margin:0;font-style:italic;color:$_alertRed;font-weight:600;">"Your quick response could save a life."</p>
        ''',
    );
  }

  String _cancelHtml(String contactName, String senderName) => _shell(
        accent: _safeGreen,
        preheader: '$senderName is safe — the previous SOS was cancelled',
        headerTitle: 'All Clear',
        bodyInner: '''
          <p style="margin:0 0 8px;font-size:20px;font-weight:800;color:$_safeGreen;">$senderName is safe</p>
          <p style="margin:0 0 18px;color:#52606d;">Hi $contactName, good news — the earlier emergency SOS from $senderName has been cancelled.</p>
          <div style="background:#eaf7ef;border-left:4px solid $_safeGreen;border-radius:8px;padding:16px 18px;">
            <p style="margin:0;color:#1f2933;">$senderName has marked themselves as <strong>safe</strong>. No further action is needed.</p>
          </div>
        ''',
      );

  // ── Verification email ──────────────────────────────────────────────────

  Future<EmailSendOutcome> sendVerificationCode({
    required String toEmail,
    required String code,
    String? userName,
  }) async {
    if (!EmailConfig.isConfigured) {
      return const EmailSendOutcome(
        success: false,
        errorMessage: 'EmailJS keys missing in lib/config/email_config.dart',
      );
    }

    final email = toEmail.trim();
    final name =
        userName?.trim().isNotEmpty == true ? userName!.trim() : 'SmartSafe User';

    // Preferred: send directly from the app via Brevo (full control, no template).
    if (EmailConfig.isBrevoConfigured) {
      return _sendViaBrevo(
        to: email,
        subject: 'Your SmartSafe verification code',
        html: _verificationHtml(name, code),
      );
    }

    final now = DateTime.now();

    final params = <String, dynamic>{
      'user_email': email,
      'email': email,
      'to_email': email,
      'verification_code': code,
      'code': code,
      'user_name': name,
      'name': name,
      'subject': 'Your SmartSafe verification code',
      'title': 'Verify your SmartSafe account',
      'message':
          'Hi $name, your SmartSafe verification code is $code. It expires in 10 minutes. If you did not request this, please ignore this email.',
      'message_html': _verificationHtml(name, code),
      'time':
          '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      'app_name': 'SmartSafe',
    };

    try {
      await emailjs.send(
          EmailConfig.emailJsServiceId, EmailConfig.emailJsTemplateId, params, _emailOptions);
      debugPrint('[EmailSendService] Verification email sent to $toEmail');
      return const EmailSendOutcome(success: true);
    } catch (e, stack) {
      debugPrint('[EmailSendService] sendVerificationCode failed: $e\n$stack');
      return EmailSendOutcome(success: false, errorMessage: _friendlyError(e));
    }
  }

  // ── SOS Emergency Email ─────────────────────────────────────────────────
  // Sends a real SOS alert email via EmailJS — directly from app, no backend.
  // Works on Android & Web. Free plan of EmailJS supports 200 emails/month.

  Future<EmailSendOutcome> sendSosAlert({
    required String toEmail,
    required String contactName,
    required String senderName,
    required String location,
    String kind = 'sos', // 'sos' | 'crash'
  }) async {
    if (!EmailConfig.isConfigured) {
      return const EmailSendOutcome(
          success: false, errorMessage: 'EmailJS not configured');
    }

    final email = toEmail.trim();
    if (email.isEmpty || !email.contains('@')) {
      return const EmailSendOutcome(
          success: false, errorMessage: 'Invalid email address');
    }

    // SOS emails go ONLY via Brevo (full control of subject + body). We NEVER
    // use the EmailJS verification template here — it is hardcoded with
    // "verification code" text and would send a wrong/confusing email. Without
    // Brevo, the SOS still reaches contacts via SMS + WhatsApp + call (which
    // already include the live location), so we simply skip the email.
    if (!EmailConfig.isBrevoConfigured) {
      debugPrint('[EmailSendService] SOS email skipped (Brevo not configured).');
      return const EmailSendOutcome(
          success: false,
          errorMessage: 'Email skipped — add a Brevo key to enable SOS emails.');
    }
    return _sendViaBrevo(
      to: email,
      subject: kind == 'crash'
          ? 'Road Accident Alert — $senderName may need help'
          : 'Emergency SOS — $senderName needs help',
      html: _sosHtml(contactName, senderName, location, kind),
    );
  }

  // ── SOS Cancel / "I am safe" Email ──────────────────────────────────────
  // Lets contacts know a previous SOS was a false alarm and the sender is safe.

  Future<EmailSendOutcome> sendSosCancel({
    required String toEmail,
    required String contactName,
    required String senderName,
  }) async {
    if (!EmailConfig.isConfigured) {
      return const EmailSendOutcome(
          success: false, errorMessage: 'EmailJS not configured');
    }

    final email = toEmail.trim();
    if (email.isEmpty || !email.contains('@')) {
      return const EmailSendOutcome(
          success: false, errorMessage: 'Invalid email address');
    }

    // Cancel emails also go ONLY via Brevo — never the EmailJS verification
    // template (which would read "verification code: SAFE"). Without Brevo we
    // skip the email; contacts already get the "all clear" via SMS + WhatsApp.
    if (!EmailConfig.isBrevoConfigured) {
      debugPrint('[EmailSendService] Cancel email skipped (Brevo not configured).');
      return const EmailSendOutcome(
          success: false,
          errorMessage: 'Email skipped — add a Brevo key to enable emails.');
    }
    return _sendViaBrevo(
      to: email,
      subject: '$senderName is safe — SmartSafe all clear',
      html: _cancelHtml(contactName, senderName),
    );
  }
}
