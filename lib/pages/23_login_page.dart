import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/primary_button.dart';
import '../services/auth_service.dart';
import '../utils/error_message.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLogin;
  final VoidCallback onSignup;
  final VoidCallback onForgot;
  const LoginPage({super.key, required this.onLogin, required this.onSignup, required this.onForgot});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _passVisible = false;
  bool _loading = false;
  String? _emailError;
  String? _passError;
  // Google sign-in failures are shown as an inline banner inside the scroll
  // view (never a bottom overlay) so buttons stay visible and tappable.
  String? _googleError;
  late AnimationController _logoCtrl;
  late Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
    _logoScale = CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut);
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d\-.]+$').hasMatch(v.trim());

  @override
  void dispose() {
    _logoCtrl.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    String? emailErr, passErr;

    if (email.isEmpty) {
      emailErr = 'Email is required';
    } else if (!_isValidEmail(email)) {
      emailErr = 'Enter a valid email address';
    }

    if (pass.isEmpty) {
      passErr = 'This field is required';
    } else if (pass.length < 6) {
      passErr = 'Password must be at least 6 characters';
    }

    if (emailErr != null || passErr != null) {
      setState(() {
        _emailError = emailErr;
        _passError = passErr;
      });
      return;
    }

    setState(() {
      _emailError = null;
      _passError = null;
      _loading = true;
    });
    try {
      await AuthService.instance.signIn(email: email, password: pass);
      if (mounted) {
        setState(() => _loading = false);
        widget.onLogin();
      }
    } catch (e) {
      if (mounted) {
        final msg = friendlyErrorMessage(e);
        setState(() {
          _loading = false;
          _passError = msg;
        });
        ScaffoldMessenger.of(context).showSnackBar(_snack(msg, C.accent));
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _loading = true;
      _googleError = null;
    });
    try {
      final cred = await AuthService.instance.signInWithGoogle();
      if (cred != null) {
        if (mounted) {
          setState(() => _loading = false);
          widget.onLogin();
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        // Inline banner instead of a bottom overlay so it pushes layout and
        // never covers the "Continue with Google" button.
        setState(() {
          _loading = false;
          _googleError = friendlyErrorMessage(e);
        });
      }
    }
  }

  SnackBar _snack(String msg, Color color) => SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(msg, style: TextStyle(color: Colors.white)),
      );

  /// Inline, dismissible error card shown inside the scroll view. It flows with
  /// the column (pushing content down) so it can never overlay the buttons.
  Widget _inlineError(String msg) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: C.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: C.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _googleError = null),
              behavior: HitTestBehavior.opaque,
              child: Icon(Icons.close_rounded, color: C.textMuted, size: 18),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final isSmall = screenH < 700;
    return Scaffold(
        backgroundColor: C.bg,
        body: Stack(
          children: [
            const DotGrid(),
            SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: isSmall ? 12 : 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: isSmall ? 16 : 30),
                    Center(
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Column(
                          children: [
                            // Splash-screen style logo
                            PulseRing(
                              size: isSmall ? 70 : 90,
                              color: C.accent,
                              rings: 2,
                              child: Container(
                                width: isSmall ? 62 : 80,
                                height: isSmall ? 62 : 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: AppTheme.sosGradient,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x55000000),
                                      blurRadius: 24,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.health_and_safety_rounded,
                                      color: Colors.white,
                                      size: isSmall ? 26 : 34,
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'SOS',
                                      style: TextStyle(
                                        fontSize: isSmall ? 11 : 13,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: isSmall ? 10 : 16),
                            DynText(
                              'login',
                              'brand',
                              'SmartSafe',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: isSmall ? 24 : 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            DynText(
                              'login',
                              'tagline',
                              'Stay protected. Always.',
                              style: TextStyle(color: C.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: isSmall ? 24 : 44),
                    SlideUpFade(
                      delay: const Duration(milliseconds: 200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DynText(
                            'login',
                            'heading',
                            'Welcome back',
                            style: TextStyle(
                              color: C.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          DynText(
                            'login',
                            'subheading',
                            'Login with your email',
                            style: TextStyle(color: C.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SlideUpFade(
                      delay: const Duration(milliseconds: 280),
                      child: Column(
                        children: [
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            onChanged: (_) {
                              if (_emailError != null) setState(() => _emailError = null);
                            },
                            decoration: InputDecoration(
                              labelText: 'Email address',
                              hintText: 'example@domain.com',
                              prefixIcon: const Icon(Icons.email_rounded),
                              errorText: _emailError,
                            ),
                            style: TextStyle(color: C.textPrimary),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _pass,
                            obscureText: !_passVisible,
                            onChanged: (_) {
                              if (_passError != null) setState(() => _passError = null);
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_rounded),
                              errorText: _passError,
                              suffixIcon: IconButton(
                                tooltip: _passVisible ? 'Hide password' : 'Show password',
                                onPressed: () =>
                                    setState(() => _passVisible = !_passVisible),
                                icon: Icon(
                                  _passVisible
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: C.textMuted,
                                ),
                              ),
                            ),
                            style: TextStyle(color: C.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SlideUpFade(
                      delay: const Duration(milliseconds: 320),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: widget.onForgot,
                          child: DynText(
                            'login',
                            'forgotPassword',
                            'Forgot password?',
                            style: TextStyle(
                              color: C.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SlideUpFade(
                      delay: const Duration(milliseconds: 360),
                      child: PrimaryButton(
                        loading: _loading,
                        onPressed: _login,
                        label: PageContentService.instance
                            .text('login', 'loginButton', 'Login'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SlideUpFade(
                      delay: const Duration(milliseconds: 400),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: C.border)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or continue with',
                              style: TextStyle(color: C.textMuted, fontSize: 12),
                            ),
                          ),
                          Expanded(child: Divider(color: C.border)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_googleError != null)
                      _inlineError(_googleError!),
                    SlideUpFade(
                      delay: const Duration(milliseconds: 440),
                      child: GoogleSignInButton(
                        loading: _loading,
                        onPressed: _loginWithGoogle,
                        label: PageContentService.instance.text(
                          'login',
                          'googleButton',
                          'Continue with Google',
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SlideUpFade(
                      delay: const Duration(milliseconds: 480),
                      child: Center(
                        child: GestureDetector(
                          onTap: widget.onSignup,
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Don\'t have an account? ',
                                  style: TextStyle(color: C.textMuted, fontSize: 14),
                                ),
                                TextSpan(
                                  text: 'Sign Up',
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
}
