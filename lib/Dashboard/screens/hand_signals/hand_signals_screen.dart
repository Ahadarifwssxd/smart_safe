import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/models/hand_signal.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

/// Admin CMS for the Women Safety "Hand Signals for Help" section.
/// Everything shown there is add/edit/delete-able here.
class HandSignalsScreen extends StatefulWidget {
  const HandSignalsScreen({super.key});

  @override
  State<HandSignalsScreen> createState() => _HandSignalsScreenState();
}

class _HandSignalsScreenState extends State<HandSignalsScreen> {
  final _emojiCtrl = TextEditingController();
  final _titleEnCtrl = TextEditingController();
  final _titleUrCtrl = TextEditingController();
  final _descEnCtrl = TextEditingController();
  final _descUrCtrl = TextEditingController();
  final _speakEnCtrl = TextEditingController();
  final _speakUrCtrl = TextEditingController();
  final _sortCtrl = TextEditingController();
  String _motion = 'push';

  @override
  void dispose() {
    _emojiCtrl.dispose();
    _titleEnCtrl.dispose();
    _titleUrCtrl.dispose();
    _descEnCtrl.dispose();
    _descUrCtrl.dispose();
    _speakEnCtrl.dispose();
    _speakUrCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  void _openDialog([DocumentSnapshot? existing]) {
    if (existing != null) {
      final d = existing.data() as Map<String, dynamic>;
      _emojiCtrl.text = d['emoji']?.toString() ?? '✋';
      _titleEnCtrl.text = d['titleEn']?.toString() ?? '';
      _titleUrCtrl.text = d['titleUr']?.toString() ?? '';
      _descEnCtrl.text = d['descEn']?.toString() ?? '';
      _descUrCtrl.text = d['descUr']?.toString() ?? '';
      _speakEnCtrl.text = d['speakEn']?.toString() ?? '';
      _speakUrCtrl.text = d['speakUr']?.toString() ?? '';
      final motion = d['motion']?.toString() ?? 'push';
      _motion = kHandSignalMotions.contains(motion) ? motion : 'push';
      _sortCtrl.text = ((d['sortOrder'] as num?)?.toInt() ?? 0).toString();
    } else {
      _emojiCtrl.text = '✋';
      _titleEnCtrl.clear();
      _titleUrCtrl.clear();
      _descEnCtrl.clear();
      _descUrCtrl.clear();
      _speakEnCtrl.clear();
      _speakUrCtrl.clear();
      _motion = 'push';
      _sortCtrl.text = '0';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: C.bg2,
          title: Text(existing == null ? 'Add Hand Signal' : 'Edit Hand Signal',
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
                  Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: _emojiCtrl,
                          style: TextStyle(color: C.textPrimary, fontSize: 22),
                          decoration: const InputDecoration(labelText: 'Icon'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _titleEnCtrl,
                          style: TextStyle(color: C.textPrimary),
                          decoration: const InputDecoration(
                              labelText: 'Title (English) *'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _titleUrCtrl,
                    style: TextStyle(color: C.textPrimary),
                    decoration:
                        const InputDecoration(labelText: 'Title (Urdu)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descEnCtrl,
                    style: TextStyle(color: C.textPrimary),
                    decoration: const InputDecoration(
                        labelText: 'Description (English)'),
                  ),
                  TextField(
                    controller: _descUrCtrl,
                    style: TextStyle(color: C.textPrimary),
                    decoration:
                        const InputDecoration(labelText: 'Description (Urdu)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _speakEnCtrl,
                    style: TextStyle(color: C.textPrimary),
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Spoken line (English)',
                        alignLabelWithHint: true),
                  ),
                  TextField(
                    controller: _speakUrCtrl,
                    style: TextStyle(color: C.textPrimary),
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Spoken line (Urdu)',
                        alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          dropdownColor: C.bg2,
                          initialValue: _motion,
                          decoration:
                              const InputDecoration(labelText: 'Motion (demo)'),
                          items: kHandSignalMotions
                              .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m,
                                      style:
                                          TextStyle(color: C.textPrimary))))
                              .toList(),
                          onChanged: (v) =>
                              setInner(() => _motion = v ?? _motion),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                final titleEn = _titleEnCtrl.text.trim();
                if (titleEn.isEmpty) return;
                final signal = HandSignal(
                  emoji: _emojiCtrl.text.trim().isEmpty
                      ? '✋'
                      : _emojiCtrl.text.trim(),
                  titleEn: titleEn,
                  titleUr: _titleUrCtrl.text.trim(),
                  descEn: _descEnCtrl.text.trim(),
                  descUr: _descUrCtrl.text.trim(),
                  speakEn: _speakEnCtrl.text.trim(),
                  speakUr: _speakUrCtrl.text.trim(),
                  motion: _motion,
                  sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 0,
                );
                try {
                  if (existing == null) {
                    await FirebaseService.instance.addHandSignal(signal);
                  } else {
                    await FirebaseService.instance
                        .updateHandSignal(existing.id, signal);
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
    final title =
        (doc.data() as Map<String, dynamic>)['titleEn'] ?? 'this signal';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Delete signal', style: TextStyle(color: C.textPrimary)),
        content:
            Text('Delete "$title"?', style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              await FirebaseService.instance.deleteHandSignal(doc.id);
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
              title: 'Hand Signals',
              subtitle:
                  '"Hand Signals for Help" shown on the Women Safety page — with voice & demo.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                  onPressed: () => _openDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Signal'),
                ),
              ],
            ),
            const SizedBox(height: defaultPadding),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getHandSignalsStream(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snap.data!.docs.toList()
                  ..sort((a, b) {
                    final am = a.data() as Map<String, dynamic>;
                    final bm = b.data() as Map<String, dynamic>;
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
                        'No hand signals yet. Tap "Add Signal", or they seed automatically on first app launch.',
                        style: TextStyle(color: C.textMuted)),
                  );
                }
                return Column(
                  children: docs.map(_signalTile).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _signalTile(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
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
                color: C.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10)),
            child: Text(d['emoji']?.toString() ?? '✋',
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
                      child: Text(d['titleEn']?.toString() ?? '',
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
                      child: Text(d['motion']?.toString() ?? 'push',
                          style: TextStyle(color: C.textMuted, fontSize: 10)),
                    ),
                  ],
                ),
                if ((d['titleUr']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(d['titleUr'].toString(),
                        style: TextStyle(color: C.textMuted, fontSize: 12)),
                  ),
                if ((d['descEn']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(d['descEn'].toString(),
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
