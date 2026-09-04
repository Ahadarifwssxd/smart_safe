import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One admin-managed chatbot answer.
class ChatFaq {
  final String question; // shown as a suggested question chip
  final String answer; // the bot's reply
  final List<String> keywords; // lowercased triggers
  final int sortOrder;

  ChatFaq({
    required this.question,
    required this.answer,
    required this.keywords,
    this.sortOrder = 0,
  });

  factory ChatFaq.fromMap(Map<String, dynamic> m) => ChatFaq(
        question: m['question']?.toString() ?? '',
        answer: m['answer']?.toString() ?? '',
        keywords: (m['keywords'] as List?)
                ?.map((e) => e.toString().toLowerCase().trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const [],
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// Live cache of the admin-managed `chatbot_faq` collection so the chatbot can
/// answer from dashboard-edited Q&A (and show them as suggested questions)
/// without a network round-trip per message.
class ChatbotFaqService {
  static final ChatbotFaqService instance = ChatbotFaqService._();
  ChatbotFaqService._();

  List<ChatFaq> _faqs = [];
  StreamSubscription? _sub;

  List<ChatFaq> get faqs => _faqs;

  /// Questions to show as suggestion chips (admin-defined). Empty → caller
  /// falls back to the built-in list.
  List<String> get suggestedQuestions => _faqs
      .where((f) => f.question.trim().isNotEmpty)
      .map((f) => f.question.trim())
      .toList();

  void start() {
    if (_sub != null) return;
    _sub = FirebaseFirestore.instance
        .collection('chatbot_faq')
        .snapshots()
        .listen((snap) {
      _faqs = snap.docs
          .map((d) => d.data())
          .where((m) => m['active'] != false)
          .map(ChatFaq.fromMap)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }, onError: (e) => debugPrint('ChatbotFaqService error: $e'));
  }

  /// Returns the admin answer whose keywords best match [query], or null.
  String? match(String query) {
    final q = query.toLowerCase();
    for (final f in _faqs) {
      if (f.answer.trim().isEmpty) continue;
      if (f.keywords.any((k) => k.isNotEmpty && q.contains(k))) {
        return f.answer;
      }
    }
    return null;
  }
}
