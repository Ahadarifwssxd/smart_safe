/// EmailJS: https://dashboard.emailjs.com/
///
/// Required values copied exactly from the dashboard:
/// - Service ID: Email Services → Gmail card
/// - Template ID: Email Templates → template kholo → Template ID (Settings)
/// - Public Key: Account → API Keys
///
/// Agar "strict mode" / Private Key error aaye:
/// - Account → API Keys → Private Key copy → emailJsPrivateKey neeche
///   YA Account → Security → strict mode off / allow browser API
class EmailConfig {
  static const String emailJsPublicKey = 'FJ3TE1EhXKRx1kNEP';
  static const String emailJsServiceId = 'service_f9m9jjk';

  /// Contact Us template (edited for verification)
  static const String emailJsTemplateId = 'template_hm96mph';

  /// Required: paste Account > API Keys > Private Key here.
  /// Example: 'ABC123XYZ456DEFG'
  static const String emailJsPrivateKey =
      '0JtvUkoQECcGOi2efEiRs'; // Paste your real private key here.

  // ── Direct email from Flutter (Brevo) — full control of subject + HTML,
  //    NO EmailJS dashboard template needed. Free 300 emails/day.
  //    Setup (one time):
  //      1. Sign up free at https://www.brevo.com
  //      2. Settings → SMTP & API → API Keys → create a key → paste below.
  //      3. Senders → add & verify your email (e.g. your Gmail) → paste below.
  //    Once both are set, the app sends emails directly (correct subject + body).
  static const String brevoApiKey = ''; // paste your Brevo API key here
  static const String brevoSenderEmail = ''; // your verified sender email
  static const String brevoSenderName = 'SmartSafe';

  static bool get isBrevoConfigured =>
      brevoApiKey.isNotEmpty && brevoSenderEmail.isNotEmpty;

  static bool get isConfigured =>
      isBrevoConfigured ||
      (emailJsPublicKey.isNotEmpty &&
          emailJsServiceId.isNotEmpty &&
          emailJsTemplateId.isNotEmpty);

  /// Returns true only if a real key is set (not empty, not a placeholder with dots)
  static bool get isPrivateKeyConfigured =>
      emailJsPrivateKey.isNotEmpty && !emailJsPrivateKey.contains('•');
}
