import 'package:flutter/material.dart';
import '../theme/colors.dart';

class PulseRing extends StatefulWidget {
  final double size;
  final Color color;
  final Widget child;
  final int rings;

  const PulseRing({
    super.key,
    required this.size,
    required this.color,
    this.child = const SizedBox.shrink(),
    int? rings,
    int? ringCount,
  }) : rings = rings ?? ringCount ?? 2;

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _scales;
  late List<Animation<double>> _opacities;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.rings, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      );
      Future.delayed(Duration(milliseconds: i * 600), () {
        if (mounted) c.repeat();
      });
      return c;
    });

    _scales = _controllers
        .map((c) => Tween<double>(begin: 1.0, end: 1.8).animate(
              CurvedAnimation(parent: c, curve: Curves.easeOut),
            ))
        .toList();

    _opacities = _controllers
        .map((c) => Tween<double>(begin: 0.6, end: 0.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeOut),
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.8,
      height: widget.size * 1.8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(widget.rings, (i) {
            return AnimatedBuilder(
              animation: _controllers[i],
              builder: (_, __) => Transform.scale(
                scale: _scales[i].value,
                child: Opacity(
                  opacity: _opacities[i].value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.color.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          widget.child,
        ],
      ),
    );
  }
}

// ── Pulsing SOS button ───────────────────────────────────────
class PulseButton extends StatefulWidget {
  final VoidCallback onTap;
  const PulseButton({super.key, required this.onTap});

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.06)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: C.accent,
            boxShadow: [
              BoxShadow(color: C.accent.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 4),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('SOS',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: C.textPrimary,
                    letterSpacing: 2,
                  )),
              Text('TAP NOW',
                  style: TextStyle(
                    fontSize: 8,
                    color: C.textPrimary.withOpacity(0.7),
                    letterSpacing: 1,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Blinking dot ─────────────────────────────────────────────
class BlinkDot extends StatefulWidget {
  final Color color;
  final double size;
  const BlinkDot({super.key, required this.color, this.size = 8});

  @override
  State<BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<BlinkDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.2).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color dotColor = widget.color;
    if (dotColor == C.accent || dotColor == Colors.green || dotColor == C.success) {
      dotColor = C.success;
    } else if (dotColor == C.warning || dotColor == Colors.amber || dotColor == C.textMuted || dotColor == Colors.grey || dotColor == Colors.blue) {
      dotColor = C.textMuted;
    }
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
          ),
        ),
      ),
    );
  }
}

// ── Wave bars (GPS broadcasting) ─────────────────────────────
class WaveBars extends StatefulWidget {
  const WaveBars({super.key});

  @override
  State<WaveBars> createState() => _WaveBarsState();
}

class _WaveBarsState extends State<WaveBars> with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(5, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      );
      Future.delayed(Duration(milliseconds: i * 120), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(5, (i) {
        return AnimatedBuilder(
          animation: _ctrls[i],
          builder: (_, __) => Container(
            width: 4,
            height: 8 + _ctrls[i].value * 12,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ── Slide-up fade-in wrapper ─────────────────────────────────
class SlideUpFade extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const SlideUpFade({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<SlideUpFade> createState() => _SlideUpFadeState();
}

class _SlideUpFadeState extends State<SlideUpFade>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: child),
      ),
      child: widget.child,
    );
  }
}
