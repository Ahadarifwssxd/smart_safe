import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartsafe/models/user_roles.dart';

class DashboardUser {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;

  const DashboardUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
  });

  bool get isAdmin => UserRoles.isAdminRole(role);

  factory DashboardUser.fromDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DashboardUser(
      uid: doc.id,
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      role: UserRoles.normalize(data['role']?.toString()),
    );
  }
}
