import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'chatbot_screen.dart';
import 'widgets/chat_widgets.dart';

/// Wrap MainShell with this to show floating SafeBot on all pages
class ChatBotOverlay extends StatefulWidget {
  final Widget child;
  const ChatBotOverlay({super.key, required this.child});
  @override State<ChatBotOverlay> createState() => _ChatBotOverlayState();
}

class _ChatBotOverlayState extends State<ChatBotOverlay> with SingleTickerProviderStateMixin {
  bool _open = false;
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  // Draggable SafeBot button. Its position lives in a ValueNotifier so a drag
  // rebuilds ONLY the button — not the whole app underneath — which is what made
  // dragging feel slow/janky before.
  final ValueNotifier<Offset?> _fabPos = ValueNotifier<Offset?>(null);
  static const double _fabSize = 50;
  bool _dragging = false;
  // Raw-pointer drag state (Listener-based) for instant, iPhone-like movement.
  Offset _pointerDownAt = Offset.zero;
  Offset _dragStartFab = Offset.zero;

  // The FAB is built ONCE and reused, so dragging never rebuilds it (keeps its
  // own animation state and makes the drag cheaper = faster).
  late final Widget _fabChild = IgnorePointer(child: ChatFAB(onTap: () {}));

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override void dispose() { _ctrl.dispose(); _fabPos.dispose(); super.dispose(); }

  void _toggleChat() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
        onWillPop: () async {
          if (_open) {
            _toggleChat();
            return false;
          }
          return true;
        },
        child: Stack(children: [
          widget.child,

    // Dim overlay when chat open
    if (_open) GestureDetector(
      onTap: _toggleChat,
      child: FadeTransition(opacity: _fade,
        child: Container(color: Colors.black.withValues(alpha: .4)))),

    // Slide-up chat panel
    if (_open || _ctrl.isAnimating)
      SlideTransition(position: _slide, child: FadeTransition(opacity: _fade,
        child: Align(alignment: Alignment.bottomCenter,
          child: Container(
            height: MediaQuery.of(context).size.height * .88,
            decoration: BoxDecoration(color: C.bg,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .4), blurRadius: 24)]),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              child: Column(children: [
                // Handle bar
                Container(margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: C.textDim, borderRadius: BorderRadius.circular(2))),
                Expanded(child: ChatBotScreen(onBack: _toggleChat)),
              ]),
            ),
          )))),

    // Draggable floating SafeBot button — move it anywhere; it snaps to the
    // nearest side edge on release so it stays out of the way but reachable.
    _buildDraggableFab(context),
  ]),
);

  Widget _buildDraggableFab(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final pad = media.padding;
    // Keep the button inside the safe, visible area.
    final minX = 8.0;
    final maxX = size.width - _fabSize - 8;
    final minY = pad.top + 8;
    final maxY = size.height - _fabSize - pad.bottom - 8;

    // Only THIS builder rebuilds while dragging — the app underneath does not,
    // so the drag follows the finger instantly (no whole-screen rebuild = fast).
    return Positioned.fill(
      child: ValueListenableBuilder<Offset?>(
        valueListenable: _fabPos,
        builder: (context, value, _) {
          final pos = value ??
              Offset(maxX,
                  (size.height * 0.66 - _fabSize / 2).clamp(minY, maxY));
          final clamped = Offset(
            pos.dx.clamp(minX, maxX),
            pos.dy.clamp(minY, maxY),
          );
          return Stack(
            children: [
              // iPhone AssistiveTouch feel: instant 1:1 follow while dragging
              // (duration 0), then a fast smooth snap to the nearest side edge on
              // release (duration 260ms).
              AnimatedPositioned(
                // Zero duration while dragging = the button sits exactly under
                // the finger (1:1, no lag). On release, a quick 190ms snap.
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                left: clamped.dx,
                top: clamped.dy,
                child: AnimatedScale(
                  scale: _open ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  // Raw Listener (pointer events) — reacts from the VERY FIRST
                  // pixel with zero touch-slop and no gesture-arena delay, so it
                  // tracks the finger instantly like iPhone AssistiveTouch.
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      _dragging = true;
                      _pointerDownAt = e.position;
                      _dragStartFab = clamped;
                    },
                    onPointerMove: (e) {
                      if (!_dragging) return;
                      final dx = e.position.dx - _pointerDownAt.dx;
                      final dy = e.position.dy - _pointerDownAt.dy;
                      // Update the notifier only — no setState, no app rebuild.
                      _fabPos.value = Offset(
                        (_dragStartFab.dx + dx).clamp(minX, maxX),
                        (_dragStartFab.dy + dy).clamp(minY, maxY),
                      );
                    },
                    onPointerUp: (e) {
                      _dragging = false;
                      // Barely moved => treat as a tap and open the chat.
                      if ((e.position - _pointerDownAt).distance < 8) {
                        _toggleChat();
                        return;
                      }
                      // Free positioning: stay EXACTLY where dropped (anywhere
                      // on the whole screen) — no edge snapping. Just keep it
                      // clamped inside the visible area.
                      final current = _fabPos.value ?? clamped;
                      _fabPos.value = Offset(
                        current.dx.clamp(minX, maxX),
                        current.dy.clamp(minY, maxY),
                      );
                    },
                    onPointerCancel: (_) => _dragging = false,
                    child: _fabChild,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
