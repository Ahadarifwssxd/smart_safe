import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/models/app_structure.dart';
import 'package:smartsafe/models/women_safety_item.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

/// Admin CMS for the app's Women Safety page. Every section — warning signs,
/// prevention tips, self-defense moves, what-to-carry, worst-case steps and
/// quick helplines — is add/edit/delete-able here.
class WomenSafetyScreen extends StatefulWidget {
  const WomenSafetyScreen({super.key});

  @override
  State<WomenSafetyScreen> createState() => _WomenSafetyScreenState();
}

class _WomenSafetyScreenState extends State<WomenSafetyScreen> {
  String _filter = 'all'; // all | warning | prevention | ...

  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _itemsCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _sortCtrl = TextEditingController();
  String _cat = kWsWarning;
  String _iconName = kWomenSafetyIcons.first;
  int _colorHex = 0xFFEF4444;

  static const _palette = [
    0xFFEF4444, 0xFFF59E0B, 0xFF22C55E, 0xFF00B4D8, 0xFF9B5DE5, 0xFFFFB347,
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _itemsCtrl.dispose();
    _emojiCtrl.dispose();
    _numberCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  void _openDialog([DocumentSnapshot? existing]) {
    if (existing != null) {
      final d = existing.data() as Map<String, dynamic>;
      _cat = kWomenSafetyCategories.keys.contains(d['category']?.toString())
          ? d['category'].toString()
          : kWsWarning;
      _titleCtrl.text = d['title']?.toString() ?? '';
      _subtitleCtrl.text = d['subtitle']?.toString() ?? '';
      _itemsCtrl.text =
          ((d['items'] as List?)?.map((e) => e.toString()).toList() ?? [])
              .join('\n');
      _emojiCtrl.text = d['emoji']?.toString() ?? '';
      _numberCtrl.text = d['number']?.toString() ?? '';
      final icon = d['iconName']?.toString() ?? '';
      _iconName =
          kWomenSafetyIcons.contains(icon) ? icon : kWomenSafetyIcons.first;
      _colorHex = (d['colorHex'] as num?)?.toInt() ?? 0xFFEF4444;
      _sortCtrl.text = ((d['sortOrder'] as num?)?.toInt() ?? 0).toString();
    } else {
      _cat = _filter == 'all' ? kWsWarning : _filter;
      _titleCtrl.clear();
      _subtitleCtrl.clear();
      _itemsCtrl.clear();
      _emojiCtrl.clear();
      _numberCtrl.clear();
      _iconName = kWomenSafetyIcons.first;
      _colorHex = 0xFFEF4444;
      _sortCtrl.text = '0';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: C.bg2,
          title: Text(existing == null ? 'Add Item' : 'Edit Item',
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
                    items: kWomenSafetyCategories.entries
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
                    controller: _subtitleCtrl,
                    style: TextStyle(color: C.textPrimary),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Subtitle (tip / detail / action / step text)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _itemsCtrl,
                    style: TextStyle(color: C.textPrimary),
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Warning signs — ONE per line',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          dropdownColor: C.bg2,
                          initialValue: _iconName,
                          decoration: const InputDecoration(
                              labelText: 'Icon (prevention)'),
                          items: kWomenSafetyIcons
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
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _numberCtrl,
                          style: TextStyle(color: C.textPrimary),
                          decoration: const InputDecoration(
                              labelText: 'Number (helpline)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Wrap (not Row): order field + six swatches don't fit on one
                  // line inside a phone-width dialog.
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
                final items = _itemsCtrl.text
                    .split('\n')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final model = WomenSafetyItem(
                  category: _cat,
                  title: title,
                  subtitle: _subtitleCtrl.text.trim(),
                  items: items,
                  emoji: _emojiCtrl.text.trim(),
                  iconName: _iconName,
                  number: _numberCtrl.text.trim(),
                  colorHex: _colorHex,
                  sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 0,
                );
                try {
                  if (existing == null) {
                    await FirebaseService.instance.addWomenSafetyItem(model);
                  } else {
                    await FirebaseService.instance
                        .updateWomenSafetyItem(existing.id, model);
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
    final title = (doc.data() as Map<String, dynamic>)['title'] ?? 'this item';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Delete item', style: TextStyle(color: C.textPrimary)),
        content: Text('Delete "$title"?', style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              await FirebaseService.instance.deleteWomenSafetyItem(doc.id);
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
              title: 'Women Safety',
              subtitle:
                  'Warning signs, prevention, self-defense, helplines — shown live in the app.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                  onPressed: () => _openDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: defaultPadding),
            // Category filter
            Wrap(
              spacing: 8,
              children: [
                _chip('all', 'All'),
                for (final e in kWomenSafetyCategories.entries)
                  _chip(e.key, e.value),
              ],
            ),
            const SizedBox(height: defaultPadding),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getWomenSafetyStream(),
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
                        'No items yet. Tap "Add Item", or they seed automatically on first app launch.',
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
    final items =
        (d['items'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final color = Color((d['colorHex'] as num?)?.toInt() ?? 0xFFEF4444);
    final emoji = d['emoji']?.toString() ?? '';
    final iconName = d['iconName']?.toString() ?? '';
    final number = d['number']?.toString() ?? '';
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
                          kWomenSafetyCategories[cat] ?? cat,
                          style:
                              TextStyle(color: C.textMuted, fontSize: 10)),
                    ),
                  ],
                ),
                if ((d['subtitle']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(d['subtitle'].toString(),
                        style: TextStyle(color: C.textMuted, fontSize: 11)),
                  ),
                if (number.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call_rounded, color: color, size: 12),
                        const SizedBox(width: 4),
                        Text(number,
                            style: TextStyle(color: color, fontSize: 11)),
                      ],
                    ),
                  ),
                if (items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${items.length} sign(s)',
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
