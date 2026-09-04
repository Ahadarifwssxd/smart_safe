import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/models/dashboard_user.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/utils/error_message.dart';
import 'package:smartsafe/models/user_roles.dart';
import 'package:smartsafe/theme/colors.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({Key? key}) : super(key: key);

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String? _updatingUid;

  /// Masks a phone number to show only the last 4 digits.
  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return phone;
    final visible = digits.substring(digits.length - 4);
    final masked = '*' * (digits.length - 4);
    return '$masked$visible';
  }

  Future<void> _changeRole(DashboardUser user, String newRole) async {
    if (user.role == newRole) return;

    setState(() => _updatingUid = user.uid);
    try {
      await FirebaseService.instance.updateUserRole(user.uid, newRole);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: C.success,
            content: Text(
              '${user.name.isNotEmpty ? user.name : user.email} is now $newRole',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: C.accent,
            content: Text(friendlyErrorMessage(e, prefix: 'Could not update role:'), style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingUid = null);
    }
  }

  void _confirmRoleChange(DashboardUser user, String newRole) {
    if (user.role == newRole) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Change role?', style: TextStyle(color: C.textPrimary)),
        content: Text(
          'Set ${user.email.isNotEmpty ? user.email : user.name} to "$newRole"?',
          style: TextStyle(color: C.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () {
              Navigator.pop(ctx);
              _changeRole(user, newRole);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Header(),
            const SizedBox(height: defaultPadding),
            const PageHeaderBar(
              title: 'App Users & Roles',
              subtitle:
                  'Signup/login users appear here with role "user". Promote to admin for dashboard access in the app.',
            ),
            const SizedBox(height: defaultPadding),
            Container(
              padding: const EdgeInsets.all(defaultPadding),
              decoration: BoxDecoration(
                color: secondaryColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.border.withValues(alpha: 0.1)),
              ),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.instance.getAppUsersStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        friendlyErrorMessage(snapshot.error!, prefix: 'Could not load users:'),
                        style: TextStyle(color: C.accentLight),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final users = snapshot.data!.docs
                      .map((d) => DashboardUser.fromDoc(d))
                      .toList()
                    ..sort((a, b) => a.email.compareTo(b.email));

                  if (users.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'No app users yet. Users appear after signup or login.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: dataTableColumnSpacing(context),
                      // Explicit light styles so the text is always visible on
                      // the dark admin panel (regardless of the app's theme).
                      headingTextStyle: TextStyle(
                        color: C.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      dataTextStyle: TextStyle(
                        color: C.textMuted,
                        fontSize: 13,
                      ),
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Role')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: users.map((user) {
                        final busy = _updatingUid == user.uid;
                        return DataRow(
                          cells: [
                            DataCell(Text(
                              user.name.isNotEmpty ? user.name : '—',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            )),
                            DataCell(Text(
                              user.email.isNotEmpty ? user.email : '—',
                              style: TextStyle(color: C.textMuted),
                            )),
                            DataCell(Text(
                              user.phone.isNotEmpty ? _maskPhone(user.phone) : '—',
                              style: TextStyle(color: C.textMuted),
                            )),
                            DataCell(_RoleBadge(role: user.role)),
                            DataCell(
                              busy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : PopupMenuButton<String>(
                                      icon: Icon(Icons.admin_panel_settings, color: C.accent),
                                      color: C.bg2,
                                      onSelected: (value) => _confirmRoleChange(user, value),
                                      itemBuilder: (context) => [
                                        if (!user.isAdmin)
                                          PopupMenuItem(
                                            value: UserRoles.admin,
                                            child: Text(
                                              'Make Admin',
                                              style: TextStyle(color: C.accentLight),
                                            ),
                                          ),
                                        if (user.isAdmin)
                                          PopupMenuItem(
                                            value: UserRoles.user,
                                            child: Text(
                                              'Remove Admin',
                                              style: TextStyle(color: C.warning),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = UserRoles.isAdminRole(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin ? C.accent.withValues(alpha: 0.2) : C.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAdmin ? C.accent.withValues(alpha: 0.5) : C.accent.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        isAdmin ? 'ADMIN' : 'USER',
        style: TextStyle(
          color: isAdmin ? C.accentLight : C.accentLight,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
