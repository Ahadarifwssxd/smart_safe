import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartsafe/utils/error_message.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const SettingsScreen({Key? key, this.onLogout}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isProfileLoaded = false;
  bool _obscurePassword = true;
  final _profileFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
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
            const PageHeaderBar(title: "System Settings"),
            const SizedBox(height: defaultPadding),
            Container(
              padding: const EdgeInsets.all(defaultPadding),
              decoration: BoxDecoration(
                color: secondaryColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.border.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_rounded, color: C.accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Appearance",
                          style: TextStyle(
                            color: C.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("Theme Mode", style: TextStyle(color: C.textPrimary)),
                    subtitle: Text(AppTheme.isDark ? "Dark Theme Active" : "Light Theme Active", style: TextStyle(color: C.textMuted)),
                    trailing: Switch(
                      value: AppTheme.isDark,
                      onChanged: (val) {
                        AppTheme.toggle();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: defaultPadding),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseService.instance.getAdminConfigStream(),
              builder: (context, snapshot) {
                bool highAlertMode = false;
                bool smsBackupEnabled = true;

                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  if (data != null) {
                    highAlertMode = data['highAlertMode'] ?? false;
                    smsBackupEnabled = data['smsBackupEnabled'] ?? true;
                    if (!_isProfileLoaded) {
                      _emailController.text = data['email'] ?? '';
                      _phoneController.text = data['phone'] ?? '';
                      _passwordController.text = data['password'] ?? '';
                      _isProfileLoaded = true;
                    }
                  }
                }

                return Container(
                  padding: const EdgeInsets.all(defaultPadding),
                  decoration: BoxDecoration(
                    color: secondaryColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.border.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security_rounded, color: C.accent, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Safety System Policies",
                              style: TextStyle(
                                color: C.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 20),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("High Alert Status", style: TextStyle(color: C.textPrimary)),
                        subtitle: Text("Force active emergency broadcasting to all clients", style: TextStyle(color: C.textMuted)),
                        trailing: Switch(
                          value: highAlertMode,
                          onChanged: (val) async {
                            try {
                              await FirebaseService.instance.updateAdminConfig(
                                highAlertMode: val,
                                smsBackupEnabled: smsBackupEnabled,
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(friendlyErrorMessage(e))),
                              );
                            }
                          },
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("Offline SMS Backup Router", style: TextStyle(color: C.textPrimary)),
                        subtitle: Text("Automatically switch to Twilio/SMS when device goes offline", style: TextStyle(color: C.textMuted)),
                        trailing: Switch(
                          value: smsBackupEnabled,
                          onChanged: (val) async {
                            try {
                              await FirebaseService.instance.updateAdminConfig(
                                highAlertMode: highAlertMode,
                                smsBackupEnabled: val,
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(friendlyErrorMessage(e))),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: defaultPadding),
            Container(
              padding: const EdgeInsets.all(defaultPadding),
              decoration: BoxDecoration(
                color: secondaryColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.border.withValues(alpha: 0.1)),
              ),
              child: Form(
                key: _profileFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_rounded, color: C.accent, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Admin Profile Credentials",
                            style: TextStyle(
                              color: C.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 20),
                    TextFormField(
                      controller: _emailController,
                      style: TextStyle(color: C.textPrimary),
                      decoration: const InputDecoration(
                        labelText: "Admin Email",
                        prefixIcon: Icon(Icons.email_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Email cannot be empty";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: _phoneController,
                      style: TextStyle(color: C.textPrimary),
                      decoration: const InputDecoration(
                        labelText: "Admin Phone Number",
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Phone number cannot be empty";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: TextStyle(color: C.textPrimary),
                      decoration: InputDecoration(
                        labelText: "Admin Password",
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: C.textMuted,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Password cannot be empty";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (_profileFormKey.currentState!.validate()) {
                          try {
                            await FirebaseService.instance.updateAdminCredentials(
                              _emailController.text,
                              _phoneController.text,
                              _passwordController.text,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Admin profile credentials updated successfully!")),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(friendlyErrorMessage(e, prefix: 'Failed to update credentials:')))
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text("Save Credentials"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: C.accent,
                        minimumSize: const Size(double.infinity, 45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.onLogout != null) ...[
              const SizedBox(height: defaultPadding),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: C.bg2,
                      title: Text("Logout", style: TextStyle(color: C.textPrimary)),
                      content: Text("Are you sure you want to logout from the admin panel?", style: TextStyle(color: C.textMuted)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text("Cancel", style: TextStyle(color: C.textMuted)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onLogout!();
                          },
                          child: const Text("Logout"),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text("Logout Admin Session"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.accent,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
