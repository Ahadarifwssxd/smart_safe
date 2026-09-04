import 'package:flutter/material.dart';

// ── Message types ─────────────────────────────────────────────
enum MsgFrom { user, bot }
enum MsgType { text, quickReplies, card, emergency, typing }

// ── Chat Message ─────────────────────────────────────────────
class ChatMsg {
  final String id;
  final String text;
  final MsgFrom from;
  final MsgType type;
  final DateTime time;
  final List<String>? quickReplies;
  final ChatCard? card;
  final bool isEmergency;

  ChatMsg({
    required this.id,
    required this.text,
    required this.from,
    this.type = MsgType.text,
    DateTime? time,
    this.quickReplies,
    this.card,
    this.isEmergency = false,
  }) : time = time ?? DateTime.now();

  factory ChatMsg.user(String text) => ChatMsg(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    text: text,
    from: MsgFrom.user,
  );

  factory ChatMsg.bot(String text, {List<String>? replies, ChatCard? card, bool emergency = false}) => ChatMsg(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    text: text,
    from: MsgFrom.bot,
    quickReplies: replies,
    card: card,
    isEmergency: emergency,
  );

  factory ChatMsg.typing() => ChatMsg(
    id: 'typing',
    text: '',
    from: MsgFrom.bot,
    type: MsgType.typing,
  );
}

// ── Info Card inside chat ─────────────────────────────────────
class ChatCard {
  final String title;
  final String body;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ChatCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.onAction,
  });
}

// ── Suggested questions ───────────────────────────────────────
final List<String> suggestedQuestions = [
  'How to trigger SOS?',
  'How does crash detection work?',
  'What is safe route?',
  'How to add contacts?',
  'Women safety tips',
  'First aid for bleeding',
  'Emergency numbers Pakistan',
  'How to use panic toolkit?',
];
