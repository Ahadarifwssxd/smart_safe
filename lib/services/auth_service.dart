import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../Dashboard/services/firebase_service.dart';
import '../models/user_roles.dart';
import 'presence_service.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache the initialize() future so concurrent callers (startup warm-up + the
  // first tap) share ONE initialization instead of racing two of them.
  Future<void>? _googleInitFuture;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // ── Sign up with email/password and send verification email ────────
  Future<UserCredential?> signUp({
    required String email,
    required String password,
    required String name,
    String phone = '',
    String? gender,
    String? bloodGroup,
    bool phoneVerified = false,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await user.updateDisplayName(name);
        await FirebaseService.instance.createUserProfile(
          uid: user.uid,
          name: name,
          email: email,
          phone: phone,
          gender: gender,
          bloodGroup: bloodGroup,
          phoneVerified: phoneVerified,
        );
        PresenceService.instance.startHeartbeat();
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint("AuthService signUp error: ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("AuthService signUp general error: $e");
      rethrow;
    }
  }

  /// Creates the account from a Firebase-VERIFIED phone credential plus the
  /// user's email/password.
  ///
  /// Firebase validates the SMS OTP the moment the phone credential is used, so
  /// a wrong code throws `invalid-verification-code` BEFORE any account exists —
  /// no half-created users. We then link email/password to the same account, so
  /// the user can log in with either.
  Future<UserCredential?> signUpWithPhoneCredential({
    required PhoneAuthCredential phoneCredential,
    required String email,
    required String password,
    required String name,
    required String phone,
    String? gender,
    String? bloodGroup,
  }) async {
    // 1. Phone sign-in — this is what actually validates the OTP.
    final cred = await _auth.signInWithCredential(phoneCredential);
    final user = cred.user;
    if (user == null) throw Exception('Phone verification failed.');

    // 2. Attach email/password to the SAME account so email login works too.
    try {
      await user.linkWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      // Already linked is fine; anything else is a real problem.
      if (e.code != 'provider-already-linked' &&
          e.code != 'credential-already-in-use') {
        rethrow;
      }
    }

    await user.updateDisplayName(name);
    await FirebaseService.instance.createUserProfile(
      uid: user.uid,
      name: name,
      email: email,
      phone: phone,
      gender: gender,
      bloodGroup: bloodGroup,
      phoneVerified: true,
    );
    PresenceService.instance.startHeartbeat();
    return cred;
  }

  // ── Send email verification ────────────────────────────────────────
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      debugPrint('Verification email sent to ${user.email}');
    }
  }

  // ── Check if email is verified ─────────────────────────────────────
  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.reload();
      return _auth.currentUser?.emailVerified ?? false;
    }
    return false;
  }

  // ── Sign in with email and password ────────────────────────────────
  Future<UserCredential?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      if (cleanEmail == 'donnaevo073@gmail.com') {
        try {
          final credential = await _auth.signInWithEmailAndPassword(
            email: cleanEmail,
            password: password,
          );
          if (credential.user != null) {
            await FirebaseService.instance
                .ensureUserProfileFromAuth(credential.user!);
          }
          return credential;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
            // Auto-register this specific admin user if they don't exist yet
            try {
              final credential = await _auth.createUserWithEmailAndPassword(
                email: cleanEmail,
                password: password,
              );
              final user = credential.user;
              if (user != null) {
                await user.updateDisplayName("Admin Ahad");
                await FirebaseService.instance.createUserProfile(
                  uid: user.uid,
                  name: "Admin Ahad",
                  email: cleanEmail,
                  phone: '03001234567',
                  role: UserRoles.admin,
                );
              }
              return credential;
            } catch (signupError) {
              debugPrint("Auto-signup failed for admin user: $signupError");
            }
          }
          rethrow;
        }
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (credential.user != null) {
        await FirebaseService.instance
            .ensureUserProfileFromAuth(credential.user!);
        PresenceService.instance.startHeartbeat();
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint("AuthService signIn error: ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("AuthService signIn general error: $e");
      rethrow;
    }
  }

  // ── Google Sign-In (Web = popup, Mobile = native google_sign_in) ───
  // Web/server OAuth client ID (client_type 3 in google-services.json).
  // Required on Android in google_sign_in v7 so Credential Manager returns
  // an idToken whose audience Firebase accepts. Without it the flow fails
  // immediately and surfaces as a "cancelled" error.
  static const String _serverClientId =
      '1095358418186-vu2k8atrb4ok2cubkvgq4mhl6imvv644.apps.googleusercontent.com';

  Future<void> _ensureGoogleSignInInitialized() {
    // initialize() is expensive on the first call. Run it exactly once and let
    // everyone await the same future.
    return _googleInitFuture ??= GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId,
    );
  }

  /// Warm up the Google Sign-In engine ahead of time (called at app startup)
  /// so the very first "Continue with Google" tap doesn't pay the one-time
  /// initialization cost. Safe to call multiple times and never throws.
  Future<void> warmUpGoogleSignIn() async {
    if (kIsWeb) return;
    try {
      await _ensureGoogleSignInInitialized();
    } catch (e) {
      // Reset so a real sign-in can retry; warm-up failure is non-fatal.
      _googleInitFuture = null;
      debugPrint('AuthService warmUpGoogleSignIn error: $e');
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      UserCredential userCredential;

      if (kIsWeb) {
        // Web: use Firebase popup
        final googleProvider = GoogleAuthProvider();
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        await _ensureGoogleSignInInitialized();

        // Android / iOS: use google_sign_in package.
        // google_sign_in v7+ removed accessToken — only idToken is needed for
        // Firebase. authenticate() already shows the account chooser, so we do
        // NOT call signOut() first (that only added a wasteful round-trip).
        final GoogleSignInAccount googleUser =
            await GoogleSignIn.instance.authenticate(
          scopeHint: ['email', 'profile'],
        );

        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        // v7: only idToken is exposed (accessToken was removed for security)
        final idToken = googleAuth.idToken;
        if (idToken == null) {
          throw Exception(
            'Google sign-in failed: no idToken returned. '
            'Check the SHA-1 fingerprint and web client ID in Firebase.',
          );
        }
        final credential = GoogleAuthProvider.credential(
          idToken: idToken,
        );

        userCredential = await _auth.signInWithCredential(credential);
      }

      final user = userCredential.user;
      if (user != null) {
        // Don't block entering the app on Firestore. The profile doc is created
        // in the background (Firestore's local cache makes it instantly
        // readable), and presence starts alongside it. This is what makes the
        // spinner after choosing an account disappear quickly.
        unawaited(FirebaseService.instance.ensureUserProfileFromAuth(user));
        PresenceService.instance.startHeartbeat();
      }
      return userCredential;
    } catch (e) {
      debugPrint("AuthService signInWithGoogle error: $e");
      rethrow;
    }
  }

  // ── Sign out ───────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
