import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

class SafetyTipsScreen extends StatefulWidget {
  const SafetyTipsScreen({super.key});

  @override
  State<SafetyTipsScreen> createState() => _SafetyTipsScreenState();
}

class _SafetyTipsScreenState extends State<SafetyTipsScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController(text: '💡');
  String _category = 'general'; // 'general' | 'women'

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  void _showTipDialog([DocumentSnapshot? existing]) {
    if (existing != null) {
      final d = existing.data() as Map<String, dynamic>;
      _titleCtrl.text = d['title']?.toString() ?? '';
      _bodyCtrl.text = d['body']?.toString() ?? '';
      _emojiCtrl.text = d['emoji']?.toString() ?? '💡';
      _category = d['category']?.toString() == 'women' ? 'women' : 'general';
    } else {
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _emojiCtrl.text = '💡';
      _category = 'general';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text(existing == null ? 'Add Safety Tip' : 'Edit Safety Tip', style: TextStyle(color: C.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _emojiCtrl,
                style: TextStyle(color: C.textPrimary, fontSize: 24),
                decoration: const InputDecoration(labelText: 'Emoji'),
              ),
              TextField(
                controller: _titleCtrl,
                style: TextStyle(color: C.textPrimary),
                decoration: const InputDecoration(labelText: 'Title *'),
              ),
              TextField(
                controller: _bodyCtrl,
                style: TextStyle(color: C.textPrimary),
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Body *'),
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, setInner) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Category:', style: TextStyle(color: C.textMuted)),
                    for (final c in const ['general', 'women'])
                      ChoiceChip(
                        label: Text(c == 'women' ? '👩 Women' : 'General'),
                        selected: _category == c,
                        onSelected: (_) => setInner(() => _category = c),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: C.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              final title = _titleCtrl.text.trim();
              final body = _bodyCtrl.text.trim();
              if (title.isEmpty || body.isEmpty) return;
              try {
                if (existing == null) {
                  await FirebaseService.instance.addSafetyTip(
                    title: title,
                    body: body,
                    emoji: _emojiCtrl.text.trim().isEmpty ? '💡' : _emojiCtrl.text.trim(),
                    colorHex: 0xFF00B4D8,
                    category: _category,
                  );
                } else {
                  await FirebaseService.instance.updateSafetyTip(
                    existing.id,
                    title: title,
                    body: body,
                    emoji: _emojiCtrl.text.trim().isEmpty ? '💡' : _emojiCtrl.text.trim(),
                    colorHex: (existing.data() as Map)['colorHex'] as int? ?? 0xFF00B4D8,
                    category: _category,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(defaultPadding),
            child: Header(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
            child: PageHeaderBar(
              icon: Icons.lightbulb_rounded,
              iconColor: C.warning,
              title: 'Safety Tips',
              subtitle: 'Yeh tips mobile app home screen par bhi dikhengi',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                  onPressed: () => _showTipDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getSafetyTipsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: C.accent));
                }
                final docs = List<DocumentSnapshot>.from(snapshot.data?.docs ?? [])
                  ..sort((a, b) {
                    final oa = (a.data() as Map?)?['sortOrder'] as int? ?? 0;
                    final ob = (b.data() as Map?)?['sortOrder'] as int? ?? 0;
                    return oa.compareTo(ob);
                  });
                if (docs.isEmpty) {
                  return Center(child: Text('No tips — tap Add', style: TextStyle(color: C.textMuted)));
                }
                return ListView.builder(
                  cacheExtent: 500,
                  padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data() as Map<String, dynamic>;
                    final color = Color(d['colorHex'] as int? ?? 0xFF00B4D8);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: secondaryColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Text(d['emoji']?.toString() ?? '💡', style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['title']?.toString() ?? '',
                                  style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  d['body']?.toString() ?? '',
                                  style: TextStyle(color: C.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit, color: C.accent, size: 20),
                            onPressed: () => _showTipDialog(doc),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: C.accent, size: 20),
                            onPressed: () => FirebaseService.instance.deleteSafetyTip(doc.id),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
