import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

/// Admin editor for the chatbot's answers. Docs live in `chatbot_faq`:
/// { question, answer, keywords: [..], sortOrder, active }. The app checks
/// these first (before the AI) and shows the questions as suggestion chips.
class ChatbotFaqScreen extends StatefulWidget {
  const ChatbotFaqScreen({super.key});

  @override
  State<ChatbotFaqScreen> createState() => _ChatbotFaqScreenState();
}

class _ChatbotFaqScreenState extends State<ChatbotFaqScreen> {
  final _questionCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();

  @override
  void dispose() {
    _questionCtrl.dispose();
    _answerCtrl.dispose();
    _keywordsCtrl.dispose();
    super.dispose();
  }

  CollectionReference get _col =>
      FirebaseFirestore.instance.collection('chatbot_faq');

  void _showDialog([DocumentSnapshot? existing]) {
    if (existing != null) {
      final d = existing.data() as Map<String, dynamic>;
      _questionCtrl.text = d['question']?.toString() ?? '';
      _answerCtrl.text = d['answer']?.toString() ?? '';
      _keywordsCtrl.text =
          (d['keywords'] as List?)?.map((e) => e.toString()).join(', ') ?? '';
    } else {
      _questionCtrl.clear();
      _answerCtrl.clear();
      _keywordsCtrl.clear();
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text(existing == null ? 'Add Chatbot Q&A' : 'Edit Chatbot Q&A',
            style: TextStyle(color: C.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _questionCtrl,
                style: TextStyle(color: C.textPrimary),
                decoration: const InputDecoration(
                    labelText: 'Question (also shown as a suggestion) *'),
              ),
              TextField(
                controller: _answerCtrl,
                style: TextStyle(color: C.textPrimary),
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Answer *'),
              ),
              TextField(
                controller: _keywordsCtrl,
                style: TextStyle(color: C.textPrimary),
                decoration: const InputDecoration(
                    labelText: 'Trigger keywords (comma separated)',
                    hintText: 'e.g. refund, cancel, price'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: C.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              final question = _questionCtrl.text.trim();
              final answer = _answerCtrl.text.trim();
              if (question.isEmpty || answer.isEmpty) return;
              final keywords = _keywordsCtrl.text
                  .split(',')
                  .map((e) => e.trim().toLowerCase())
                  .where((e) => e.isNotEmpty)
                  .toList();
              // If no keywords given, use words from the question so it still
              // matches when a user asks something similar.
              final finalKeywords = keywords.isNotEmpty
                  ? keywords
                  : question
                      .toLowerCase()
                      .split(RegExp(r'\s+'))
                      .where((w) => w.length > 3)
                      .toList();
              try {
                final data = {
                  'question': question,
                  'answer': answer,
                  'keywords': finalKeywords,
                  'active': true,
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                if (existing == null) {
                  await _col.add({
                    ...data,
                    'sortOrder': 0,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } else {
                  await _col.doc(existing.id).update(data);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(friendlyErrorMessage(e))));
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
              icon: Icons.smart_toy_rounded,
              title: 'Chatbot Q&A',
              subtitle:
                  'SafeBot answers these first (before the AI). Questions also show '
                  'as suggestion chips in the app.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                  onPressed: () => _showDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _col.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(color: C.accent));
                }
                final docs =
                    List<DocumentSnapshot>.from(snapshot.data?.docs ?? []);
                if (docs.isEmpty) {
                  return Center(
                      child: Text('No custom answers yet — tap Add',
                          style: TextStyle(color: C.textMuted)));
                }
                return ListView.builder(
                  cacheExtent: 500,
                  padding: const EdgeInsets.symmetric(
                      horizontal: defaultPadding),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data() as Map<String, dynamic>;
                    final keywords =
                        (d['keywords'] as List?)?.join(', ') ?? '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: secondaryColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d['question']?.toString() ?? '',
                                    style: TextStyle(
                                        color: C.textPrimary,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(d['answer']?.toString() ?? '',
                                    style: TextStyle(
                                        color: C.textMuted, fontSize: 12)),
                                if (keywords.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.vpn_key_rounded,
                                          color: C.accent, size: 12),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(keywords,
                                            style: TextStyle(
                                                color: C.accent, fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit, color: C.accent, size: 20),
                            onPressed: () => _showDialog(doc),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: C.accent, size: 20),
                            onPressed: () => _col.doc(doc.id).delete(),
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
