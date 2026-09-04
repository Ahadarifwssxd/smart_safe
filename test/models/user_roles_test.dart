import 'package:flutter_test/flutter_test.dart';
import 'package:smartsafe/models/user_roles.dart';

void main() {
  group('UserRoles.isAdminRole', () {
    test('true only for the admin role (case/space insensitive)', () {
      expect(UserRoles.isAdminRole('admin'), isTrue);
      expect(UserRoles.isAdminRole('ADMIN'), isTrue);
      expect(UserRoles.isAdminRole('  Admin  '), isTrue);
    });

    test('false for user / unknown / null', () {
      expect(UserRoles.isAdminRole('user'), isFalse);
      expect(UserRoles.isAdminRole('moderator'), isFalse);
      expect(UserRoles.isAdminRole(null), isFalse);
      expect(UserRoles.isAdminRole(''), isFalse);
    });
  });

  group('UserRoles.normalize', () {
    test('keeps admin as admin', () {
      expect(UserRoles.normalize('ADMIN'), UserRoles.admin);
    });

    test('collapses everything else to user', () {
      expect(UserRoles.normalize('user'), UserRoles.user);
      expect(UserRoles.normalize('whatever'), UserRoles.user);
      expect(UserRoles.normalize(null), UserRoles.user);
    });
  });
}
