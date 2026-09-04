import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/phone_verification_service.dart';
import '../services/user_profile_service.dart';
import '../theme/colors.dart';
import '../utils/error_message.dart';
import '../widgets/otp_code_input.dart';
import '../widgets/primary_button.dart';
import '../widgets/widgets.dart';

/// Blocks the app until the signed-in user has a VERIFIED phone number.
///
/// Used for Google sign-ups (which never collect a phone) and any older
/// account that predates phone verification. On success it writes
/// `phone` + `phoneVerified: true` to the profile and calls [onVerified].
class PhoneVerifyGatePage extends StatefulWidget {
  /// Called once the phone number has been verified + saved.
  final VoidCallback onVerified;

  /// Lets the user sign out instead (e.g. wrong account).
  final Future<void> Function()? onLogout;

  const PhoneVerifyGatePage({
    super.key,
    required this.onVerified,
    this.onLogout,
  });

  @override
  State<PhoneVerifyGatePage> createState() => _PhoneVerifyGatePageState();
}

class _PhoneVerifyGatePageState extends State<PhoneVerifyGatePage> {
  final _phone = TextEditingController();
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  UserProfile? _profile;
  bool _loading = false;
  bool _codeSent = false;
  String _completePhoneNumber = '';
  bool _phoneValid = false;
  String? _phoneErr;

  @override
  void initState() {
    super.initState();
    UserProfileService.instance.getCurrentProfile().then((p) {
      if (!mounted) return;
      setState(() => _profile = p);
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    super.dispose();
  }

  void _snack(String msg, Color color, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: duration ?? const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Text(msg, style: TextStyle(color: C.textPrimary)),
    ));
  }

  Future<void> _sendCode() async {
    if (_phone.text.trim().isEmpty || !_phoneValid) {
      setState(() => _phoneErr = 'Enter a valid phone number');
      return;
    }
    setState(() {
      _phoneErr = null;
      _loading = true;
    });

    // One number per person.
    final available = await PhoneVerificationService.instance
        .isPhoneAvailable(_completePhoneNumber, forUid: _profile?.uid);
    if (!mounted) return;
    if (!available) {
      setState(() {
        _loading = false;
        _phoneErr = 'This number is already registered to another account';
      });
      return;
    }

    try {
      final result = await PhoneVerificationService.instance
          .sendVerificationCode(_completePhoneNumber);
      if (!mounted) return;
      if (result.smsSent) {
        _snack('Code sent via SMS to $_completePhoneNumber', C.success);
      } else if (result.devCode != null) {
        _snack('SMS busy — use this code: ${result.devCode}', C.warning,
            duration: const Duration(seconds: 14));
      } else {
        _snack(result.errorMessage ?? 'Could not send the code.', C.accent);
      }
      setState(() {
        _loading = false;
        _codeSent = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(friendlyErrorMessage(e, prefix: 'Could not send code:'), C.accent);
      }
    }
  }

  Future<void> _verify() async {
    final code =
        _otpCtrls.map((c) => c.text).join().replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      _snack('Please enter the complete 6-digit code', C.accent);
      return;
    }
    setState(() => _loading = true);
    try {
      final valid = await PhoneVerificationService.instance
          .verifyCode(_completePhoneNumber, code);
      if (!valid) {
        if (mounted) {
          setState(() => _loading = false);
          _snack('Invalid code. Please try again.', C.accent);
        }
        return;
      }

      // Race guard before claiming the number.
      final stillFree = await PhoneVerificationService.instance
          .isPhoneAvailable(_completePhoneNumber, forUid: _profile?.uid);
      if (!stillFree) {
        if (mounted) {
          setState(() => _loading = false);
          _snack('This number was just registered by someone else.', C.accent);
        }
        return;
      }

      final p = _profile;
      await UserProfileService.instance.updateProfile(
        name: p?.name ?? AuthService.instance.currentUser?.displayName ?? '',
        email: p?.email ?? AuthService.instance.currentUser?.email ?? '',
        phone: _completePhoneNumber,
        gender: p?.gender,
        bloodGroup: p?.bloodGroup,
        phoneVerified: true,
      );

      if (mounted) {
        setState(() => _loading = false);
        _snack('Phone verified! Welcome to SmartSafe.', C.success);
        widget.onVerified();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(friendlyErrorMessage(e), C.accent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          const DotGrid(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Icon(Icons.sms_rounded, color: C.accent, size: 40),
                  const SizedBox(height: 16),
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
                    _codeSent
                        ? 'Enter the 6-digit code sent by SMS to $_completePhoneNumber'
                        : 'A verified phone number is required to keep your account secure and to reach you in an emergency.',
                    style: TextStyle(color: C.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  if (!_codeSent) ...[
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
                      ),
                    ),
                  ] else ...[
                    OtpCodeInput(controllers: _otpCtrls, focusNodes: _otpFocus),
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: _loading ? null : _sendCode,
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: "Didn't receive? ",
                                style:
                                    TextStyle(color: C.textMuted, fontSize: 13),
                              ),
                              TextSpan(
                                text: 'Resend SMS',
                                style: TextStyle(
                                  color: C.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  PrimaryButton(
                    loading: _loading,
                    onPressed: _codeSent ? _verify : _sendCode,
                    label: _codeSent ? 'Verify & Continue' : 'Send Code',
                  ),
                  if (widget.onLogout != null) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: _loading ? null : () => widget.onLogout!.call(),
                        child: Text(
                          'Sign out',
                          style: TextStyle(
                            color: C.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
