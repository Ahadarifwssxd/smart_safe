import 'package:firebase_auth/firebase_auth.dart';
import 'user_roles.dart';

class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String gender;
  final String bloodGroup;
  final String role;
  final String photoUrl;
  final bool phoneVerified;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.gender = '',
    this.bloodGroup = '',
    this.role = UserRoles.user,
    this.photoUrl = '',
    this.phoneVerified = false,
  });

  bool get isAdmin => UserRoles.isAdminRole(role);

  String get initials {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    String? letter(String s) {
      for (final m in RegExp(r'[A-Za-z]').allMatches(s)) {
        return m.group(0)!.toUpperCase();
      }
      return null;
    }
    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final a = letter(parts[0]);
      final b = letter(parts[1]);
      if (a != null && b != null) return '$a$b';
    }
    return letter(clean) ?? '?';
  }

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? 'User' : parts.first;
  }

  factory UserProfile.fromFirestore(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      gender: data['gender']?.toString() ?? '',
      bloodGroup: data['bloodGroup']?.toString() ?? '',
      role: UserRoles.normalize(data['role']?.toString()),
      photoUrl: data['photoUrl']?.toString() ?? '',
      phoneVerified: data['phoneVerified'] == true,
    );
  }

  factory UserProfile.fromAuthUser(User user) {
    return UserProfile(
      uid: user.uid,
      name: user.displayName ?? '',
      email: user.email ?? '',
      phone: user.phoneNumber ?? '',
      role: UserRoles.user,
      photoUrl: user.photoURL ?? '',
      phoneVerified: false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'phone': phone,
        'gender': gender,
        'bloodGroup': bloodGroup,
        'role': role,
        'photoUrl': photoUrl,
        'phoneVerified': phoneVerified,
      };
}
