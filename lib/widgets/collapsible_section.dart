import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'widgets.dart';

/// A reusable collapsible section — keeps all content but tucks it behind a
/// tappable header so dense guide pages don't feel cluttered. Tap the header to
/// expand/collapse with a smooth animation.
class CollapsibleSection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool initiallyOpen;
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.children,
    this.initiallyOpen = false,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: SecHeader(widget.title)),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right_rounded,
                      color: C.textMuted, size: 22),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const SizedBox(height: 8), ...widget.children],
          ),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 240),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}
