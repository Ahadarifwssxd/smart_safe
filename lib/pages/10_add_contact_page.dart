import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import '../services/app_firestore_service.dart';
import '../theme/colors.dart';
import '../utils/error_message.dart';
import '../utils/phone_utils.dart';
import '../widgets/widgets.dart';

class AddContactPage extends StatefulWidget {
  const AddContactPage({super.key});

  @override
  State<AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<AddContactPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _relation = 'Family';
  bool _smsEnabled = true;
  bool _pushEnabled = true;
  bool _saving = false;
  String _completePhoneNumber = '';
  bool _phoneValid = false;
  final _relations = ['Family', 'Friend', 'Work', 'Other'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_smsEnabled && !_pushEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.accent,
          content: Text(
              'Turn on at least one alert (SMS or Push notification).',
              style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // Email is NOT asked from the user anymore. If this phone belongs to a
      // registered SmartSafe user, pull their (verified) email automatically so
      // email SOS alerts still work — otherwise it's simply left blank.
      String autoEmail = '';
      final norm = normalizePhone(_completePhoneNumber.trim());
      if (norm.isNotEmpty) {
        try {
          final q = await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNormalized', isEqualTo: norm)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            autoEmail = q.docs.first.data()['email']?.toString() ?? '';
          }
        } catch (_) {}
      }

      await AppFirestoreService.instance.addEmergencyContact(
        name: _nameCtrl.text.trim(),
        phone: _completePhoneNumber.trim(),
        email: autoEmail,
        relationship: _relation,
        colorHex: AppColors.accent.value,
        smsAlert: _smsEnabled,
        pushAlert: _pushEnabled,
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accent,
            content: const Text('Contact saved successfully.',
                style: TextStyle(color: Colors.white)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: AppColors.accent,
              content: Text(friendlyErrorMessage(e, prefix: 'Save failed:'),
                  style: TextStyle(color: Colors.white))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateName(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Name is required';
    if (t.length < 2) return 'At least 2 characters';
    return null;
  }

  String? _validatePhone(dynamic v) {
    if (_phoneCtrl.text.trim().isEmpty) return 'Phone number is required';
    if (!_phoneValid) return 'Enter a valid phone number';
    return null;
  }

  String get _initials {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: SlideUpFade(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.bg2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Icon(Icons.arrow_back_ios_new_rounded,
                                color: C.textPrimary, size: 18),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text('Add Emergency Contact',
                            style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),

                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          // Avatar preview
                          SlideUpFade(
                            delay: const Duration(milliseconds: 80),
                            child: Center(
                              child: AnimatedBuilder(
                                animation: _nameCtrl,
                                builder: (_, __) => Column(
                                  children: [
                                    AvatarWidget(
                                      initials: _initials,
                                      color: AppColors.accent,
                                      size: 80,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _nameCtrl.text.isEmpty
                                          ? 'Preview'
                                          : _nameCtrl.text,
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Name field
                          SlideUpFade(
                            delay: const Duration(milliseconds: 160),
                            child: _InputField(
                              controller: _nameCtrl,
                              label: 'Full Name *',
                              hint: 'e.g. Amna Riaz',
                              icon: Icons.person_rounded,
                              validator: _validateName,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Phone field
                          SlideUpFade(
                            delay: const Duration(milliseconds: 200),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Phone Number *',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    )),
                                const SizedBox(height: 8),
                                IntlPhoneField(
                                  controller: _phoneCtrl,
                                  initialCountryCode: 'PK',
                                  showCountryFlag: false,
                                  dropdownTextStyle: TextStyle(color: C.textPrimary),
                                  style: TextStyle(color: C.textPrimary),
                                  pickerDialogStyle: PickerDialogStyle(
                                    backgroundColor: AppColors.bg2,
                                    countryNameStyle: TextStyle(color: C.textPrimary),
                                    countryCodeStyle: TextStyle(color: C.textMuted),
                                    searchFieldInputDecoration: InputDecoration(
                                      hintText: 'Search country',
                                      hintStyle: TextStyle(color: C.textMuted),
                                      prefixIcon: Icon(Icons.search, color: C.textMuted),
                                    ),
                                  ),
                                  onChanged: (phone) {
                                    _completePhoneNumber = phone.completeNumber;
                                    try {
                                      _phoneValid = phone.isValidNumber();
                                    } catch (_) {
                                      _phoneValid = false;
                                    }
                                  },
                                  validator: _validatePhone,
                                  decoration: InputDecoration(
                                    hintText: '3XXXXXXXXX',
                                    hintStyle: TextStyle(color: AppColors.textMuted),
                                    filled: true,
                                    fillColor: AppColors.bg2,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),


                          // Relation selector
                          SlideUpFade(
                            delay: const Duration(milliseconds: 240),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Relationship',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    )),
                                const SizedBox(height: 8),
                                Row(
                                  children: _relations.map((r) {
                                    final sel = r == _relation;
                                    return Expanded(
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _relation = r),
                                        child: Container(
                                          margin:
                                              const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: sel
                                                ? AppColors.accent
                                                    .withValues(alpha: 0.15)
                                                : AppColors.bg2,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: sel
                                                  ? AppColors.accent
                                                      .withValues(alpha: 0.5)
                                                  : AppColors.border,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(r,
                                                style: TextStyle(
                                                  color: sel
                                                      ? AppColors.accent
                                                      : AppColors.textMuted,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                )),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Alert toggles
                          SlideUpFade(
                            delay: const Duration(milliseconds: 280),
                            child: DCard(
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.sms_rounded,
                                          color: AppColors.accent, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('SMS Alert',
                                                style: TextStyle(
                                                    color: C.textPrimary,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13)),
                                            Text('Sent even without internet',
                                                style: TextStyle(
                                                    color: AppColors.textMuted,
                                                    fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: _smsEnabled,
                                        onChanged: (v) =>
                                            setState(() => _smsEnabled = v),
                                        activeThumbColor: AppColors.accent,
                                        activeTrackColor:
                                            AppColors.accent.withValues(alpha: 0.3),
                                        inactiveThumbColor: AppColors.textMuted,
                                        inactiveTrackColor: AppColors.border,
                                      ),
                                    ],
                                  ),
                                  Divider(color: AppColors.border, height: 20),
                                  Row(
                                    children: [
                                      Icon(Icons.notifications_rounded,
                                          color: AppColors.accent, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('App Push Notification',
                                                style: TextStyle(
                                                    color: C.textPrimary,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13)),
                                            Text('Requires SmartSafe installed',
                                                style: TextStyle(
                                                    color: AppColors.textMuted,
                                                    fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: _pushEnabled,
                                        onChanged: (v) =>
                                            setState(() => _pushEnabled = v),
                                        activeThumbColor: AppColors.accent,
                                        activeTrackColor:
                                            AppColors.accent.withValues(alpha: 0.3),
                                        inactiveThumbColor: AppColors.textMuted,
                                        inactiveTrackColor: AppColors.border,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Info card
                          SlideUpFade(
                            delay: const Duration(milliseconds: 320),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: AppColors.accent.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline_rounded,
                                      color: AppColors.accent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'This contact will receive your location and SOS alerts automatically',
                                      style: TextStyle(
                                          color: AppColors.textMuted, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Save button
                          SlideUpFade(
                            delay: const Duration(milliseconds: 360),
                            child: ElevatedButton(
                              onPressed: _saving ? null : _saveContact,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Save Contact',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      )),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
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

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          validator: validator,
          style: TextStyle(color: C.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.textMuted),
            prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
            filled: true,
            fillColor: AppColors.bg2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.accent, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}
