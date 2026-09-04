import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../models/chat_models.dart';

// ── Typing indicator (3 bouncing dots) ───────────────────────
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});
  @override State<TypingIndicator> createState() => _TypingIndicatorState();
}
class _TypingIndicatorState extends State<TypingIndicator> with TickerProviderStateMixin {
  late List<AnimationController> _cs;
  @override void initState() {
    super.initState();
    _cs = List.generate(3, (i) {
      final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
      Future.delayed(Duration(milliseconds: i * 160), () { if (mounted) c.repeat(reverse: true); });
      return c;
    });
  }
  @override void dispose() { for (final c in _cs) {
    c.dispose();
  } super.dispose(); }
  @override Widget build(BuildContext context) => RepaintBoundary(child: Row(mainAxisSize: MainAxisSize.min, children: [
    Text('SafeBot is typing', style: TextStyle(color: C.textMuted, fontSize: 11)),
    const SizedBox(width: 6),
    ...List.generate(3, (i) => AnimatedBuilder(
      animation: _cs[i],
      builder: (_, __) => Container(
        width: 6, height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: C.accent.withValues(alpha: .4 + _cs[i].value * .6),
        ),
      ),
    )),
  ]));
}

// ── Bot Avatar with pulse ─────────────────────────────────────
class BotAvatar extends StatefulWidget {
  const BotAvatar({super.key});
  @override State<BotAvatar> createState() => _BotAvatarState();
}
class _BotAvatarState extends State<BotAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => RepaintBoundary(child: AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: C.accent,
        boxShadow: [BoxShadow(color: C.accent.withValues(alpha: .2 + _c.value * .3), blurRadius: 8 + _c.value * 4)],
      ),
      child: const Center(
          child: Icon(Icons.health_and_safety_rounded,
              color: Colors.white, size: 18)),
    ),
  ));
}

// ── Message Bubble ─────────────────────────────────────────────
class MessageBubble extends StatefulWidget {
  final ChatMsg msg;
  final VoidCallback? onQuickReply;
  final Function(String)? onReply;
  const MessageBubble({super.key, required this.msg, this.onQuickReply, this.onReply});
  @override State<MessageBubble> createState() => _MessageBubbleState();
}
class _MessageBubbleState extends State<MessageBubble> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    final isUser = widget.msg.from == MsgFrom.user;
    _slide = Tween<Offset>(begin: Offset(isUser ? .3 : -.3, .1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(_c);
    _c.forward();
  }
  @override void dispose() { _c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final isUser = widget.msg.from == MsgFrom.user;
    return SlideTransition(position: _slide, child: FadeTransition(opacity: _fade, child:
      Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12), child:
        Column(crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [

          // Avatar + typing
          if (!isUser && widget.msg.type == MsgType.typing)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const BotAvatar(), const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: C.bg2, borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18))),
                child: const TypingIndicator()),
            ]),

          // Normal message
          if (widget.msg.type != MsgType.typing) ...[
            if (!isUser) Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const BotAvatar(), const SizedBox(width: 8),
              Flexible(child: _BubbleBody(msg: widget.msg, isUser: false)),
            ]) else _BubbleBody(msg: widget.msg, isUser: true),

            // Quick replies
            if (!isUser && widget.msg.quickReplies != null) ...[
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.only(left: 40), child:
                Wrap(spacing: 6, runSpacing: 6, children: widget.msg.quickReplies!.map((r) =>
                  GestureDetector(
                    onTap: () => widget.onReply?.call(r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: C.bg3,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: C.accent.withValues(alpha: .5))),
                      child: Text(r, style: TextStyle(color: C.accent, fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ).toList()),
              ),
            ],
          ],
        ]),
      ),
    ));
  }
}

class _BubbleBody extends StatelessWidget {
  final ChatMsg msg; final bool isUser;
  const _BubbleBody({required this.msg, required this.isUser});

  @override Widget build(BuildContext context) => Column(
    crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
    Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? C.accent : (msg.isEmergency ? C.accent.withValues(alpha: .12) : C.bg2),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        border: msg.isEmergency && !isUser ? Border.all(color: C.accent.withValues(alpha: .4)) : null,
      ),
      child: msg.text.isEmpty ? null : Text(msg.text,
        style: TextStyle(color: isUser ? C.textPrimary : C.textMuted, fontSize: 13, height: 1.5)),
    ),

    // Card inside message
    if (msg.card != null) ...[
      const SizedBox(height: 6),
      Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .72),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: msg.card!.color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: msg.card!.color.withValues(alpha: .35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(msg.card!.icon, color: msg.card!.color, size: 16),
            const SizedBox(width: 7),
            Expanded(child: Text(msg.card!.title,
              style: TextStyle(color: msg.card!.color, fontSize: 12, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 6),
          Text(msg.card!.body, style: TextStyle(color: C.textMuted, fontSize: 11, height: 1.5)),
          if (msg.card!.actionLabel != null) ...[
            const SizedBox(height: 8),
            GestureDetector(onTap: msg.card!.onAction,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: msg.card!.color, borderRadius: BorderRadius.circular(8)),
                child: Text(msg.card!.actionLabel!, style: TextStyle(color: C.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)))),
          ],
        ]),
      ),
    ],

    // Time
    const SizedBox(height: 3),
    Text(_fmt(msg.time), style: TextStyle(color: C.textMuted, fontSize: 9)),
  ]);

  String _fmt(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ── Animated FAB (floating chat button) ──────────────────────
class ChatFAB extends StatefulWidget {
  final VoidCallback onTap;
  final int unreadCount;
  const ChatFAB({super.key, required this.onTap, this.unreadCount = 0});
  @override State<ChatFAB> createState() => _ChatFABState();
}
class _ChatFABState extends State<ChatFAB> with SingleTickerProviderStateMixin {
  // Only ONE, one-time entrance bounce. The old version ran TWO forever-looping
  // animations (pulse + breathe) that repainted this always-on-screen button at
  // 60fps on every page — a real source of jank on low-end devices. It's now
  // static at rest, so it costs nothing once it has settled.
  late AnimationController _bounce;
  late Animation<double> _bounceAnim;

  @override void initState() {
    super.initState();
    _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _bounceAnim = Tween<double>(begin: 1, end: 1.12).animate(CurvedAnimation(parent: _bounce, curve: Curves.elasticOut));
    Future.delayed(const Duration(seconds: 2), () { if (mounted) _bounce.forward().then((_) => _bounce.reverse()); });
  }
  @override void dispose() { _bounce.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => RepaintBoundary(
    child: ScaleTransition(
      scale: _bounceAnim,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          // Static soft ring (no continuous animation).
          Container(width: 50, height: 50,
            decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(color: C.accent.withValues(alpha: 0.20), width: 2))),
          // Main button — SmartSafe shield mark on the SOS gradient.
          Container(width: 50, height: 50,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppTheme.sosGradient,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]),
            child: const Center(
                child: Icon(Icons.health_and_safety_rounded,
                    color: Colors.white, size: 26))),
          // Unread badge
          if (widget.unreadCount > 0) Positioned(top: -2, right: -2,
            child: Container(width: 18, height: 18,
              decoration: BoxDecoration(shape: BoxShape.circle, color: C.accent),
              child: Center(child: Text('${widget.unreadCount}',
                style: TextStyle(color: C.textPrimary, fontSize: 9, fontWeight: FontWeight.w700))))),
        ]),
      ),
    ),
  );
}
