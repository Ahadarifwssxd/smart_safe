import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';

/// Admin-only view of each user's private "Emergency Will / Info" (filled in
/// the mobile app). This data is intentionally NOT shared with contacts or
/// other users — it only surfaces here, in the dashboard.
class EmergencyWillScreen extends StatelessWidget {
  const EmergencyWillScreen({super.key});

  // Field key → human label + which section it belongs to (mirrors the app).
  static const _groups = <String, List<List<String>>>{
    'Personal Identity': [
      ['name', 'Full Name'],
      ['cnic', 'CNIC'],
      ['blood', 'Blood Group'],
      ['dob', 'Date of Birth'],
    ],
    'Medical Info': [
      ['allergies', 'Allergies'],
      ['medications', 'Medications'],
      ['conditions', 'Conditions'],
      ['doctor', 'Doctor'],
    ],
    'Financial Access': [
      ['bank', 'Bank'],
      ['insurance', 'Insurance'],
      ['wallet', 'Mobile Wallet'],
    ],
    'Legal & Next of Kin': [
      ['kin', 'Next of Kin'],
      ['property', 'Property'],
    ],
    'Last Wishes': [
      ['message', 'Message'],
    ],
  };

  static const _allKeys = [
    'name', 'cnic', 'blood', 'dob', 'allergies', 'medications', 'conditions',
    'doctor', 'bank', 'insurance', 'wallet', 'kin', 'property', 'message',
  ];

  int _filled(Map<String, dynamic> d) =>
      _allKeys.where((k) => (d[k]?.toString().trim() ?? '').isNotEmpty).length;

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
              title: 'Emergency Will & Info',
              subtitle:
                  'Configure the fields users fill in the app, and review what they submitted.',
            ),
            const SizedBox(height: defaultPadding),
            const _FieldManager(),
            const SizedBox(height: defaultPadding),
            Text('User Submissions',
                style: TextStyle(
                    color: C.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getEmergencyInfoStream(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snap.data!.docs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  return _filled(m) > 0;
                }).toList();
                if (docs.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: secondaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'No user has filled their emergency info yet.',
                      style: TextStyle(color: C.textMuted),
                    ),
                  );
                }
                return Column(
                  children: docs
                      .map((d) => _UserCard(
                            data: d.data() as Map<String, dynamic>,
                            uid: d.id,
                            filled: _filled(d.data() as Map<String, dynamic>),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin panel to add / edit / delete the Emergency Will field definitions.
/// Whatever is configured here is what every app user sees in their form.
class _FieldManager extends StatefulWidget {
  const _FieldManager();

  @override
  State<_FieldManager> createState() => _FieldManagerState();
}

class _FieldManagerState extends State<_FieldManager> {
  @override
  void initState() {
    super.initState();
    // Populate defaults on first run so admins have something to edit.
    FirebaseService.instance.seedWillFieldsIfEmpty();
  }

  Future<void> _openEditor({DocumentSnapshot? doc}) async {
    final data = (doc?.data() as Map<String, dynamic>?) ?? {};
    final sectionCtrl =
        TextEditingController(text: (data['section'] ?? '').toString());
    final labelCtrl =
        TextEditingController(text: (data['label'] ?? '').toString());
    final keyCtrl =
        TextEditingController(text: (data['fieldKey'] ?? '').toString());
    final sectionOrderCtrl = TextEditingController(
        text: ((data['sectionOrder'] as num?)?.toInt() ?? 0).toString());
    final orderCtrl = TextEditingController(
        text: ((data['order'] as num?)?.toInt() ?? 0).toString());
    final isEdit = doc != null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: secondaryColor,
        title: Text(isEdit ? 'Edit Field' : 'Add Field',
            style: TextStyle(color: C.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dlgField(sectionCtrl, 'Section (e.g. Medical Info)'),
              _dlgField(labelCtrl, 'Label (e.g. Blood Group)'),
              _dlgField(keyCtrl, 'Field key (e.g. blood) — no spaces'),
              _dlgField(sectionOrderCtrl, 'Section order (0,1,2…)',
                  number: true),
              _dlgField(orderCtrl, 'Field order within section', number: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final section = sectionCtrl.text.trim();
      final label = labelCtrl.text.trim();
      final key = keyCtrl.text.trim().replaceAll(' ', '_');
      final sectionOrder = int.tryParse(sectionOrderCtrl.text.trim()) ?? 0;
      final order = int.tryParse(orderCtrl.text.trim()) ?? 0;
      if (section.isNotEmpty && label.isNotEmpty && key.isNotEmpty) {
        if (isEdit) {
          await FirebaseService.instance.updateWillField(doc.id,
              section: section,
              sectionOrder: sectionOrder,
              label: label,
              fieldKey: key,
              order: order);
        } else {
          await FirebaseService.instance.addWillField(
              section: section,
              sectionOrder: sectionOrder,
              label: label,
              fieldKey: key,
              order: order);
        }
      }
    }
    sectionCtrl.dispose();
    labelCtrl.dispose();
    keyCtrl.dispose();
    sectionOrderCtrl.dispose();
    orderCtrl.dispose();
  }

  Widget _dlgField(TextEditingController c, String hint,
      {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: C.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: C.textMuted, fontSize: 13),
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: C.border.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: C.accent),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(DocumentSnapshot doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: secondaryColor,
        title: Text('Delete field?', style: TextStyle(color: C.textPrimary)),
        content: Text(
          'This removes the field from every user\'s app form. Existing answers stay in their records.',
          style: TextStyle(color: C.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseService.instance.deleteWillField(doc.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: C.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Form Fields',
                    style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: C.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10)),
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Field'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('These are the fields users fill in the app\'s Emergency Will.',
              style: TextStyle(color: C.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.getWillFieldsStream(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data!.docs.toList()
                ..sort((a, b) {
                  final am = a.data() as Map<String, dynamic>;
                  final bm = b.data() as Map<String, dynamic>;
                  final so = ((am['sectionOrder'] as num?)?.toInt() ?? 0)
                      .compareTo((bm['sectionOrder'] as num?)?.toInt() ?? 0);
                  if (so != 0) return so;
                  return ((am['order'] as num?)?.toInt() ?? 0)
                      .compareTo((bm['order'] as num?)?.toInt() ?? 0);
                });
              if (docs.isEmpty) {
                return Text('No fields yet — add one above.',
                    style: TextStyle(color: C.textMuted));
              }
              // Group into sections for a tidy layout.
              String? lastSection;
              final children = <Widget>[];
              for (final d in docs) {
                final m = d.data() as Map<String, dynamic>;
                final section = (m['section'] ?? 'Details').toString();
                if (section != lastSection) {
                  lastSection = section;
                  children.add(Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(section.toUpperCase(),
                        style: TextStyle(
                            color: C.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6)),
                  ));
                }
                children.add(_fieldRow(d, m));
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children);
            },
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(DocumentSnapshot doc, Map<String, dynamic> m) {
    final label = (m['label'] ?? '').toString();
    final key = (m['fieldKey'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: C.bg.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: C.border.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(key,
                    style: TextStyle(color: C.textMuted, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.edit_rounded, size: 18, color: C.accent),
            onPressed: () => _openEditor(doc: doc),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: C.red),
            onPressed: () => _confirmDelete(doc),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;
  final int filled;
  const _UserCard(
      {required this.data, required this.uid, required this.filled});

  String _val(String k) => data[k]?.toString().trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final name = _val('name').isNotEmpty ? _val('name') : 'Unnamed user';
    final blood = _val('blood');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border.withValues(alpha: 0.12)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            backgroundColor: C.accent.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: C.accent, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(name,
              style: TextStyle(
                  color: C.textPrimary, fontWeight: FontWeight.w700)),
          subtitle: Text(
            'UID: $uid',
            style: TextStyle(color: C.textMuted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (blood.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: C.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(blood,
                      style: TextStyle(
                          color: C.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              Text('$filled/${EmergencyWillScreen._allKeys.length}',
                  style: TextStyle(color: C.textMuted, fontSize: 11)),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
          children: EmergencyWillScreen._groups.entries.map((entry) {
            final rows = entry.value
                .where((f) => _val(f[0]).isNotEmpty)
                .toList();
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(entry.key.toUpperCase(),
                    style: TextStyle(
                        color: C.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 6),
                ...rows.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            // Narrower label column on phones so the value
                            // still has room instead of being crushed.
                            width: Responsive.isMobile(context) ? 100 : 130,
                            child: Text(f[1],
                                style: TextStyle(
                                    color: C.textMuted, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_val(f[0]),
                                style: TextStyle(
                                    color: C.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    )),
                Divider(color: C.border.withValues(alpha: 0.1), height: 16),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
