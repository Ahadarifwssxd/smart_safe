import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/primary_button.dart';
import '../widgets/otp_code_input.dart';
import '../services/auth_service.dart';
import '../services/email_verification_service.dart';
import '../services/phone_verification_service.dart';
import '../utils/error_message.dart';

class SignupPage extends StatefulWidget {
  final VoidCallback onSignup;
  final VoidCallback onLogin;
  const SignupPage({super.key, required this.onSignup, required this.onLogin});
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _cpass = TextEditingController();
  bool _passVis = false, _cpassVis = false;
  bool _agreed = false;
  bool _loading = false;
  String _gender = 'Female';
  // 1 = personal info, 2 = security, 3 = verify email code, 4 = verify phone code
  int _step = 1;
  static const _totalSteps = 4;

  String _completePhoneNumber = '';
  bool _phoneValid = false;
  String? _nameErr, _emailErr, _phoneErr, _passErr, _cpassErr;
  // The current verification code, shown as a reliable on-screen backup so a
  // slow/undelivered email or SMS can never block signup.
  String? _shownCode;

  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  // Separate boxes for the SMS code (step 4).
  final List<TextEditingController> _smsCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _smsFocus = List.generate(6, (_) => FocusNode());

  // Resend throttle — stops the "Resend code" links from spamming email/SMS.
  int _resendSecs = 0;
  Timer? _resendTimer;

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecs = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendSecs > 0) {
          _resendSecs--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _handleResend(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      if (mounted) _startResendCooldown();
    } catch (e) {
      if (mounted) {
        _snack(friendlyErrorMessage(e, prefix: 'Resend failed:'), C.accent);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shared "Didn't receive? Resend code" link with a live cooldown.
  Widget _resendLink(Future<void> Function() action) {
    final onCooldown = _resendSecs > 0;
    final disabled = _loading || onCooldown;
    return Center(
      child: GestureDetector(
        onTap: disabled ? null : () => _handleResend(action),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: "Didn't receive? ",
                style: TextStyle(color: C.textMuted, fontSize: 13),
              ),
              TextSpan(
                text: onCooldown ? 'Resend in ${_resendSecs}s' : 'Resend code',
                style: TextStyle(
                  color: onCooldown ? C.textDim : C.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    _cpass.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    for (final c in _smsCtrls) {
      c.dispose();
    }
    for (final f in _smsFocus) {
      f.dispose();
    }
    super.dispose();
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d\-.]+$').hasMatch(v.trim());
  bool _isValidName(String v) =>
      RegExp(r'^[a-zA-Z\s]+$').hasMatch(v.trim()) && v.trim().length >= 2;
  bool _isStrongPass(String v) =>
      v.length >= 8 &&
      v.contains(RegExp(r'[A-Z]')) &&
      v.contains(RegExp(r'[0-9]')) &&
      v.contains(RegExp(r'[!@#\$%^&*]'));

  void _showCodeSentMessage(EmailSendResult result) {
    if (!mounted) return;
    final code = result.devCode;
    // Only surface a code on-screen when real email delivery FAILED.
    setState(() => _shownCode = result.emailSent ? null : code);
    if (result.emailSent) {
      _snack(
        'Code sent to ${_email.text.trim()} — check your inbox & spam.',
        C.success,
        duration: const Duration(seconds: 6),
      );
    } else if (code != null && code.isNotEmpty) {
      _snack(
        'Email didn\'t send — use this code to continue: $code',
        C.warning,
        duration: const Duration(seconds: 14),
      );
    } else {
      _snack(
        result.errorMessage ?? 'Could not send the code. Please try again.',
        C.accent,
      );
    }
  }

  void _showSmsCodeMessage(PhoneSendResult result) {
    if (!mounted) return;
    final code = result.devCode;
    // Only surface a code on-screen when real SMS delivery FAILED.
    setState(() => _shownCode = result.smsSent ? null : code);
    if (result.smsSent) {
      _snack(
        'Code sent via SMS to $_completePhoneNumber.',
        C.success,
        duration: const Duration(seconds: 6),
      );
    } else if (code != null && code.isNotEmpty) {
      _snack(
        'SMS didn\'t send — use this code to continue: $code',
        C.warning,
        duration: const Duration(seconds: 14),
      );
    } else {
      _snack(
        result.errorMessage ?? 'Could not send the SMS code. Please try again.',
        C.accent,
      );
    }
  }

  /// Persistent on-screen backup of the current verification code. Email/SMS
  /// delivery is best-effort, so this guarantees the user always has the exact
  /// code to enter and can never get stuck on the verify step.
  Widget _codeBackupHint() {
    final code = _shownCode;
    if (code == null || code.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: C.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.warning.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.vpn_key_rounded, color: C.warning, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Demo code: $code',
                    style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Type this code above to continue. (Real SMS needs a paid plan; '
              'this demo code works free.)',
              style: TextStyle(color: C.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPhoneCode() async {
    // Firebase Phone Auth sends a REAL, FREE OTP from Google's servers — no
    // Twilio, no trial-number limits.
    final result = await PhoneVerificationService.instance
        .sendFirebaseOtp(_completePhoneNumber);
    if (result.smsSent) {
      _showSmsCodeMessage(result);
      return;
    }
    // Firebase couldn't send. Surface the REAL reason (briefly) so setup issues
    // like a missing SHA-256 are diagnosable, then fall back to the legacy path
    // so signup is never fully blocked.
    debugPrint('[Signup] Firebase OTP failed: ${result.errorMessage}');
    if (mounted && (result.errorMessage ?? '').isNotEmpty) {
      _snack('SMS setup issue: ${result.errorMessage}', C.warning,
          duration: const Duration(seconds: 8));
    }
    final fallback = await PhoneVerificationService.instance
        .sendVerificationCode(_completePhoneNumber);
    _showSmsCodeMessage(fallback);
  }

  Future<void> _signupWithGoogle() async {
    setState(() => _loading = true);
    try {
      final cred = await AuthService.instance.signInWithGoogle();
      if (cred != null) {
        if (mounted) {
          setState(() => _loading = false);
          _snack('Welcome to SmartSafe! Logged in with Google.', C.success);
          widget.onSignup();
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(
            friendlyErrorMessage(e, prefix: 'Google sign-up failed:'), C.accent);
      }
    }
  }

  Future<void> _next() async {
    if (_step == 1) {
      String? ne, ee, pe;
      if (_name.text.trim().isEmpty) {
        ne = 'Full name is required';
      } else if (!_isValidName(_name.text)) {
        ne = 'Name must contain only letters and spaces (min 2 chars)';
      }

      if (_email.text.trim().isEmpty) {
        ee = 'Email is required';
      } else if (!_isValidEmail(_email.text)) {
        ee = 'Enter a valid email address';
      }

      if (_phone.text.trim().isEmpty) {
        pe = 'Phone number is required';
      } else if (!_phoneValid) {
        pe = 'Enter a valid phone number';
      }

      if (ne != null || ee != null || pe != null) {
        setState(() {
          _nameErr = ne;
          _emailErr = ee;
          _phoneErr = pe;
        });
        return;
      }

      // One number per person — reject a number another account already verified.
      setState(() {
        _nameErr = _emailErr = _phoneErr = null;
        _loading = true;
      });
      final available = await PhoneVerificationService.instance
          .isPhoneAvailable(_completePhoneNumber);
      if (!mounted) return;
      if (!available) {
        setState(() {
          _loading = false;
          _phoneErr = 'This number is already registered to another account';
        });
        return;
      }
      setState(() {
        _loading = false;
        _step = 2;
      });
    } else if (_step == 2) {
      String? pe, ce;
      if (_pass.text.isEmpty) {
        pe = 'Password is required';
      } else if (!_isStrongPass(_pass.text)) {
        pe = 'Password needs 8+ chars, uppercase, number & special character';
      }

      if (_cpass.text.isEmpty) {
        ce = 'Please confirm your password';
      } else if (_pass.text != _cpass.text) {
        ce = 'Passwords do not match';
      }

      if (pe != null || ce != null) {
        setState(() {
          _passErr = pe;
          _cpassErr = ce;
        });
        return;
      }
      if (!_agreed) {
        _snack(
            'Please agree to the Terms of Service & Privacy Policy', C.warning);
        return;
      }

      setState(() {
        _passErr = _cpassErr = null;
        _loading = true;
      });
      try {
        final result =
            await EmailVerificationService.instance.sendVerificationCode(
          _email.text.trim(),
          userName: _name.text.trim(),
        );
        _showCodeSentMessage(result);
      } catch (e) {
        if (mounted) {
          _snack(friendlyErrorMessage(e, prefix: 'Could not prepare code:'),
              C.accent);
        }
      } finally {
        if (mounted) {
          setState(() {
            _loading = false;
            _step = 3;
          });
        }
      }
    } else if (_step == 3) {
      // Verify EMAIL code, then text the phone code and advance to step 4.
      final code =
          _otpCtrls.map((c) => c.text).join().replaceAll(RegExp(r'\D'), '');
      if (code.length != 6) {
        _snack('Please enter the complete 6-digit email code', C.accent);
        return;
      }

      setState(() => _loading = true);
      try {
        final valid = await EmailVerificationService.instance.verifyCode(
          _email.text.trim(),
          code,
        );
        if (!valid) {
          if (mounted) {
            setState(() => _loading = false);
            _snack('Invalid email code. Please try again.', C.accent);
          }
          return;
        }

        await _sendPhoneCode();
        if (mounted) {
          setState(() {
            _loading = false;
            _step = 4;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loading = false);
          _snack(friendlyErrorMessage(e), C.accent);
        }
      }
    } else {
      // Step 4 — verify PHONE code, then create the account (both verified).
      final code =
          _smsCtrls.map((c) => c.text).join().replaceAll(RegExp(r'\D'), '');
      if (code.length != 6) {
        _snack('Please enter the complete 6-digit SMS code', C.accent);
        return;
      }

      setState(() => _loading = true);
      try {
        final svc = PhoneVerificationService.instance;

        // Re-check uniqueness right before claiming, to close the race where two
        // people verify the same number at once.
        final stillAvailable =
            await svc.isPhoneAvailable(_completePhoneNumber);
        if (!stillAvailable) {
          if (mounted) {
            setState(() => _loading = false);
            _snack('This number was just registered by someone else.', C.accent);
          }
          return;
        }

        // ── Preferred: Firebase Phone Auth (free, real SMS) ──────────────────
        // Firebase itself validates the OTP when the credential is used, so a
        // wrong code throws BEFORE any account is created.
        final phoneCred =
            svc.autoCredential ?? svc.credentialForCode(code);
        if (svc.hasFirebaseCode && phoneCred != null) {
          await AuthService.instance.signUpWithPhoneCredential(
            phoneCredential: phoneCred,
            email: _email.text.trim(),
            password: _pass.text,
            name: _name.text.trim(),
            phone: _completePhoneNumber,
            gender: _gender,
          );
        } else {
          // ── Fallback: legacy Twilio/dev-code path ──────────────────────────
          final valid = await svc.verifyCode(_completePhoneNumber, code);
          if (!valid) {
            if (mounted) {
              setState(() => _loading = false);
              _snack('Invalid SMS code. Please try again.', C.accent);
            }
            return;
          }
          await AuthService.instance.signUp(
            email: _email.text.trim(),
            password: _pass.text,
            name: _name.text.trim(),
            phone: _completePhoneNumber,
            gender: _gender,
            phoneVerified: true,
          );
        }

        if (mounted) {
          setState(() => _loading = false);
          _snack('Signup successful! Welcome to SmartSafe.', C.success);
          widget.onSignup();
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          setState(() => _loading = false);
          _snack(
            e.code == 'invalid-verification-code'
                ? 'Invalid SMS code. Please try again.'
                : friendlyErrorMessage(e),
            C.accent,
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loading = false);
          _snack(friendlyErrorMessage(e), C.accent);
        }
      }
    }
  }

  void _snack(String msg, Color color, {Duration? duration}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(msg, style: TextStyle(color: C.textPrimary)),
      ));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          backgroundColor: C.bg,
          elevation: 0,
          leading: _step > 1
              ? IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 18, color: C.textPrimary),
                  onPressed: () => setState(() => _step--),
                )
              : IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 18, color: C.textPrimary),
                  onPressed: widget.onLogin,
                ),
          title: Text('Step $_step of $_totalSteps',
              style: TextStyle(color: C.textMuted, fontSize: 13)),
        ),
        body: Stack(
          children: [
            const DotGrid(),
            SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(
                        _totalSteps,
                        (i) => Expanded(
                          child: Container(
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i < _step ? C.accent : C.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_step == 1) ...[
                      SlideUpFade(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DynText(
                              'signup',
                              'heading',
                              'Create account',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            DynText(
                              'signup',
                              'subheading',
                              'Your safety starts here',
                              style: TextStyle(color: C.textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 28),
                            Center(
                              // Live initial-letter avatar (updates as the name
                              // is typed). Profile photos are added later in
                              // Settings, so there's no misleading "add photo"
                              // affordance here.
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: C.accent,
                                child: Text(
                                  _name.text.trim().isEmpty
                                      ? '?'
                                      : _name.text.trim()[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _name,
                              onChanged: (_) {
                                setState(() {});
                                if (_nameErr != null) {
                                  setState(() => _nameErr = null);
                                }
                              },
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: const Icon(Icons.person_rounded),
                                errorText: _nameErr,
                              ),
                              style: TextStyle(color: C.textPrimary),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) {
                                if (_emailErr != null) {
                                  setState(() => _emailErr = null);
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Email address',
                                hintText: 'example@domain.com',
                                prefixIcon: const Icon(Icons.email_rounded),
                                errorText: _emailErr,
                              ),
                              style: TextStyle(color: C.textPrimary),
                            ),
                            const SizedBox(height: 16),
                            IntlPhoneField(
                              controller: _phone,
                              initialCountryCode: 'PK',
                              showCountryFlag: false,
                              dropdownTextStyle: TextStyle(color: C.textPrimary),
                              style: TextStyle(color: C.textPrimary),
                              pickerDialogStyle: PickerDialogStyle(
                                backgroundColor: C.bg2,
                                countryNameStyle: TextStyle(color: C.textPrimary),
                                countryCodeStyle: TextStyle(color: C.textMuted),
                                searchFieldInputDecoration: InputDecoration(
                                  hintText: 'Search country',
                                  hintStyle: TextStyle(color: C.textMuted),
                                  prefixIcon: Icon(Icons.search, color: C.textMuted),
                                ),
                              ),
                              onChanged: (phone) {
                                _completePhoneNumber = phone.completeNumber;
                                try {
                                  _phoneValid = phone.isValidNumber();
                                } catch (_) {
                                  _phoneValid = false;
                                }
                                if (_phoneErr != null) {
                                  setState(() => _phoneErr = null);
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Phone number',
                                hintText: '3XXXXXXXXX',
                                errorText: _phoneErr,
                                // Hide the built-in "0/10" length counter.
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 16),
                            const SecHeader('I am'),
                            Row(
                              children: ['Female', 'Male', 'Other'].map((g) {
                                final sel = g == _gender;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3),
                                    child: GestureDetector(
                                      onTap: () => setState(() => _gender = g),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        decoration: BoxDecoration(
                                          color: sel ? C.accent : C.bg2,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: sel ? C.accent : C.textDim),
                                        ),
                                        child: Text(
                                          g,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: sel ? Colors.white : C.textMuted,
                                            fontSize: 13,
                                            fontWeight: sel
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(child: Divider(color: C.border)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Text('or',
                                      style: TextStyle(
                                          color: C.textMuted, fontSize: 12)),
                                ),
                                Expanded(child: Divider(color: C.border)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            GoogleSignInButton(
                              loading: _loading,
                              onPressed: _signupWithGoogle,
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_step == 2) ...[
                      SlideUpFade(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Set your password',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'We will email a verification code next',
                              style: TextStyle(color: C.textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 28),
                            TextField(
                              controller: _pass,
                              obscureText: !_passVis,
                              onChanged: (_) {
                                setState(() {});
                                if (_passErr != null) {
                                  setState(() => _passErr = null);
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_rounded),
                                errorText: _passErr,
                                suffixIcon: IconButton(
                                  tooltip: _passVis
                                      ? 'Hide password'
                                      : 'Show password',
                                  onPressed: () =>
                                      setState(() => _passVis = !_passVis),
                                  icon: Icon(
                                    _passVis
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: C.textMuted,
                                  ),
                                ),
                              ),
                              style: TextStyle(color: C.textPrimary),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _cpass,
                              obscureText: !_cpassVis,
                              onChanged: (_) {
                                if (_cpassErr != null) {
                                  setState(() => _cpassErr = null);
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Confirm password',
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                errorText: _cpassErr,
                                suffixIcon: IconButton(
                                  tooltip: _cpassVis
                                      ? 'Hide password'
                                      : 'Show password',
                                  onPressed: () =>
                                      setState(() => _cpassVis = !_cpassVis),
                                  icon: Icon(
                                    _cpassVis
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: C.textMuted,
                                  ),
                                ),
                              ),
                              style: TextStyle(color: C.textPrimary),
                            ),
                            const SizedBox(height: 16),
                            if (_pass.text.isNotEmpty)
                              _PasswordStrength(password: _pass.text),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () => setState(() => _agreed = !_agreed),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: _agreed ? C.accent : C.bg2,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: _agreed ? C.accent : C.textDim),
                                    ),
                                    child: _agreed
                                        ? Icon(Icons.check_rounded,
                                            size: 14, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'I agree to SmartSafe\'s ',
                                            style: TextStyle(
                                                color: C.textMuted, fontSize: 12),
                                          ),
                                          TextSpan(
                                            text: 'Terms of Service',
                                            style: TextStyle(
                                              color: C.accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          TextSpan(
                                            text: ' and ',
                                            style: TextStyle(
                                                color: C.textMuted, fontSize: 12),
                                          ),
                                          TextSpan(
                                            text: 'Privacy Policy',
                                            style: TextStyle(
                                              color: C.accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_step == 3) ...[
                      SlideUpFade(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verify your email',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Enter the 6-digit code sent to ${_email.text.trim()}',
                              style: TextStyle(color: C.textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 36),
                            OtpCodeInput(
                              controllers: _otpCtrls,
                              focusNodes: _otpFocus,
                            ),
                            _codeBackupHint(),
                            const SizedBox(height: 28),
                            _resendLink(() async {
                              final result = await EmailVerificationService
                                  .instance
                                  .sendVerificationCode(
                                _email.text.trim(),
                                userName: _name.text.trim(),
                              );
                              _showCodeSentMessage(result);
                            }),
                          ],
                        ),
                      ),
                    ],
                    if (_step == 4) ...[
                      SlideUpFade(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verify your phone',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Enter the 6-digit code sent by SMS to $_completePhoneNumber',
                              style: TextStyle(color: C.textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 36),
                            OtpCodeInput(
                              controllers: _smsCtrls,
                              focusNodes: _smsFocus,
                            ),
                            _codeBackupHint(),
                            const SizedBox(height: 28),
                            _resendLink(_sendPhoneCode),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    PrimaryButton(
                      loading: _loading,
                      onPressed: _next,
                      label: _step == 4
                          ? 'Verify & Create Account'
                          : _step == 3
                              ? 'Verify Email'
                              : 'Next',
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: GestureDetector(
                        onTap: widget.onLogin,
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Already have an account? ',
                                style: TextStyle(color: C.textMuted, fontSize: 14),
                              ),
                              TextSpan(
                                text: 'Login',
                                style: TextStyle(
                                  color: C.accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
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

class _PasswordStrength extends StatelessWidget {
  final String password;
  const _PasswordStrength({required this.password});

  int get _strength {
    int s = 0;
    if (password.length >= 8) s++;
    if (password.contains(RegExp(r'[A-Z]'))) s++;
    if (password.contains(RegExp(r'[0-9]'))) s++;
    if (password.contains(RegExp(r'[!@#\$%^&*]'))) s++;
    return s;
  }

  Color get _color => _strength <= 1
      ? C.accent
      : _strength <= 2
          ? C.warning
          : C.success;
  String get _label => _strength <= 1
      ? 'Weak'
      : _strength <= 2
          ? 'Medium'
          : _strength <= 3
              ? 'Strong'
              : 'Very Strong';

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Password strength',
                  style: TextStyle(color: C.textMuted, fontSize: 11)),
              Text(_label,
                  style: TextStyle(
                      color: _color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i < _strength ? _color : C.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _Check('8+ characters', password.length >= 8),
              _Check('Uppercase', password.contains(RegExp(r'[A-Z]'))),
              _Check('Number', password.contains(RegExp(r'[0-9]'))),
              _Check('Special char', password.contains(RegExp(r'[!@#\$%^&*]'))),
            ],
          ),
        ],
      );
}

class _Check extends StatelessWidget {
  final String label;
  final bool ok;
  const _Check(this.label, this.ok);
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 12,
            color: ok ? C.success : C.textMuted,
          ),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(color: ok ? C.success : C.textMuted, fontSize: 10)),
        ],
      );
}
