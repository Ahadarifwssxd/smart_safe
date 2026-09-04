import 'package:firebase_auth/firebase_auth.dart';

/// Converts Firebase and other thrown errors into short, user-facing text.
String friendlyErrorMessage(Object error, {String? prefix}) {
  final message = _resolveMessage(error);
  if (prefix == null || prefix.isEmpty) return message;
  return '$prefix $message';
}

String _resolveMessage(Object error) {
  if (error is FirebaseAuthException) {
    return _firebaseAuthMessage(error);
  }
  if (error is FirebaseException) {
    return _firebaseServiceMessage(error);
  }
  final google = _googleMessage(error.toString());
  if (google != null) return google;
  if (error is Exception) {
    return _cleanRaw(error.toString());
  }
  return _cleanRaw(error.toString());
}

/// Maps common Google Sign-In failures to clear, user-facing text.
String? _googleMessage(String raw) {
  final r = raw.toLowerCase();
  final looksGoogle = r.contains('google') ||
      r.contains('apiexception') ||
      r.contains('sign_in_failed') ||
      r.contains('developer_error');
  if (!looksGoogle) return null;

  // A "canceled" from Credential Manager usually means Google sign-in isn't
  // fully set up on this build (no matching credential) rather than a real user
  // cancel — so guide people to the email login that always works instead of a
  // scary error.
  if (r.contains('cancel')) {
    return 'Google sign-in isn\'t available right now — please sign in with '
        'your email and password instead.';
  }
  if (r.contains('apiexception: 10') || r.contains('developer_error')) {
    return 'Google sign-in isn\'t available yet — please use your email and '
        'password to sign in.';
  }
  if (r.contains('network') || r.contains('7:')) {
    return 'No internet connection. Check your network and try again.';
  }
  if (r.contains('12500') || r.contains('12501') || r.contains('sign_in_failed')) {
    return 'Google sign-in isn\'t available right now — please sign in with '
        'your email instead.';
  }
  return null;
}

String _firebaseAuthMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'email-already-in-use':
      return 'This email is already registered. Try logging in instead.';
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'user-disabled':
      return 'This account has been disabled. Contact support.';
    case 'user-not-found':
      return 'No account found with this email.';
    case 'wrong-password':
      return 'Incorrect password. Please try again.';
    case 'invalid-credential':
    case 'invalid-login-credentials':
      return 'Incorrect email or password.';
    case 'weak-password':
      return 'Password is too weak. Use 8+ characters with uppercase, a number, and a symbol.';
    case 'operation-not-allowed':
      return 'This sign-in method is not available.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'network-request-failed':
      return 'No internet connection. Check your network and try again.';
    case 'requires-recent-login':
      return 'Please sign in again to complete this action.';
    case 'account-exists-with-different-credential':
      return 'An account already exists with a different sign-in method.';
    case 'invalid-verification-code':
      return 'Invalid verification code. Please try again.';
    case 'invalid-verification-id':
      return 'Verification expired. Request a new code.';
    case 'credential-already-in-use':
      return 'This account is already linked to another user.';
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
      return 'Sign-in was cancelled.';
    case 'email-not-verified':
      return 'Please verify your email before continuing.';
    default:
      final fromFirebase = e.message?.trim();
      if (fromFirebase != null && fromFirebase.isNotEmpty) {
        return _cleanRaw(fromFirebase);
      }
      return 'Authentication failed. Please try again.';
  }
}

String _firebaseServiceMessage(FirebaseException e) {
  switch (e.code) {
    case 'permission-denied':
      return 'You do not have permission to do this.';
    case 'unavailable':
      return 'Service is temporarily unavailable. Try again shortly.';
    case 'not-found':
      return 'The requested data was not found.';
    case 'already-exists':
      return 'This item already exists.';
    case 'failed-precondition':
      return 'Action could not be completed. Please refresh and try again.';
    case 'resource-exhausted':
      return 'Too many requests. Please try again later.';
    case 'unauthenticated':
      return 'Please sign in to continue.';
    case 'cancelled':
      return 'Operation was cancelled.';
    case 'invalid-argument':
      return 'Some information is invalid. Check your input and try again.';
    default:
      final fromFirebase = e.message?.trim();
      if (fromFirebase != null && fromFirebase.isNotEmpty) {
        return _cleanRaw(fromFirebase);
      }
      return 'Something went wrong. Please try again.';
  }
}

String _cleanRaw(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return 'Something went wrong. Please try again.';

  text = text.replaceFirst(RegExp(r'^Exception:\s*', caseSensitive: false), '');
  text = text.replaceFirst(RegExp(r'^Error:\s*', caseSensitive: false), '');

  final bracketMatch = RegExp(
    r'\[(?:firebase_auth|cloud_firestore|firebase_storage)/([a-z0-9-]+)\]',
    caseSensitive: false,
  ).firstMatch(text);
  if (bracketMatch != null) {
    final code = bracketMatch.group(1);
    if (code != null) {
      final mapped = _messageForCode(code);
      if (mapped != null) return mapped;
    }
    text = text.replaceFirst(bracketMatch.group(0)!, '').trim();
  }

  text = text.replaceAll(RegExp(r'^\[\w+/[\w-]+\]\s*'), '');
  text = text.trim();
  if (text.isEmpty) return 'Something went wrong. Please try again.';
  return text;
}

String? _messageForCode(String code) {
  switch (code) {
    case 'email-already-in-use':
      return 'This email is already registered. Try logging in instead.';
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'user-not-found':
      return 'No account found with this email.';
    case 'wrong-password':
    case 'invalid-credential':
    case 'invalid-login-credentials':
      return 'Incorrect email or password.';
    case 'weak-password':
      return 'Password is too weak. Use 8+ characters with uppercase, a number, and a symbol.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'network-request-failed':
      return 'No internet connection. Check your network and try again.';
    case 'permission-denied':
      return 'You do not have permission to do this.';
    default:
      return null;
  }
}
