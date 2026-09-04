import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'email_send_service.dart';

class EmailSendResult {
  final bool emailSent;
  final String? devCode;
  final String? errorMessage;

  const EmailSendResult({
    required this.emailSent,
    this.devCode,
    this.errorMessage,
  });
}

class _PendingVerification {
  final String code;
  final DateTime expiresAt;

  _PendingVerification({required this.code, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class EmailVerificationService {
  static final EmailVerificationService instance = EmailVerificationService._internal();
  EmailVerificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'email_verifications';
  static const _expiryMinutes = 10;
  static const _firestoreTimeout = Duration(seconds: 8);

  final Map<String, _PendingVerification> _memoryCodes = {};

  String? debugLastCode;
  String? debugLastEmail;
  bool lastEmailSent = false;
  String? lastEmailError;

  String _docIdForEmail(String email) =>
      email.trim().toLowerCase().replaceAll('.', '_');

  String _generateCode() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  void _storeInMemory(String normalizedEmail, String code) {
    _memoryCodes[normalizedEmail] = _PendingVerification(
      code: code,
      expiresAt: DateTime.now().add(const Duration(minutes: _expiryMinutes)),
    );
    debugLastCode = code;
    debugLastEmail = normalizedEmail;
  }

  Future<void> _syncFirestore(String normalized, String code, DateTime expiresAt) async {
    try {
      await _db.collection(_collection).doc(_docIdForEmail(normalized)).set({
        'email': normalized,
        'code': code,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'createdAt': FieldValue.serverTimestamp(),
        'verified': false,
      }).timeout(_firestoreTimeout);
    } on TimeoutException {
      debugPrint('Firestore verification write timed out.');
    } catch (e) {
      debugPrint('Firestore verification write failed: $e');
    }
  }

  Future<EmailSendResult> sendVerificationCode(
    String email, {
    String? userName,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) throw Exception('Email is required');

    final code = _generateCode();
    final expiresAt = DateTime.now().add(const Duration(minutes: _expiryMinutes));

    _storeInMemory(normalized, code);

    final outcome = await EmailSendService.instance.sendVerificationCode(
      toEmail: normalized,
      code: code,
      userName: userName,
    );

    lastEmailSent = outcome.success;
    lastEmailError = outcome.errorMessage;

    if (!outcome.success && kDebugMode) {
      debugPrint('SmartSafe verification code for $normalized: $code');
      if (outcome.errorMessage != null) {
        debugPrint('Email error: ${outcome.errorMessage}');
      }
    }

    unawaited(_syncFirestore(normalized, code, expiresAt));

    // Real delivery first: on success the code goes ONLY to the user's inbox
    // (like every other app) and nothing is shown on-screen. The code is
    // returned as a fallback ONLY when the email genuinely failed to send, so a
    // delivery outage can't hard-block signup.
    return EmailSendResult(
      emailSent: outcome.success,
      devCode: outcome.success ? null : code,
      errorMessage: outcome.errorMessage,
    );
  }

  Future<bool> verifyCode(String email, String code) async {
    final normalized = email.trim().toLowerCase();
    // Keep digits only — guards against stray spaces / extra characters that
    // previously made a correct code read as "invalid".
    final entered = code.replaceAll(RegExp(r'\D'), '');

    if (entered.length != 6) return false;

    final pending = _memoryCodes[normalized];
    if (pending != null) {
      if (pending.isExpired) {
        _memoryCodes.remove(normalized);
        throw Exception('Verification code has expired. Please request a new code.');
      }
      if (pending.code == entered) {
        _memoryCodes.remove(normalized);
        _tryDeleteFirestoreDoc(normalized);
        return true;
      }
      return false;
    }

    try {
      final doc = await _db
          .collection(_collection)
          .doc(_docIdForEmail(normalized))
          .get()
          .timeout(_firestoreTimeout);

      if (!doc.exists) {
        throw Exception('No verification code found. Please request a new code.');
      }

      final data = doc.data()!;
      final storedCode = data['code']?.toString() ?? '';
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();

      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        await doc.reference.delete();
        throw Exception('Verification code has expired. Please request a new code.');
      }

      if (storedCode != entered) return false;

      await doc.reference.delete();
      return true;
    } on TimeoutException {
      throw Exception('Could not verify code. Check your connection and try again.');
    }
  }

  void _tryDeleteFirestoreDoc(String normalizedEmail) {
    _db.collection(_collection).doc(_docIdForEmail(normalizedEmail)).delete().catchError((_) {});
  }
}
