import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

class AdminLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const AdminLoginScreen({Key? key, required this.onLoginSuccess}) : super(key: key);

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailPhoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final input = _emailPhoneController.text.trim();
    final password = _passwordController.text;
    bool success = false;
    String? error;

    if (input.contains('@')) {
      final email = input.toLowerCase();
      try {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (cred.user != null) {
          final isAdmin = await FirebaseService.instance.userHasAdminRole(cred.user!.uid);
          if (isAdmin) {
            success = true;
          } else {
            await FirebaseAuth.instance.signOut();
            error =
                'Not an admin. Use dashboard → Users & Roles to promote this account, or login with admin credentials.';
          }
        }
      } on FirebaseAuthException catch (e) {
        final legacyOk =
            await FirebaseService.instance.validateAdminCredentials(input, password);
        if (legacyOk) {
          success = true;
        } else {
          error = friendlyErrorMessage(e);
        }
      }
    } else {
      success = await FirebaseService.instance.validateAdminCredentials(input, password);
      if (!success) error = 'Invalid phone or password';
    }

    if (success && FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = success ? null : error ?? 'Login failed. Please try again.';
      });
      if (success) widget.onLoginSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 768;

    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(defaultPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: C.accent.withValues(alpha: 0.1),
                  border: Border.all(color: C.accent.withValues(alpha: 0.4), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: C.accent.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: C.accent,
                  size: 45,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "SmartSafe Admin Portal",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: C.textPrimary,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                "Login with admin email (Firebase) or legacy admin credentials",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: C.textMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 35),
              Container(
                width: isDesktop ? 450 : double.infinity,
                padding: const EdgeInsets.all(defaultPadding * 2),
                decoration: BoxDecoration(
                  color: C.bg2,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: C.border.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Sign In",
                        style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: C.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: C.accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: C.accentLight, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: C.accentLight, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 15),
                      ],
                      TextFormField(
                        controller: _emailPhoneController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: InputDecoration(
                          labelText: "Admin Email or Phone",
                          hintText: "your@email.com or 03001234567",
                          prefixIcon: Icon(Icons.person_rounded, color: C.textMuted),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return "Please enter your email or phone number";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: TextStyle(color: C.textPrimary),
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: Icon(Icons.lock_rounded, color: C.textMuted),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              color: C.textMuted,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return "Please enter your password";
                          }
                          if (val.length < 6) {
                            return "Password must be at least 6 characters";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: C.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  "Login to Dashboard",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "Authorized administrative access only.",
                style: TextStyle(
                  color: C.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
