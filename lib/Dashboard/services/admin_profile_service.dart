import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/models/user_profile.dart';

/// Live admin identity for dashboard header (Firebase user or legacy config).
class AdminProfileService {
  static final AdminProfileService instance = AdminProfileService._internal();
  AdminProfileService._internal();

  Stream<AdminDisplayProfile> profileStream() {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      return FirebaseService.instance.getUserProfileStream(user.uid).map((data) {
        if (data != null) {
          final profile = UserProfile.fromFirestore(user.uid, data);
          return AdminDisplayProfile(
            name: profile.name.isNotEmpty ? profile.name : (user.email ?? 'Admin'),
            email: profile.email.isNotEmpty ? profile.email : (user.email ?? ''),
            photoUrl: profile.photoUrl.isNotEmpty ? profile.photoUrl : (user.photoURL ?? ''),
            uid: user.uid,
            isFirebaseUser: true,
          );
        }
        return AdminDisplayProfile(
          name: user.displayName ?? user.email ?? 'Admin',
          email: user.email ?? '',
          photoUrl: user.photoURL ?? '',
          uid: user.uid,
          isFirebaseUser: true,
        );
      });
    }

    return FirebaseService.instance.getAdminConfigStream().map((snap) {
      if (!snap.exists) {
        return const AdminDisplayProfile(name: 'Admin', email: '', photoUrl: '');
      }
      final data = snap.data() as Map<String, dynamic>? ?? {};
      return AdminDisplayProfile(
        name: data['name']?.toString().isNotEmpty == true
            ? data['name'].toString()
            : 'SmartSafe Admin',
        email: data['email']?.toString() ?? '',
        photoUrl: data['photoUrl']?.toString() ?? '',
        isFirebaseUser: false,
      );
    });
  }
}

class AdminDisplayProfile {
  final String name;
  final String email;
  final String photoUrl;
  final String? uid;
  final bool isFirebaseUser;

  const AdminDisplayProfile({
    required this.name,
    required this.email,
    this.photoUrl = '',
    this.uid,
    this.isFirebaseUser = false,
  });

  String get initials {
    final clean = name.trim();
    if (clean.isEmpty) return 'A';
    String? first(String s) {
      for (final m in RegExp(r'[A-Za-z]').allMatches(s)) {
        return m.group(0)!.toUpperCase();
      }
      return null;
    }
    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final a = first(parts[0]);
      final b = first(parts[1]);
      if (a != null && b != null) return '$a$b';
    }
    return first(clean) ?? 'A';
  }
}
