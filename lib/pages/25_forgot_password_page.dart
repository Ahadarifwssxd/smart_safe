import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../widgets/primary_button.dart';
import '../services/email_verification_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  final VoidCallback onBack;
  const ForgotPasswordPage({super.key, required this.onBack});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  int _step = 1; // 1=enter email, 2=OTP, 3=done (Firebase sends reset link)
  final _email = TextEditingController();
  bool _loading = false;
  String? _emailError;

  // OTP
  final List<TextEditingController> _otp =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  // Resend countdown
  int _resendCountdown = 0;
  Timer? _resendTimer;
  bool get _canResend => _resendCountdown == 0;

  // Tracks what email the OTP was sent to
  String _sentToEmail = '';

  @override
  void dispose() {
    _email.dispose();
    for (final c in _otp) { c.dispose(); }
    for (final f in _otpFocus) { f.dispose(); }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(msg, style: TextStyle(color: C.textPrimary)),
      ));

  // ── Step 1: Send OTP via EmailVerificationService ──────────────────
  Future<void> _sendOtp() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _emailError = 'Enter a valid email address');
      return;
    }
    setState(() => _loading = true);

    try {
      // Instead of querying Firestore which causes permission-denied for unauthenticated users,
      // we just attempt to send the OTP. If the user doesn't exist, they still get an OTP
      // but the reset link sent later won't do anything harmful.

      final result = await EmailVerificationService.instance
          .sendVerificationCode(email, userName: 'SmartSafe User');

      if (!mounted) return;
      setState(() => _loading = false);

      if (result.emailSent) {
        _sentToEmail = email;
        _snack('OTP sent to $email', C.success);
      } else {
        // In debug mode devCode is available; show fallback info
        final extra = result.devCode != null
            ? ' (Dev code: ${result.devCode})'
            : '';
        _snack(
          'OTP generated${result.errorMessage != null ? " — email failed: ${result.errorMessage}" : ""}$extra',
          result.devCode != null ? C.warning : C.accent,
        );
        _sentToEmail = email;
      }
      setState(() => _step = 2);
      _startResendTimer();

      // Auto-focus first OTP box
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _otpFocus[0].requestFocus();
      });
    } catch (e) {
      debugPrint('Error in _sendOtp: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('An error occurred: $e', C.accent);
    }
  }

  // ── Step 2: Verify OTP ─────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    final entered = _otp.map((c) => c.text).join();
    if (entered.length < 6) {
      _snack('Enter the complete 6-digit OTP', C.accent);
      return;
    }
    setState(() => _loading = true);

    try {
      final valid = await EmailVerificationService.instance
          .verifyCode(_sentToEmail, entered);

      if (!mounted) return;
      setState(() => _loading = false);

      if (valid) {
        // Send Firebase password reset email
        await FirebaseAuth.instance.sendPasswordResetEmail(email: _sentToEmail);
        setState(() => _step = 3);
        _snack('OTP verified! Password reset link sent to $_sentToEmail', C.success);
      } else {
        _snack('Incorrect OTP. Please try again.', C.accent);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('$e', C.accent);
    }
  }

  // ── Resend OTP ──────────────────────────────────────────────────────
  Future<void> _resend() async {
    if (!_canResend) return;
    for (final c in _otp) { c.clear(); }
    setState(() {});
    await _sendOtp();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          backgroundColor: C.bg,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded, size: 18, color: C.textPrimary),
            onPressed: _step > 1 && _step < 3
                ? () => setState(() => _step--)
                : widget.onBack,
          ),
          title: Text(
            'Reset Password',
            style: TextStyle(
              color: C.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: Stack(
          children: [
            const DotGrid(),
            SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step indicator
                    Row(
                      children: List.generate(
                        3,
                        (i) => Expanded(
                          child: Container(
                            height: 4,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i < _step ? C.accent : C.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Step 1: Email ───────────────────────────────────
                    if (_step == 1)
                      SlideUpFade(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: C.accent.withValues(alpha: .15),
                                ),
                                child: Icon(Icons.email_rounded,
                                    color: C.accent, size: 38),
                              ),
                            ),
                            const SizedBox(height: 28),
                            DynText(
                              'forgot_password',
                              'heading',
                              'Forgot password?',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DynText(
                              'forgot_password',
                              'subheading',
                              'Enter your registered email. We\'ll send a 6-digit OTP to verify your identity.',
                              style: TextStyle(
                                  color: C.textMuted, fontSize: 13, height: 1.5),
                            ),
                            const SizedBox(height: 28),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              onChanged: (_) {
                                if (_emailError != null) {
                                  setState(() => _emailError = null);
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Email address',
                                hintText: 'example@domain.com',
                                prefixIcon:
                                    const Icon(Icons.alternate_email_rounded),
                                errorText: _emailError,
                              ),
                              style: TextStyle(color: C.textPrimary),
                            ),
                            const SizedBox(height: 16),
                            DCard(
                              borderColor: C.accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(children: [
                                Icon(Icons.info_outline_rounded,
                                    color: C.accent, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'A 6-digit OTP will be sent to your email. Valid for 10 minutes.',
                                    style:
                                        TextStyle(color: C.textMuted, fontSize: 11),
                                  ),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),

                    // ── Step 2: OTP ────────────────────────────────────
                    if (_step == 2)
                      SlideUpFade(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: C.accent.withValues(alpha: .15),
                                ),
                                child: Icon(Icons.mark_email_read_rounded,
                                    color: C.accent, size: 38),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Enter OTP',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                  text: '6-digit OTP sent to ',
                                  style: TextStyle(
                                      color: C.textMuted, fontSize: 13),
                                ),
                                TextSpan(
                                  text: _sentToEmail,
                                  style: TextStyle(
                                      color: C.accent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 32),

                            // 6-digit OTP boxes
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                6,
                                (i) => Expanded(
                                  child: Container(
                                  height: 54,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: C.bg2,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _otp[i].text.isNotEmpty
                                          ? C.accent
                                          : C.textDim,
                                      width:
                                          _otp[i].text.isNotEmpty ? 1.5 : 1,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _otp[i],
                                    focusNode: _otpFocus[i],
                                    maxLength: 1,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(
                                      color: C.textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    decoration: const InputDecoration(
                                      counterText: '',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (v) {
                                      setState(() {});
                                      if (v.isNotEmpty && i < 5) {
                                        _otpFocus[i + 1].requestFocus();
                                      }
                                      if (v.isEmpty && i > 0) {
                                        _otpFocus[i - 1].requestFocus();
                                      }
                                      // Auto-verify on last digit
                                      if (i == 5 && v.isNotEmpty) {
                                        final full =
                                            _otp.map((c) => c.text).join();
                                        if (full.length == 6) _verifyOtp();
                                      }
                                    },
                                  ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Resend row
                            Center(
                              child: GestureDetector(
                                onTap: _canResend ? _resend : null,
                                child: RichText(
                                  text: TextSpan(children: [
                                    TextSpan(
                                      text: 'Didn\'t receive? ',
                                      style: TextStyle(
                                          color: C.textMuted, fontSize: 13),
                                    ),
                                    TextSpan(
                                      text: _canResend
                                          ? 'Resend OTP'
                                          : 'Resend in ${_resendCountdown}s',
                                      style: TextStyle(
                                        color: _canResend ? C.accent : C.textDim,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Step 3: Done ───────────────────────────────────
                    if (_step == 3)
                      SlideUpFade(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: C.success.withValues(alpha: .15),
                                ),
                                child: Icon(Icons.check_circle_rounded,
                                    color: C.success, size: 48),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Center(
                              child: Text(
                                'Check your email!',
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                'A password reset link has been sent to\n$_sentToEmail',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: C.textMuted, fontSize: 13, height: 1.6),
                              ),
                            ),
                            const SizedBox(height: 24),
                            DCard(
                              borderColor: C.success,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(children: [
                                Icon(Icons.info_outline_rounded,
                                    color: C.success, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Open the link in your email, set a new password, then come back and login.',
                                    style:
                                        TextStyle(color: C.textMuted, fontSize: 12),
                                  ),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 32),

                    // Action Button
                    if (_step < 3)
                      PrimaryButton(
                        loading: _loading,
                        onPressed: _step == 1 ? _sendOtp : _verifyOtp,
                        label: _step == 1 ? 'Send OTP' : 'Verify OTP',
                      ),

                    const SizedBox(height: 24),

                    Center(
                      child: GestureDetector(
                        onTap: widget.onBack,
                        child: RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: _step == 3
                                  ? 'Back to '
                                  : 'Remember password? ',
                              style:
                                  TextStyle(color: C.textMuted, fontSize: 14),
                            ),
                            TextSpan(
                              text: 'Login',
                              style: TextStyle(
                                color: C.accent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
