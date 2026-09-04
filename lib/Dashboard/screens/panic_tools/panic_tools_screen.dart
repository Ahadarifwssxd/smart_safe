import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/models/app_structure.dart';
import 'package:smartsafe/models/panic_tool.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

/// Admin CMS for the informational cards on the app's Panic Toolkit page —
/// "What To Do Right Now", "Stay Calm & Breathe" and "After You're Safe". Each
/// card is add/edit/delete-able here. The interactive hardware tools (torch,
/// siren, fake call, distress timer) are wired in code and not managed here.
class PanicToolsScreen extends StatefulWidget {
  const PanicToolsScreen({super.key});

  @override
  State<PanicToolsScreen> createState() => _PanicToolsScreenState();
}

class _PanicToolsScreenState extends State<PanicToolsScreen> {
  String _filter = 'all'; // all | what_to_do | stay_calm | after

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _stepsCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  final _sortCtrl = TextEditingController();
  String _cat = kPanicWhatToDo;
  String _iconName = kPanicToolIcons.first;
  int _colorHex = 0xFFEF4444;

  static const _palette = [
    0xFFEF4444, 0xFFF59E0B, 0xFF22C55E, 0xFF00B4D8, 0xFF9B5DE5, 0xFF06D6A0,
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _stepsCtrl.dispose();
    _emojiCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  void _openDialog([DocumentSnapshot? existing]) {
    if (existing != null) {
      final d = existing.data() as Map<String, dynamic>;
      _cat = kPanicToolCategories.keys.contains(d['category']?.toString())
          ? d['category'].toString()
          : kPanicWhatToDo;
      _titleCtrl.text = d['title']?.toString() ?? '';
      _descCtrl.text = d['description']?.toString() ?? '';
      _stepsCtrl.text =
          ((d['steps'] as List?)?.map((e) => e.toString()).toList() ?? [])
              .join('\n');
      _emojiCtrl.text = d['emoji']?.toString() ?? '';
      final icon = d['iconName']?.toString() ?? '';
      _iconName = kPanicToolIcons.contains(icon) ? icon : kPanicToolIcons.first;
      _colorHex = (d['colorHex'] as num?)?.toInt() ?? 0xFFEF4444;
      _sortCtrl.text = ((d['sortOrder'] as num?)?.toInt() ?? 0).toString();
    } else {
      _cat = _filter == 'all' ? kPanicWhatToDo : _filter;
      _titleCtrl.clear();
      _descCtrl.clear();
      _stepsCtrl.clear();
      _emojiCtrl.clear();
      _iconName = kPanicToolIcons.first;
      _colorHex = 0xFFEF4444;
      _sortCtrl.text = '0';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: C.bg2,
          title: Text(existing == null ? 'Add Card' : 'Edit Card',
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
                    decoration: const InputDecoration(labelText: 'Section *'),
                    items: kPanicToolCategories.entries
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
                          decoration:
                              const InputDecoration(labelText: 'Emoji'),
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
                    controller: _descCtrl,
                    style: TextStyle(color: C.textPrimary),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description (short supporting line)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _stepsCtrl,
                    style: TextStyle(color: C.textPrimary),
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Steps — ONE per line',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    dropdownColor: C.bg2,
                    initialValue: _iconName,
                    decoration:
                        const InputDecoration(labelText: 'Icon (if no emoji)'),
                    items: kPanicToolIcons
                        .map((k) => DropdownMenuItem(
                              value: k,
                              child: Row(
                                children: [
                                  Icon(iconFromName(k),
                                      color: C.textPrimary, size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(k,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: C.textPrimary,
                                            fontSize: 12)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setInner(() => _iconName = v ?? _iconName),
                  ),
                  const SizedBox(height: 12),
                  // Wrap (not Row): on a narrow phone dialog the order field +
                  // six swatches don't fit on one line, they now flow instead
                  // of overflowing.
                  Wrap(
                    spacing: 6,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _sortCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: C.textPrimary),
                          decoration:
                              const InputDecoration(labelText: 'Order'),
                        ),
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
                final model = PanicTool(
                  category: _cat,
                  title: title,
                  description: _descCtrl.text.trim(),
                  steps: steps,
                  emoji: _emojiCtrl.text.trim(),
                  iconName: _iconName,
                  colorHex: _colorHex,
                  sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 0,
                );
                try {
                  if (existing == null) {
                    await FirebaseService.instance.addPanicTool(model);
                  } else {
                    await FirebaseService.instance
                        .updatePanicTool(existing.id, model);
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
    final title = (doc.data() as Map<String, dynamic>)['title'] ?? 'this card';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Delete card', style: TextStyle(color: C.textPrimary)),
        content: Text('Delete "$title"?', style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              await FirebaseService.instance.deletePanicTool(doc.id);
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
              title: 'Panic Toolkit',
              subtitle:
                  'What-to-do, stay-calm and after-care guidance — shown live in the app.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                  onPressed: () => _openDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Card'),
                ),
              ],
            ),
            const SizedBox(height: defaultPadding),
            // Category filter
            Wrap(
              spacing: 8,
              children: [
                _chip('all', 'All'),
                for (final e in kPanicToolCategories.entries)
                  _chip(e.key, e.value),
              ],
            ),
            const SizedBox(height: defaultPadding),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getPanicToolsStream(),
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
                        'No cards yet. Tap "Add Card", or they seed automatically on first app launch.',
                        style: TextStyle(color: C.textMuted)),
                  );
                }
                return Column(
                  children: docs.map(_itemTile).toList(),
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

  Widget _itemTile(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final cat = d['category']?.toString() ?? '';
    final steps =
        (d['steps'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final color = Color((d['colorHex'] as num?)?.toInt() ?? 0xFFEF4444);
    final emoji = d['emoji']?.toString() ?? '';
    final iconName = d['iconName']?.toString() ?? '';
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
            child: emoji.isNotEmpty
                ? Text(emoji, style: const TextStyle(fontSize: 20))
                : Icon(iconFromName(iconName), color: color, size: 20),
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
                          kPanicToolCategories[cat] ?? cat,
                          style:
                              TextStyle(color: C.textMuted, fontSize: 10)),
                    ),
                  ],
                ),
                if ((d['description']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(d['description'].toString(),
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
