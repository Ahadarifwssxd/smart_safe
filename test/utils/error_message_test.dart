import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsafe/utils/error_message.dart';

void main() {
  group('friendlyErrorMessage — FirebaseAuthException', () {
    test('maps known auth codes to friendly text', () {
      expect(
        friendlyErrorMessage(FirebaseAuthException(code: 'wrong-password')),
        'Incorrect password. Please try again.',
      );
      expect(
        friendlyErrorMessage(FirebaseAuthException(code: 'user-not-found')),
        'No account found with this email.',
      );
      expect(
        friendlyErrorMessage(FirebaseAuthException(code: 'email-already-in-use')),
        'This email is already registered. Try logging in instead.',
      );
    });

    test('falls back to a generic auth message for unknown codes', () {
      expect(
        friendlyErrorMessage(FirebaseAuthException(code: 'something-weird')),
        'Authentication failed. Please try again.',
      );
    });
  });

  group('friendlyErrorMessage — FirebaseException (Firestore/Storage)', () {
    test('maps permission-denied', () {
      expect(
        friendlyErrorMessage(
            FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')),
        'You do not have permission to do this.',
      );
    });

    test('maps unavailable', () {
      expect(
        friendlyErrorMessage(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')),
        'Service is temporarily unavailable. Try again shortly.',
      );
    });
  });

  group('friendlyErrorMessage — Google Sign-In', () {
    test('recognises a cancelled google sign-in', () {
      final msg = friendlyErrorMessage(
          Exception('PlatformException(sign_in_failed, cancelled by user)'));
      expect(msg, 'Sign-in was cancelled.');
    });

    test('explains the developer_error / SHA-1 case', () {
      final msg = friendlyErrorMessage(
          Exception('PlatformException(ApiException: 10, developer_error)'));
      expect(msg, contains('SHA-1'));
    });
  });

  group('friendlyErrorMessage — raw errors and prefix', () {
    test('cleans the leading "Exception:" prefix', () {
      expect(friendlyErrorMessage(Exception('Boom happened')), 'Boom happened');
    });

    test('applies the optional prefix', () {
      final msg = friendlyErrorMessage(
        FirebaseAuthException(code: 'invalid-email'),
        prefix: 'Could not sign in —',
      );
      expect(msg, startsWith('Could not sign in —'));
      expect(msg, contains('valid email'));
    });

    test('never returns an empty string', () {
      expect(friendlyErrorMessage(Exception('')), isNotEmpty);
    });
  });
}
