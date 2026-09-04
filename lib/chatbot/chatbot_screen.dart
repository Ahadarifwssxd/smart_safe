import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'models/chat_models.dart';
import 'services/ai_brain.dart';
import 'services/chatbot_faq_service.dart';
import 'widgets/chat_widgets.dart';

class ChatBotScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ChatBotScreen({super.key, this.onBack});
  @override
  State<ChatBotScreen> createState() => _ChatBotScreenState();
}

class _ChatBotScreenState extends State<ChatBotScreen>
    with TickerProviderStateMixin {
  final List<ChatMsg> _messages = [];
  final _inputCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _typing = false;
  bool _showSuggestions = true;
  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerCtrl.forward();
    // Welcome message
    Future.delayed(
        const Duration(milliseconds: 400),
        () => _addBotMsg(ChatMsg.bot(
              'Hi, I am SafeBot.\n\nAsk me any safety question. I am available 24/7 and can help in English or Urdu.',
              replies: [
                'How to use SOS?',
                'Emergency numbers',
                'Women safety tips',
                'First aid help'
              ],
            )));
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _inputCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _addBotMsg(ChatMsg msg) {
    if (!mounted) return;
    setState(() => _messages.add(msg));
    _scrollToBottom();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();
    // Snapshot the conversation BEFORE adding the new message, so the AI gets
    // the prior context as memory (respond() adds the new input itself).
    final history = List<ChatMsg>.from(_messages);
    setState(() {
      _messages.add(ChatMsg.user(text));
      _typing = true;
      _showSuggestions = false;
    });
    _scrollToBottom();

    final responses = await AIBrain.respond(text, history: history);
    if (!mounted) return;
    setState(() => _typing = false);

    for (int i = 0; i < responses.length; i++) {
      await Future.delayed(Duration(milliseconds: i * 300));
      _addBotMsg(responses[i]);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 100,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }


  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: _buildAppBar(),
        body: Column(children: [
          // Messages
          Expanded(
              child: ListView.builder(
            cacheExtent: 500,
            controller: _scroll,
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            itemCount: _messages.length +
                (_typing ? 1 : 0) +
                (_showSuggestions && _messages.isNotEmpty ? 1 : 0),
            itemBuilder: (_, i) {
              // Typing
              if (_typing && i == _messages.length) {
                return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const BotAvatar(),
                          const SizedBox(width: 8),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                  color: C.bg2,
                                  borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(18),
                                      topRight: Radius.circular(18),
                                      bottomRight: Radius.circular(18))),
                              child: const TypingIndicator()),
                        ]));
              }
              // Suggestions
              if (_showSuggestions && i == _messages.length) {
                return _SuggestionsRow(onTap: _send);
              }
              // Message
              return MessageBubble(msg: _messages[i], onReply: _send);
            },
          )),

          // Suggestions bar (before first message)
          if (_showSuggestions && _messages.isEmpty)
            _SuggestionsRow(onTap: _send),

          // Input
          _buildInput(),
        ]),
      );

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: C.bg2,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded, color: C.textPrimary, size: 18),
            onPressed: () {
              if (widget.onBack != null) {
                widget.onBack!();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            }),
        title: FadeTransition(
            opacity: _headerFade,
            child: Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.accent,
                      boxShadow: [
                        BoxShadow(color: C.accent.withValues(alpha: .4), blurRadius: 8)
                      ]),
                  child: const Center(
                      child: Icon(Icons.health_and_safety_rounded,
                          color: Colors.white, size: 20))),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SafeBot',
                    style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Row(children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: C.success)),
                  const SizedBox(width: 4),
                  Text('Online 24/7 — Safety AI',
                      style: TextStyle(color: C.textMuted, fontSize: 10)),
                ]),
              ]),
            ])),
        actions: [
          IconButton(
              icon:
                  Icon(Icons.delete_outline_rounded, color: C.textMuted, size: 20),
              onPressed: () => setState(() {
                    _messages.clear();
                    _showSuggestions = true;
                  })),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: C.textPrimary.withValues(alpha: .06))),
      );

  Widget _buildInput() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
            color: C.bg2,
            border: Border(top: BorderSide(color: C.textPrimary.withValues(alpha: .06)))),
        child: Row(children: [
          // Input field
          Expanded(
              child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
                color: C.bg3,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: C.textDim)),
            child: TextField(
              controller: _inputCtrl,
              style: TextStyle(color: C.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ask me anything about safety...',
                hintStyle: TextStyle(color: C.textMuted, fontSize: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
            ),
          )),
          const SizedBox(width: 8),
          // Send button
          GestureDetector(
            onTap: () => _send(_inputCtrl.text),
            child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: C.accent,
                    boxShadow: [
                      BoxShadow(
                          color: C.accent.withValues(alpha: 0.33), blurRadius: 8)
                    ]),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20)),
          ),
        ]),
      );
}

// ── Suggestions strip ─────────────────────────────────────────
class _SuggestionsRow extends StatelessWidget {
  final Function(String) onTap;
  const _SuggestionsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Prefer admin-managed (dashboard) suggestions; fall back to the built-ins.
    final adminQs = ChatbotFaqService.instance.suggestedQuestions;
    final questions = adminQs.isNotEmpty ? adminQs : suggestedQuestions;
    return Container(
        height: 44,
        margin: const EdgeInsets.only(bottom: 4),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: questions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => onTap(questions[i]),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: C.bg3,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: C.accent.withValues(alpha: .3))),
                child: Center(
                    child: Text(questions[i],
                        style: TextStyle(
                            color: C.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)))),
          ),
        ),
      );
  }
}
