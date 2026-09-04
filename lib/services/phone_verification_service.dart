import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/phone_utils.dart';
import 'twilio_service.dart';

/// Outcome of trying to send an SMS verification code.
class PhoneSendResult {
  final bool smsSent;
  final String? devCode; // shown on screen if SMS delivery failed
  final String? errorMessage;

  const PhoneSendResult({
    required this.smsSent,
    this.devCode,
    this.errorMessage,
  });
}

class _PendingPhoneCode {
  final String code;
  final DateTime expiresAt;
  _PendingPhoneCode({required this.code, required this.expiresAt});
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Sends + verifies a 6-digit OTP to a phone number over Twilio SMS.
///
/// Mirrors [EmailVerificationService]: codes are held in memory AND mirrored to
/// Firestore (`phone_verifications`) so a verification survives a hot restart,
/// and SMS delivery never blocks the user — if Twilio fails, the code is
/// returned as [PhoneSendResult.devCode] so signup can still proceed.
///
/// It also enforces **one number per person**: [isPhoneAvailable] rejects a
/// number that another account has already verified.
class PhoneVerificationService {
  static final PhoneVerificationService instance =
      PhoneVerificationService._internal();
  PhoneVerificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'phone_verifications';
  static const _expiryMinutes = 10;
  static const _firestoreTimeout = Duration(seconds: 8);

  final Map<String, _PendingPhoneCode> _memoryCodes = {};

  /// Doc id / cache key — the normalized (last-10-digit) form of the number so
  /// +92 / 0092 / 0 prefixes all resolve to the same key.
  String _key(String phone) {
    final n = normalizePhone(phone);
    return n.isNotEmpty ? n : phone.replaceAll(RegExp(r'\D'), '');
  }

  String _generateCode() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  /// Returns `true` when [phoneE164] is free to use — i.e. no OTHER account has
  /// already verified it. [forUid] excludes the current user (so re-saving your
  /// own verified number is allowed).
  Future<bool> isPhoneAvailable(String phoneE164, {String? forUid}) async {
    final normalized = normalizePhone(phoneE164);
    if (normalized.isEmpty) return false;
    try {
      final snap = await _db
          .collection('users')
          .where('phoneNormalized', isEqualTo: normalized)
          .get()
          .timeout(_firestoreTimeout);
      for (final doc in snap.docs) {
        if (doc.id == forUid) continue;
        if (doc.data()['phoneVerified'] == true) return false;
      }
      return true;
    } on TimeoutException {
      // Don't hard-block on a flaky connection — let the save path re-check.
      debugPrint('[PhoneVerify] uniqueness check timed out');
      return true;
    } catch (e) {
      debugPrint('[PhoneVerify] uniqueness check failed: $e');
      return true;
    }
  }

  Future<void> _syncFirestore(String key, String code, DateTime expiresAt) async {
    try {
      await _db.collection(_collection).doc(key).set({
        'code': code,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(_firestoreTimeout);
    } on TimeoutException {
      debugPrint('[PhoneVerify] Firestore write timed out');
    } catch (e) {
      debugPrint('[PhoneVerify] Firestore write failed: $e');
    }
  }

  // ── Firebase Phone Auth (FREE real SMS OTP) ────────────────────────────────
  // Firebase sends the OTP itself from Google's servers — no Twilio, no cost, no
  // "trial number must be verified" limitation. The OTP is validated by Firebase
  // when the resulting credential is used (see [credentialForCode]).

  /// The verificationId Firebase hands back once it has texted the OTP.
  String? _firebaseVerificationId;

  /// Set when Android auto-retrieves the SMS and verifies it for the user.
  PhoneAuthCredential? autoCredential;

  /// True once Firebase has texted an OTP and we can build a credential.
  bool get hasFirebaseCode => _firebaseVerificationId != null;

  /// Ask Firebase to text a real OTP to [phoneE164] (E.164, e.g. +923001234567).
  /// Completes as soon as the SMS is on its way (or the send fails).
  Future<PhoneSendResult> sendFirebaseOtp(String phoneE164) async {
    final phone = phoneE164.trim();
    if (phone.isEmpty) throw Exception('Phone number is required');
    _firebaseVerificationId = null;
    autoCredential = null;

    final done = Completer<PhoneSendResult>();
    void finish(PhoneSendResult r) {
      if (!done.isCompleted) done.complete(r);
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential cred) {
          // Android may auto-read the SMS — keep the credential so the user
          // doesn't have to type anything.
          autoCredential = cred;
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('[PhoneVerify] Firebase OTP failed: ${e.code} ${e.message}');
          finish(PhoneSendResult(
            smsSent: false,
            errorMessage: e.message ?? 'Could not send the SMS code.',
          ));
        },
        codeSent: (String verificationId, int? resendToken) {
          _firebaseVerificationId = verificationId;
          finish(const PhoneSendResult(smsSent: true));
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _firebaseVerificationId = verificationId;
          finish(const PhoneSendResult(smsSent: true));
        },
      );
    } catch (e) {
      debugPrint('[PhoneVerify] Firebase verifyPhoneNumber threw: $e');
      finish(PhoneSendResult(smsSent: false, errorMessage: e.toString()));
    }
    return done.future;
  }

  /// Builds the credential for the OTP the user typed. Firebase validates it the
  /// moment it's used to sign in / link — a wrong code throws
  /// `invalid-verification-code`. Returns null if no OTP was ever requested.
  PhoneAuthCredential? credentialForCode(String smsCode) {
    final vid = _firebaseVerificationId;
    final code = smsCode.replaceAll(RegExp(r'\D'), '');
    if (vid == null || code.length != 6) return null;
    return PhoneAuthProvider.credential(
        verificationId: vid, smsCode: code);
  }

  /// Generates a code, stores it, and texts it to [phoneE164] via Twilio.
  /// (Legacy fallback — only used if Firebase Phone Auth is unavailable.)
  Future<PhoneSendResult> sendVerificationCode(String phoneE164) async {
    final phone = phoneE164.trim();
    if (phone.isEmpty) throw Exception('Phone number is required');

    final key = _key(phone);
    final code = _generateCode();
    final expiresAt =
        DateTime.now().add(const Duration(minutes: _expiryMinutes));

    _memoryCodes[key] = _PendingPhoneCode(code: code, expiresAt: expiresAt);
    unawaited(_syncFirestore(key, code, expiresAt));

    final message =
        'Your SmartSafe verification code is $code. It expires in $_expiryMinutes minutes.';

    bool sent = false;
    String? error;
    try {
      sent = await TwilioService.instance.sendSms(phone, message);
    } catch (e) {
      error = e.toString();
      debugPrint('[PhoneVerify] SMS send error: $e');
    }

    if (!sent && kDebugMode) {
      debugPrint('SmartSafe phone code for $phone: $code');
    }

    // Real delivery first: on success the OTP goes ONLY to the user's SMS and
    // nothing is shown on-screen. The code is returned as a fallback ONLY when
    // the SMS genuinely failed to send (e.g. a Twilio trial number that isn't
    // verified), so a delivery outage can't hard-block signup.
    return PhoneSendResult(
      smsSent: sent,
      devCode: sent ? null : code,
      errorMessage: error,
    );
  }

  /// Validates [code] for [phoneE164]. Checks the in-memory cache first, then
  /// falls back to the Firestore mirror (survives hot restart).
  Future<bool> verifyCode(String phoneE164, String code) async {
    final key = _key(phoneE164);
    final entered = code.replaceAll(RegExp(r'\D'), '');
    if (entered.length != 6) return false;

    final pending = _memoryCodes[key];
    if (pending != null) {
      if (pending.isExpired) {
        _memoryCodes.remove(key);
        throw Exception('Code has expired. Please request a new one.');
      }
      if (pending.code == entered) {
        _memoryCodes.remove(key);
        _tryDeleteDoc(key);
        return true;
      }
      return false;
    }

    try {
      final doc =
          await _db.collection(_collection).doc(key).get().timeout(_firestoreTimeout);
      if (!doc.exists) {
        throw Exception('No code found. Please request a new one.');
      }
      final data = doc.data()!;
      final storedCode = data['code']?.toString() ?? '';
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        await doc.reference.delete();
        throw Exception('Code has expired. Please request a new one.');
      }
      if (storedCode != entered) return false;
      await doc.reference.delete();
      return true;
    } on TimeoutException {
      throw Exception('Could not verify code. Check your connection and retry.');
    }
  }

  void _tryDeleteDoc(String key) {
    _db.collection(_collection).doc(key).delete().catchError((_) {});
  }
}
