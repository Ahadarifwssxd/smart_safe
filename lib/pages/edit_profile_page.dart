import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../navigation/dark_route.dart';
import '../services/cloudinary_service.dart';
import '../utils/media_image.dart';
import '../services/user_profile_service.dart';
import '../theme/colors.dart';
import '../utils/error_message.dart';
import '../widgets/widgets.dart';

class EditProfilePage extends StatefulWidget {
  final UserProfile profile;
  const EditProfilePage({super.key, required this.profile});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late String _gender;
  String? _bloodGroup;
  bool _loading = false;
  String? _nameErr, _emailErr, _phoneErr;
  late String _completePhoneNumber;
  bool _phoneValid = true;
  late String _photoUrl;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    // Fall back to the signed-in account so name/email are never blank — e.g. a
    // Google sign-up carries displayName + email, and email always comes from
    // the auth account even if the Firestore profile doc is missing it.
    final authUser = FirebaseAuth.instance.currentUser;
    final email = widget.profile.email.isNotEmpty
        ? widget.profile.email
        : (authUser?.email ?? '');
    // Name fallback chain so it's NEVER blank: saved name → Google displayName →
    // a friendly name derived from the email (e.g. "aa@gmail.com" → "Aa").
    String name = widget.profile.name.trim();
    if (name.isEmpty) name = authUser?.displayName?.trim() ?? '';
    if (name.isEmpty) name = _nameFromEmail(email);
    _name = TextEditingController(text: name);
    _email = TextEditingController(text: email);
    
    // Phone number is fixed (verified at signup) and shown read-only here, so no
    // country parsing or re-verification is needed — just display it as saved.
    _phone = TextEditingController(text: widget.profile.phone);
    _completePhoneNumber = widget.profile.phone;
    _phoneValid = widget.profile.phone.isNotEmpty;
    _gender = widget.profile.gender.isNotEmpty ? widget.profile.gender : 'Female';
    _bloodGroup = widget.profile.bloodGroup.isNotEmpty ? widget.profile.bloodGroup : null;
    _photoUrl = widget.profile.photoUrl;
  }

  /// Pick an image and upload it as the profile photo (via Cloudinary).
  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
      if (picked == null) return;
      setState(() => _uploadingPhoto = true);
      final bytes = await picked.readAsBytes();
      // Stored inline (base64) — no Cloudinary/media host needed.
      final url = await CloudinaryService.instance
          .storeImage(bytes, folder: 'user_avatars');
      if (mounted) {
        setState(() {
          _photoUrl = url;
          _uploadingPhoto = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        _snack(friendlyErrorMessage(e, prefix: 'Photo upload failed:'), C.accent);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Turns an email into a friendly starting name, e.g. "john.doe@x.com" →
  /// "John Doe". Best-effort only — the user can edit it.
  String _nameFromEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return '';
    final raw = email.substring(0, at).replaceAll(RegExp(r'[._\-]+'), ' ').trim();
    return raw
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d\-.]+$').hasMatch(v.trim());
  bool _isValidName(String v) =>
      RegExp(r'^[a-zA-Z\s]+$').hasMatch(v.trim()) && v.trim().length >= 2;

  Future<void> _save() async {
    String? ne, ee, pe;
    if (_name.text.trim().isEmpty) {
      ne = 'Full name is required';
    } else if (!_isValidName(_name.text)) {
      ne = 'Name must contain only letters and spaces (min 2 chars)';
    }
    if (_email.text.trim().isEmpty) {
      ee = 'Email is required';
    } else if (!_isValidEmail(_email.text)) {
      ee = 'Enter a valid email address';
    }
    if (_phone.text.trim().isEmpty) {
      pe = 'Phone number is required';
    } else if (!_phoneValid) {
      pe = 'Enter a valid phone number';
    }

    if (ne != null || ee != null || pe != null) {
      setState(() {
        _nameErr = ne;
        _emailErr = ee;
        _phoneErr = pe;
      });
      return;
    }

    setState(() {
      _nameErr = _emailErr = _phoneErr = null;
      _loading = true;
    });

    // The phone number can't be changed on this screen (it's the verified number
    // tied to the account), so no re-verification is needed — save directly.
    await _persist(phoneVerified: true);
  }

  void _snack(String msg, Color color, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: duration ?? const Duration(seconds: 4),
      content: Text(msg, style: TextStyle(color: C.textPrimary)),
    ));
  }

  Future<void> _persist({required bool phoneVerified}) async {
    try {
      await UserProfileService.instance.updateProfile(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _completePhoneNumber.trim(),
        gender: _gender,
        bloodGroup: _bloodGroup,
        phoneVerified: phoneVerified,
        photoUrl: _photoUrl.isNotEmpty ? _photoUrl : null,
      );
      if (mounted) {
        _snack('Profile updated', C.success);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(friendlyErrorMessage(e, prefix: 'Update failed:'), C.accent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = _name.text.trim().isEmpty
        ? widget.profile.initials
        : (_name.text.trim().length >= 2
            ? '${_name.text.trim()[0]}${_name.text.trim().split(RegExp(r'\s+')).length > 1 ? _name.text.trim().split(RegExp(r'\s+'))[1][0] : ''}'
                .toUpperCase()
            : _name.text.trim()[0].toUpperCase());

    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          const DotGrid(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: _uploadingPhoto ? null : _pickPhoto,
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 44,
                                  backgroundColor: C.accent,
                                  backgroundImage: mediaImageProvider(_photoUrl),
                                  child: _uploadingPhoto
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white),
                                        )
                                      : (_photoUrl.isEmpty
                                          ? Text(
                                              initials.length > 2
                                                  ? initials.substring(0, 2)
                                                  : initials,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 30,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            )
                                          : null),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: C.bg2,
                                      shape: BoxShape.circle,
                                      border:
                                          Border.all(color: C.accent, width: 2),
                                    ),
                                    child: Icon(Icons.camera_alt_rounded,
                                        color: C.accent, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _name,
                          onChanged: (_) {
                            setState(() {});
                            if (_nameErr != null) setState(() => _nameErr = null);
                          },
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: const Icon(Icons.person_rounded),
                            errorText: _nameErr,
                          ),
                          style: TextStyle(color: C.textPrimary),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _email,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Email (Cannot be changed)',
                            prefixIcon: const Icon(Icons.email_rounded),
                            errorText: _emailErr,
                            filled: true,
                            fillColor: C.bg2.withValues(alpha: 0.5),
                          ),
                          style: TextStyle(color: C.textMuted),
                        ),
                        const SizedBox(height: 14),
                        // Phone number is locked — it's the verified number tied
                        // to this account and cannot be changed here.
                        TextField(
                          controller: _phone,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Phone number (Cannot be changed)',
                            prefixIcon: const Icon(Icons.phone_rounded),
                            suffixIcon: Icon(Icons.lock_outline_rounded,
                                size: 18, color: C.textMuted),
                            filled: true,
                            fillColor: C.bg2.withValues(alpha: 0.5),
                          ),
                          style: TextStyle(color: C.textMuted),
                        ),
                        const SizedBox(height: 16),
                        const SecHeader('Gender'),
                        const SizedBox(height: 8),
                        Row(
                          children: ['Female', 'Male', 'Other'].map((g) {
                            final sel = g == _gender;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: GestureDetector(
                                  onTap: () => setState(() => _gender = g),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: sel ? C.accent : C.bg2,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: sel ? C.accent : C.textDim),
                                    ),
                                    child: Text(
                                      g,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: sel ? Colors.white : C.textMuted,
                                        fontSize: 13,
                                        fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: _loading ? null : _save,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              color: _loading ? C.textDim : C.accent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: _loading
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : Text(
                                      'Save Changes',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void openEditProfile(BuildContext context, UserProfile profile) {
  Navigator.push(
    context,
    darkRoute(EditProfilePage(profile: profile)),
  );
}
