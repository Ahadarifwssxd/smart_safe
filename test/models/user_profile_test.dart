import 'package:flutter_test/flutter_test.dart';
import 'package:smartsafe/models/user_profile.dart';
import 'package:smartsafe/models/user_roles.dart';

void main() {
  group('UserProfile.initials', () {
    test('uses first letters of the first two words', () {
      const p = UserProfile(uid: 'u', name: 'Saad Khan', email: '', phone: '');
      expect(p.initials, 'SK');
    });

    test('single name → single initial', () {
      const p = UserProfile(uid: 'u', name: 'Saad', email: '', phone: '');
      expect(p.initials, 'S');
    });

    test('skips leading non-letters', () {
      const p = UserProfile(uid: 'u', name: '123 saad', email: '', phone: '');
      expect(p.initials, 'S');
    });

    test('empty name → ?', () {
      const p = UserProfile(uid: 'u', name: '   ', email: '', phone: '');
      expect(p.initials, '?');
    });
  });

  group('UserProfile.firstName', () {
    test('returns the first word', () {
      const p =
          UserProfile(uid: 'u', name: 'Saad Ali Khan', email: '', phone: '');
      expect(p.firstName, 'Saad');
    });
  });

  group('UserProfile.isAdmin', () {
    test('reflects the role', () {
      const admin = UserProfile(
          uid: 'u', name: 'A', email: '', phone: '', role: UserRoles.admin);
      const user = UserProfile(uid: 'u', name: 'B', email: '', phone: '');
      expect(admin.isAdmin, isTrue);
      expect(user.isAdmin, isFalse);
    });
  });

  group('UserProfile.fromFirestore', () {
    test('reads fields and normalizes the role', () {
      final p = UserProfile.fromFirestore('uid123', {
        'name': 'Saad',
        'email': 'saad@example.com',
        'phone': '03001234567',
        'role': 'ADMIN',
        'phoneVerified': true,
      });
      expect(p.uid, 'uid123');
      expect(p.name, 'Saad');
      expect(p.email, 'saad@example.com');
      expect(p.role, UserRoles.admin);
      expect(p.phoneVerified, isTrue);
    });

    test('uses safe defaults for missing fields', () {
      final p = UserProfile.fromFirestore('uid', {});
      expect(p.name, '');
      expect(p.role, UserRoles.user);
      expect(p.phoneVerified, isFalse);
    });
  });

  group('UserProfile.toFirestore', () {
    test('round-trips through fromFirestore', () {
      const original = UserProfile(
        uid: 'uid',
        name: 'Saad',
        email: 'saad@example.com',
        phone: '03001234567',
        gender: 'male',
        bloodGroup: 'O+',
        role: UserRoles.admin,
        phoneVerified: true,
      );
      final restored = UserProfile.fromFirestore('uid', original.toFirestore());
      expect(restored.name, original.name);
      expect(restored.email, original.email);
      expect(restored.phone, original.phone);
      expect(restored.gender, original.gender);
      expect(restored.bloodGroup, original.bloodGroup);
      expect(restored.role, original.role);
      expect(restored.phoneVerified, original.phoneVerified);
    });
  });
}
