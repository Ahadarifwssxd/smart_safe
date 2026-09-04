import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/models/onboarding_slide.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

/// Admin CMS for the app's first-run Onboarding walkthrough slides. Each slide
/// (big emoji, headline, supporting paragraph, accent colour) is add/edit/delete
/// -able here and shows live in the app's onboarding page.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  final _sortCtrl = TextEditingController();
  int _colorHex = 0xFFEF4444;

  static const _palette = [
    0xFFEF4444, 0xFFF59E0B, 0xFF22C55E, 0xFF00B4D8, 0xFF9B5DE5, 0xFF06D6A0,
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _emojiCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  void _openDialog([DocumentSnapshot? existing]) {
    if (existing != null) {
      final d = existing.data() as Map<String, dynamic>;
      _emojiCtrl.text = d['emoji']?.toString() ?? '';
      _titleCtrl.text = d['title']?.toString() ?? '';
      _subtitleCtrl.text = d['subtitle']?.toString() ?? '';
      _colorHex = (d['colorHex'] as num?)?.toInt() ?? 0xFFEF4444;
      _sortCtrl.text = ((d['sortOrder'] as num?)?.toInt() ?? 0).toString();
    } else {
      _emojiCtrl.clear();
      _titleCtrl.clear();
      _subtitleCtrl.clear();
      _colorHex = 0xFFEF4444;
      _sortCtrl.text = '0';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: C.bg2,
          title: Text(existing == null ? 'Add Slide' : 'Edit Slide',
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: _subtitleCtrl,
                    style: TextStyle(color: C.textPrimary),
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Subtitle (supporting paragraph)',
                      alignLabelWithHint: true,
                    ),
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
                final model = OnboardingSlide(
                  emoji: _emojiCtrl.text.trim(),
                  title: title,
                  subtitle: _subtitleCtrl.text.trim(),
                  colorHex: _colorHex,
                  sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 0,
                );
                try {
                  if (existing == null) {
                    await FirebaseService.instance.addOnboardingSlide(model);
                  } else {
                    await FirebaseService.instance
                        .updateOnboardingSlide(existing.id, model);
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
    final title = (doc.data() as Map<String, dynamic>)['title'] ?? 'this slide';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Delete slide', style: TextStyle(color: C.textPrimary)),
        content: Text('Delete "$title"?', style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              await FirebaseService.instance.deleteOnboardingSlide(doc.id);
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
              title: 'Onboarding',
              subtitle: 'First-run walkthrough slides — shown live in the app.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                  onPressed: () => _openDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Slide'),
                ),
              ],
            ),
            const SizedBox(height: defaultPadding),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getOnboardingStream(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snap.data!.docs.toList();
                docs.sort((a, b) {
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
                        'No slides yet. Tap "Add Slide", or they seed automatically on first app launch.',
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

  Widget _itemTile(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final color = Color((d['colorHex'] as num?)?.toInt() ?? 0xFFEF4444);
    final emoji = d['emoji']?.toString() ?? '';
    final order = (d['sortOrder'] as num?)?.toInt() ?? 0;
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
                : Icon(Icons.auto_stories_rounded, color: color, size: 20),
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
                      child: Text('#$order',
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
