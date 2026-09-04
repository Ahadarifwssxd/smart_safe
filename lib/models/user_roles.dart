/// Firestore `users/{uid}.role` values.
class UserRoles {
  UserRoles._();

  static const String user = 'user';
  static const String admin = 'admin';

  static bool isAdminRole(String? role) =>
      role?.toLowerCase().trim() == admin;

  static String normalize(String? role) =>
      isAdminRole(role) ? admin : user;
}
