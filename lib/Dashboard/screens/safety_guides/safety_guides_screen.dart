import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/models/safety_guide.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

/// Admin CMS for the app's Driving / Child Safety / First-Aid guide pages.
/// Everything shown on those pages is add/edit/delete-able here.
class SafetyGuidesScreen extends StatefulWidget {
  const SafetyGuidesScreen({super.key});

  @override
  State<SafetyGuidesScreen> createState() => _SafetyGuidesScreenState();
}

class _SafetyGuidesScreenState extends State<SafetyGuidesScreen> {
  String _filter = 'all'; // all | driving | child | first_aid

  static const _categories = {
    kGuideDriving: '🚗 Driving',
    kGuideChild: '🧒 Child',
    kGuideFirstAid: '❤️ First Aid',
  };

  final _titleCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  final _detailCtrl = TextEditingController();
  final _stepsCtrl = TextEditingController();
  String _cat = kGuideFirstAid;
  bool _urgent = false;
  int _colorHex = 0xFFE63946;

  static const _palette = [
    0xFFE63946, 0xFF00B4D8, 0xFF06D6A0, 0xFFF4A261, 0xFF9B5DE5, 0xFFFFB347,
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _emojiCtrl.dispose();
    _detailCtrl.dispose();
    _stepsCtrl.dispose();
    super.dispose();
  }

  void _openDialog([DocumentSnapshot? existing]) {
    if (existing != null) {
      final d = existing.data() as Map<String, dynamic>;
      _cat = d['category']?.toString() ?? kGuideFirstAid;
      _titleCtrl.text = d['title']?.toString() ?? '';
      _emojiCtrl.text = d['emoji']?.toString() ?? '📌';
      _detailCtrl.text = d['detail']?.toString() ?? '';
      _stepsCtrl.text =
          ((d['steps'] as List?)?.map((e) => e.toString()).toList() ?? [])
              .join('\n');
      _urgent = d['urgent'] == true;
      _colorHex = (d['colorHex'] as num?)?.toInt() ?? 0xFFE63946;
    } else {
      _cat = _filter == 'all' ? kGuideFirstAid : _filter;
      _titleCtrl.clear();
      _emojiCtrl.text = '📌';
      _detailCtrl.clear();
      _stepsCtrl.clear();
      _urgent = false;
      _colorHex = 0xFFE63946;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: C.bg2,
          title: Text(existing == null ? 'Add Guide' : 'Edit Guide',
              style: TextStyle(color: C.textPrimary)),
          content: SizedBox(
            width: MediaQuery.of(ctx).size.width < 500
                ? MediaQuery.of(ctx).size.width * 0.9
                : 460.0,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    dropdownColor: C.bg2,
                    initialValue: _cat,
                    decoration: const InputDecoration(labelText: 'Category *'),
                    items: _categories.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value,
                                style: TextStyle(color: C.textPrimary))))
                        .toList(),
                    onChanged: (v) => setInner(() => _cat = v ?? _cat),
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: _emojiCtrl,
                          style:
                              TextStyle(color: C.textPrimary, fontSize: 22),
                          decoration: const InputDecoration(labelText: 'Icon'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _titleCtrl,
                          style: TextStyle(color: C.textPrimary),
                          decoration:
                              const InputDecoration(labelText: 'Title *'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _detailCtrl,
                    style: TextStyle(color: C.textPrimary),
                    decoration: const InputDecoration(
                        labelText: 'Short description (optional)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _stepsCtrl,
                    style: TextStyle(color: C.textPrimary),
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Steps — ONE per line',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Wrap (not Row): the urgent switch + six swatches overflow a
                  // narrow phone dialog when forced onto a single line.
                  Wrap(
                    spacing: 6,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Urgent', style: TextStyle(color: C.textMuted)),
                      Switch(
                        value: _urgent,
                        activeColor: C.accent,
                        onChanged: (v) => setInner(() => _urgent = v),
                      ),
                      const SizedBox(width: 4),
                      for (final c in _palette)
                        GestureDetector(
                          onTap: () => setInner(() => _colorHex = c),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _colorHex == c
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: C.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: C.accent),
              onPressed: () async {
                final title = _titleCtrl.text.trim();
                if (title.isEmpty) return;
                final steps = _stepsCtrl.text
                    .split('\n')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                try {
                  if (existing == null) {
                    await FirebaseService.instance.addSafetyGuide(
                      category: _cat,
                      title: title,
                      emoji: _emojiCtrl.text.trim().isEmpty
                          ? '📌'
                          : _emojiCtrl.text.trim(),
                      detail: _detailCtrl.text.trim(),
                      steps: steps,
                      colorHex: _colorHex,
                      urgent: _urgent,
                    );
                  } else {
                    await FirebaseService.instance.updateSafetyGuide(
                      existing.id,
                      category: _cat,
                      title: title,
                      emoji: _emojiCtrl.text.trim().isEmpty
                          ? '📌'
                          : _emojiCtrl.text.trim(),
                      detail: _detailCtrl.text.trim(),
                      steps: steps,
                      colorHex: _colorHex,
                      urgent: _urgent,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(DocumentSnapshot doc) {
    final title = (doc.data() as Map<String, dynamic>)['title'] ?? 'this guide';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Delete guide', style: TextStyle(color: C.textPrimary)),
        content: Text('Delete "$title"?', style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              await FirebaseService.instance.deleteSafetyGuide(doc.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
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
            PageHeaderBar(
              title: 'Safety Guides',
              subtitle:
                  'Driving, Child Safety & First-Aid content — shown live in the app.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                  onPressed: () => _openDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Guide'),
                ),
              ],
            ),
            const SizedBox(height: defaultPadding),
            // Category filter
            Wrap(
              spacing: 8,
              children: [
                _chip('all', 'All'),
                for (final e in _categories.entries) _chip(e.key, e.value),
              ],
            ),
            const SizedBox(height: defaultPadding),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getSafetyGuidesStream(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                var docs = snap.data!.docs.toList();
                if (_filter != 'all') {
                  docs = docs
                      .where((d) =>
                          (d.data() as Map<String, dynamic>)['category'] ==
                          _filter)
                      .toList();
                }
                docs.sort((a, b) {
                  final am = a.data() as Map<String, dynamic>;
                  final bm = b.data() as Map<String, dynamic>;
                  final ac = (am['category'] ?? '').toString();
                  final bc = (bm['category'] ?? '').toString();
                  if (ac != bc) return ac.compareTo(bc);
                  return ((am['sortOrder'] ?? 0) as num)
                      .compareTo((bm['sortOrder'] ?? 0) as num);
                });
                if (docs.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: secondaryColor,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        'No guides yet. Tap "Add Guide", or they seed automatically on first app launch.',
                        style: TextStyle(color: C.textMuted)),
                  );
                }
                return Column(
                  children: docs.map(_guideTile).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      backgroundColor: C.bg2,
      selectedColor: C.accent.withValues(alpha: 0.25),
      labelStyle:
          TextStyle(color: selected ? C.accent : C.textMuted, fontSize: 12),
    );
  }

  Widget _guideTile(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final steps =
        (d['steps'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final color = Color((d['colorHex'] as num?)?.toInt() ?? 0xFF00B4D8);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10)),
            child: Text(d['emoji']?.toString() ?? '📌',
                style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(d['title']?.toString() ?? '',
                          style: TextStyle(
                              color: C.textPrimary,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: C.bg,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                          _categories[d['category']] ??
                              d['category']?.toString() ??
                              '',
                          style:
                              TextStyle(color: C.textMuted, fontSize: 10)),
                    ),
                    if (d['urgent'] == true) ...[
                      const SizedBox(width: 6),
                      Text('URGENT',
                          style: TextStyle(
                              color: C.accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
                if ((d['detail']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(d['detail'].toString(),
                        style: TextStyle(color: C.textMuted, fontSize: 11)),
                  ),
                if (steps.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${steps.length} step(s)',
                        style: TextStyle(color: C.textMuted, fontSize: 11)),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit, color: C.accent, size: 18),
            onPressed: () => _openDialog(doc),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
            onPressed: () => _confirmDelete(doc),
          ),
        ],
      ),
    );
  }
}
