import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartsafe/Dashboard/services/admin_profile_service.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/services/user_profile_service.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

class AdminEditProfileDialog extends StatefulWidget {
  final AdminDisplayProfile profile;
  const AdminEditProfileDialog({super.key, required this.profile});

  @override
  State<AdminEditProfileDialog> createState() => _AdminEditProfileDialogState();
}

class _AdminEditProfileDialogState extends State<AdminEditProfileDialog> {
  late final TextEditingController _name;
  String? _photoUrl;
  Uint8List? _pickedBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _photoUrl = widget.profile.photoUrl.isNotEmpty ? widget.profile.photoUrl : null;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _buildAvatarPreview() {
    if (_pickedBytes != null) {
      return CircleAvatar(radius: 48, backgroundImage: MemoryImage(_pickedBytes!));
    }
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          _photoUrl!,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 96,
              height: 96,
              color: C.accent.withValues(alpha: 0.15),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: C.accent),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return CircleAvatar(
              radius: 48,
              backgroundColor: C.accent.withValues(alpha: 0.15),
              child: Text(
                widget.profile.initials,
                style: TextStyle(color: C.accent, fontSize: 28, fontWeight: FontWeight.w800),
              ),
            );
          },
        ),
      );
    }
    return CircleAvatar(
      radius: 48,
      backgroundColor: C.accent.withValues(alpha: 0.15),
      child: Text(
        widget.profile.initials,
        style: TextStyle(color: C.accent, fontSize: 28, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedBytes = bytes;
      _photoUrl = null;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: C.accent, content: Text('Name is required', style: TextStyle(color: C.textPrimary))),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      if (widget.profile.isFirebaseUser && widget.profile.uid != null) {
        final uid = widget.profile.uid!;
        final existing = await FirebaseService.instance.getUserProfile(uid);
        var newPhotoUrl = _photoUrl ?? existing?['photoUrl']?.toString() ?? '';

        if (_pickedBytes != null) {
          newPhotoUrl = await FirebaseService.instance.uploadUserAvatar(
            uid,
            _pickedBytes!,
          );
        }

        final user = FirebaseAuth.instance.currentUser;
        final email = user?.email?.trim().isNotEmpty == true
            ? user!.email!
            : (existing?['email']?.toString() ?? widget.profile.email);

        await UserProfileService.instance.updateProfile(
          name: name,
          email: email,
          phone: existing?['phone']?.toString() ?? '',
          gender: existing?['gender']?.toString(),
          bloodGroup: existing?['bloodGroup']?.toString(),
          photoUrl: newPhotoUrl.isNotEmpty ? newPhotoUrl : null,
        );

        if (user != null && newPhotoUrl.isNotEmpty) {
          await user.updatePhotoURL(newPhotoUrl);
          await user.reload();
        }
      } else {
        String? newPhotoUrl = _photoUrl;
        if (_pickedBytes != null) {
          newPhotoUrl = await FirebaseService.instance.uploadUserAvatar(
            'legacy_admin',
            _pickedBytes!,
          );
        }
        await FirebaseService.instance.updateAdminDisplayProfile(
          name: name,
          photoUrl: newPhotoUrl ?? '',
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: C.success,
            content: Text('Profile updated', style: TextStyle(color: C.textPrimary)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final raw = e.toString().toLowerCase();
        final msg = raw.contains('unauthorized') || raw.contains('permission')
            ? 'Photo upload failed. Enable Firebase Storage in the console, then run: firebase deploy --only storage'
            : friendlyErrorMessage(e, prefix: 'Update failed:');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: C.accent,
            content: Text(msg, style: TextStyle(color: C.textPrimary)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: C.bg2,
      title: Text('Edit Admin Profile', style: TextStyle(color: C.textPrimary)),
      content: SizedBox(
        width: MediaQuery.of(context).size.width < 400
            ? MediaQuery.of(context).size.width * 0.9
            : 360.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _loading ? null : _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _buildAvatarPreview(),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: C.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Tap to change photo', style: TextStyle(color: C.textMuted, fontSize: 12)),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              style: TextStyle(color: C.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Display name',
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: C.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: C.accent),
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

void showAdminEditProfileDialog(BuildContext context, AdminDisplayProfile profile) {
  showDialog<bool>(
    context: context,
    builder: (ctx) => AdminEditProfileDialog(profile: profile),
  );
}
