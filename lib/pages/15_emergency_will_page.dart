import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../Dashboard/services/firebase_service.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class EmergencyWillPage extends StatefulWidget {
  const EmergencyWillPage({super.key});

  @override
  State<EmergencyWillPage> createState() => _EmergencyWillPageState();
}

class _EmergencyWillPageState extends State<EmergencyWillPage> {
  // Real values keyed by field id, loaded from / saved to Firestore.
  final Map<String, String> _values = {};
  bool _loading = true;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('emergency_info').doc(_uid);

  // Live sections: default to the built-in set, then get replaced by whatever
  // the admin has configured in the dashboard (fetched from Firestore).
  late List<_InfoSection> _sections = _defaultSections;

  final List<_InfoSection> _defaultSections = [
    _InfoSection(Icons.person_rounded, AppColors.accent, 'Personal Identity',
        'Name, CNIC, Blood Group', [
      const _Field('Full Name', 'name', validator: _vName),
      const _Field('CNIC', 'cnic',
          keyboard: TextInputType.number,
          hint: '42101-1234567-1',
          validator: _vCnic),
      const _Field('Blood Group', 'blood', hint: 'e.g. O+', validator: _vBlood),
      const _Field('Date of Birth', 'dob',
          hint: 'DD/MM/YYYY', validator: _vDob),
    ]),
    _InfoSection(Icons.medical_services_rounded, AppColors.accent, 'Medical Info',
        'Allergies, medications, conditions', [
      const _Field('Allergies', 'allergies'),
      const _Field('Medications', 'medications'),
      const _Field('Conditions', 'conditions'),
      const _Field('Doctor', 'doctor',
          keyboard: TextInputType.phone, validator: _vPhone),
    ]),
    _InfoSection(Icons.account_balance_rounded, AppColors.accent,
        'Financial Access', 'Bank, insurance, accounts', [
      const _Field('Bank', 'bank'),
      const _Field('Insurance', 'insurance'),
      const _Field('Mobile Wallet', 'wallet',
          keyboard: TextInputType.phone, validator: _vPhone),
    ]),
    _InfoSection(Icons.gavel_rounded, AppColors.warning, 'Legal & Next of Kin',
        'Will, property, next of kin', [
      const _Field('Next of Kin', 'kin', validator: _vName),
      const _Field('Property', 'property'),
    ]),
    _InfoSection(Icons.favorite_rounded, AppColors.success, 'Last Wishes',
        'A personal message to your loved ones', [
      const _Field('Message', 'message'),
    ]),
  ];

  StreamSubscription<QuerySnapshot>? _fieldsSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Seed defaults once (no-op if the admin already configured fields), then
    // listen so any add/update/delete from the dashboard reflects live here.
    FirebaseService.instance.seedWillFieldsIfEmpty();
    _fieldsSub = FirebaseService.instance.getWillFieldsStream().listen(
      _applyFieldDocs,
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _fieldsSub?.cancel();
    super.dispose();
  }

  /// Rebuilds the on-screen sections from the admin-configured field docs.
  /// Falls back to the built-in defaults when nothing is configured yet.
  void _applyFieldDocs(QuerySnapshot snap) {
    if (snap.docs.isEmpty) {
      if (mounted) setState(() => _sections = _defaultSections);
      return;
    }
    // Group fields by section, preserving admin-defined ordering.
    final bySection = <String, List<Map<String, dynamic>>>{};
    final sectionOrder = <String, int>{};
    for (final d in snap.docs) {
      final m = (d.data() as Map<String, dynamic>?) ?? {};
      final section = (m['section'] ?? 'Details').toString();
      bySection.putIfAbsent(section, () => []).add(m);
      sectionOrder[section] =
          (m['sectionOrder'] as num?)?.toInt() ?? sectionOrder[section] ?? 0;
    }
    final orderedSections = bySection.keys.toList()
      ..sort((a, b) =>
          (sectionOrder[a] ?? 0).compareTo(sectionOrder[b] ?? 0));

    final built = <_InfoSection>[];
    for (final section in orderedSections) {
      final fields = bySection[section]!
        ..sort((a, b) => ((a['order'] as num?)?.toInt() ?? 0)
            .compareTo((b['order'] as num?)?.toInt() ?? 0));
      final infoFields = <_Field>[];
      for (final f in fields) {
        final key = (f['fieldKey'] ?? '').toString();
        final label = (f['label'] ?? key).toString();
        if (key.isEmpty) continue;
        infoFields.add(_Field(label, key, keyboard: _keyboardFor(key)));
      }
      if (infoFields.isEmpty) continue;
      final count = infoFields.length;
      built.add(_InfoSection(_iconFor(section), AppColors.accent, section,
          '$count field${count == 1 ? '' : 's'}', infoFields));
    }
    if (built.isEmpty) built.addAll(_defaultSections);
    if (mounted) setState(() => _sections = built);
  }

  IconData _iconFor(String section) {
    final s = section.toLowerCase();
    if (s.contains('personal') || s.contains('identity')) {
      return Icons.person_rounded;
    }
    if (s.contains('medical') || s.contains('health')) {
      return Icons.medical_services_rounded;
    }
    if (s.contains('financ') || s.contains('bank') || s.contains('money')) {
      return Icons.account_balance_rounded;
    }
    if (s.contains('legal') || s.contains('kin') || s.contains('law')) {
      return Icons.gavel_rounded;
    }
    if (s.contains('wish') || s.contains('message') || s.contains('note')) {
      return Icons.favorite_rounded;
    }
    return Icons.folder_rounded;
  }

  TextInputType _keyboardFor(String key) {
    final k = key.toLowerCase();
    if (k.contains('phone') || k.contains('cnic') || k.contains('number')) {
      return TextInputType.phone;
    }
    if (k.contains('email')) return TextInputType.emailAddress;
    if (k == 'message' || k.contains('note') || k.contains('address')) {
      return TextInputType.multiline;
    }
    return TextInputType.text;
  }

  Future<void> _load() async {
    if (_uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final snap = await _doc.get();
      final data = snap.data() ?? {};
      for (final e in data.entries) {
        _values[e.key] = e.value?.toString() ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<_Field> get _allFields => _sections.expand((s) => s.fields).toList();
  int get _filled =>
      _allFields.where((f) => (_values[f.key] ?? '').trim().isNotEmpty).length;

  bool _sectionComplete(_InfoSection s) =>
      s.fields.every((f) => (_values[f.key] ?? '').trim().isNotEmpty);

  Future<void> _editField(_Field f) async {
    final ctrl = TextEditingController(text: _values[f.key] ?? '');
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: C.bg2,
          title: Text(f.label, style: TextStyle(color: C.textPrimary)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: f.key == 'message' ? 4 : 1,
            keyboardType: f.keyboard,
            style: TextStyle(color: C.textPrimary),
            onChanged: (_) {
              if (error != null) setLocal(() => error = null);
            },
            decoration: InputDecoration(
              hintText: f.hint ?? 'Enter ${f.label.toLowerCase()}',
              hintStyle: TextStyle(color: C.textMuted),
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: C.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: C.accent),
              onPressed: () {
                final text = ctrl.text.trim();
                final err = f.validator?.call(text);
                if (err != null) {
                  setLocal(() => error = err);
                  return;
                }
                Navigator.pop(ctx, text);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    setState(() => _values[f.key] = result);
    if (_uid != null) {
      try {
        await _doc.set({f.key: result, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
      } catch (_) {}
    }
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: SlideUpFade(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (Navigator.canPop(context)) ...[
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Icon(Icons.arrow_back_ios_new_rounded,
                                    color: C.textPrimary, size: 18),
                              ),
                              const SizedBox(width: 12),
                            ],
                            DynText('emergency_will', 'title', 'Emergency Info',
                                style: TextStyle(
                                    color: C.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(children: [
                                Icon(Icons.lock_rounded,
                                    color: AppColors.accent, size: 13),
                                const SizedBox(width: 4),
                                Text('Private',
                                    style: TextStyle(
                                        color: AppColors.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ],
                        ),
                        Text('Critical info for emergencies — tap any field to fill it',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 16),
                        Row(children: [
                          Text('$_filled/${_allFields.length} filled',
                              style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Text(
                              '${_allFields.isEmpty ? 0 : ((_filled / _allFields.length) * 100).round()}%',
                              style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _allFields.isEmpty
                                ? 0
                                : _filled / _allFields.length,
                            minHeight: 8,
                            backgroundColor: AppColors.border,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(color: C.accent))
                      : ListView.builder(
                          cacheExtent: 500,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _sections.length,
                          itemBuilder: (ctx, i) {
                            final s = _sections[i];
                            return SlideUpFade(
                              delay: Duration(milliseconds: 80 + i * 50),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _SectionCard(
                                  section: s,
                                  complete: _sectionComplete(s),
                                  value: (k) => _values[k] ?? '',
                                  onToggle: () => setState(
                                      () => s.isExpanded = !s.isExpanded),
                                  onEdit: _editField,
                                ),
                              ),
                            );
                          },
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

class _SectionCard extends StatelessWidget {
  final _InfoSection section;
  final bool complete;
  final String Function(String key) value;
  final VoidCallback onToggle;
  final void Function(_Field) onEdit;

  const _SectionCard({
    required this.section,
    required this.complete,
    required this.value,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: complete
              ? section.color.withValues(alpha: 0.25)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: section.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(section.icon, color: section.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(section.title,
                            style: TextStyle(
                                color: C.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        Text(section.subtitle,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (complete)
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 20)
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Incomplete',
                          style: TextStyle(
                              color: AppColors.warning, fontSize: 10)),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    section.isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (section.isExpanded) ...[
            Divider(color: AppColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: section.fields.map((f) {
                  final v = value(f.key);
                  return GestureDetector(
                    onTap: () => onEdit(f),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(f.label,
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                          ),
                          Expanded(
                            child: Text(v.isEmpty ? 'Tap to add' : v,
                                style: TextStyle(
                                  color:
                                      v.isEmpty ? AppColors.textDim : C.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )),
                          ),
                          Icon(Icons.edit_rounded,
                              color: section.color.withValues(alpha: 0.6),
                              size: 14),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoSection {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<_Field> fields;
  bool isExpanded = false;

  _InfoSection(this.icon, this.color, this.title, this.subtitle, this.fields);
}

class _Field {
  final String label;
  final String key;
  final String? hint;
  final TextInputType keyboard;
  // Returns an error string when [value] is invalid, or null when it's OK.
  // All validators ALLOW empty (fields are optional) — they only enforce the
  // format once the user actually types something.
  final String? Function(String value)? validator;
  const _Field(
    this.label,
    this.key, {
    this.hint,
    this.keyboard = TextInputType.text,
    this.validator,
  });
}

// ── Field validators (top-level so they stay const-usable in _Field) ────────
String? _vCnic(String v) {
  if (v.isEmpty) return null;
  final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 13) return 'CNIC must be 13 digits (e.g. 42101-1234567-1)';
  return null;
}

String? _vBlood(String v) {
  if (v.isEmpty) return null;
  const groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  if (!groups.contains(v.toUpperCase().replaceAll(' ', ''))) {
    return 'Enter a valid blood group (A+, O-, AB+ …)';
  }
  return null;
}

String? _vDob(String v) {
  if (v.isEmpty) return null;
  // Accept DD/MM/YYYY or YYYY-MM-DD.
  final ok = RegExp(r'^\d{1,2}[/-]\d{1,2}[/-]\d{4}$').hasMatch(v) ||
      RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(v);
  if (!ok) return 'Use DD/MM/YYYY (e.g. 05/08/1998)';
  return null;
}

String? _vPhone(String v) {
  if (v.isEmpty) return null;
  final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 7 || digits.length > 15) return 'Enter a valid phone number';
  return null;
}

String? _vName(String v) {
  if (v.isEmpty) return null;
  if (v.trim().length < 2) return 'Enter a valid name';
  return null;
}
