import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../theme/design_tokens.dart';

// ── Pulse Ring ───────────────────────────────────────────────
class PulseRing extends StatefulWidget {
  final double size; final Color color; final Widget child; final int rings;
  const PulseRing({
    super.key,
    required this.size,
    required this.color,
    this.child = const SizedBox.shrink(),
    int? rings,
    int? ringCount,
  }) : rings = rings ?? ringCount ?? 2;
  @override State<PulseRing> createState() => _PulseRingState();
}
class _PulseRingState extends State<PulseRing> with TickerProviderStateMixin {
  late List<AnimationController> _cs;
  @override void initState() {
    super.initState();
    _cs = List.generate(widget.rings, (i) {
      final c = AnimationController(vsync:this, duration:const Duration(milliseconds:1800));
      Future.delayed(Duration(milliseconds:i*600), () { if(mounted) c.repeat(); });
      return c;
    });
  }
  @override void dispose() { for(final c in _cs) {
    c.dispose();
  } super.dispose(); }
  @override Widget build(BuildContext context) => RepaintBoundary(child: SizedBox(
    width:widget.size*1.85, height:widget.size*1.85,
    child:Stack(alignment:Alignment.center, children:[
      ...List.generate(widget.rings, (i) => AnimatedBuilder(animation:_cs[i],
        builder:(_,__)=>Transform.scale(
          scale:Tween<double>(begin:1.0,end:1.8).animate(CurvedAnimation(parent:_cs[i],curve:Curves.easeOut)).value,
          child:Opacity(opacity:Tween<double>(begin:.6,end:0).animate(CurvedAnimation(parent:_cs[i],curve:Curves.easeOut)).value,
            child:Container(width:widget.size,height:widget.size,
              decoration:BoxDecoration(shape:BoxShape.circle,
                border:Border.all(color:widget.color.withValues(alpha: .5),width:2))))))),
      widget.child,
    ])));
}

// ── Pulse SOS Button ─────────────────────────────────────────
class PulseSOSButton extends StatefulWidget {
  final VoidCallback onTap;
  final double size;
  const PulseSOSButton({super.key, required this.onTap, this.size = 140});
  @override State<PulseSOSButton> createState() => _PulseSOSButtonState();
}
class _PulseSOSButtonState extends State<PulseSOSButton> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { 
    super.initState(); 
    _c=AnimationController(vsync:this,duration:const Duration(milliseconds:1600))..repeat(reverse:true); 
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => RepaintBoundary(child: AnimatedBuilder(
    animation:_c,
    builder:(_,child)=>Transform.scale(
      scale:Tween<double>(begin:1.0,end:1.04).animate(CurvedAnimation(parent:_c,curve:Curves.easeInOutSine)).value,
      child:child
    ),
    child:GestureDetector(
      onTapDown: (_) => HapticFeedback.lightImpact(),
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child:Container(
        width:widget.size,
        height:widget.size,
        decoration:BoxDecoration(
          shape:BoxShape.circle,
          gradient:AppTheme.sosGradient,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.2),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.3),
              ],
              stops: const [0.0, 0.7, 1.0],
              center: Alignment.topLeft,
              radius: 1.2,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
          ),
          child: Column(
            mainAxisAlignment:MainAxisAlignment.center,
            children:[
              Text('SOS',style:DesignTokens.display.copyWith(fontSize:32,letterSpacing:1.5,color:Colors.white, fontWeight: FontWeight.w800, shadows: [const Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))])),
              Text('TAP NOW',style:DesignTokens.label.copyWith(fontSize:10,color:Colors.white.withValues(alpha:0.9),letterSpacing:1.5, fontWeight: FontWeight.w600)),
            ]
          ),
        ),
      ),
    ),
  ));
}

// ── Blink Dot ────────────────────────────────────────────────
class BlinkDot extends StatefulWidget {
  final Color? color; final double size;
  const BlinkDot({super.key, this.color, this.size=8});
  @override State<BlinkDot> createState() => _BlinkDotState();
}
class _BlinkDotState extends State<BlinkDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c=AnimationController(vsync:this,duration:const Duration(milliseconds:1200))..repeat(reverse:true); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    Color dotColor = widget.color ?? C.success;
    if (dotColor == C.accent || dotColor == Colors.green || dotColor == C.success) {
      dotColor = C.success;
    } else if (dotColor == C.warning || dotColor == Colors.amber || dotColor == C.textMuted || dotColor == Colors.grey || dotColor == Colors.blue) {
      dotColor = C.textMuted;
    }
    return RepaintBoundary(child: AnimatedBuilder(animation:_c,
      builder:(_,__)=>Opacity(opacity:Tween<double>(begin:1.0,end:.2).animate(_c).value,
        child:Container(width:widget.size,height:widget.size,decoration:BoxDecoration(shape:BoxShape.circle,color:dotColor)))));
  }
}

// ── Wave Bars ────────────────────────────────────────────────
class WaveBars extends StatefulWidget {
  final Color? color;
  final double height;
  const WaveBars({super.key, this.color, this.height = 12});
  @override State<WaveBars> createState() => _WaveBarsState();
}
class _WaveBarsState extends State<WaveBars> with TickerProviderStateMixin {
  late List<AnimationController> _cs;
  @override void initState() {
    super.initState();
    _cs = List.generate(5,(i){ final c=AnimationController(vsync:this,duration:const Duration(milliseconds:700)); Future.delayed(Duration(milliseconds:i*120),(){if(mounted)c.repeat(reverse:true);}); return c; });
  }
  @override void dispose() { for(final c in _cs) {
    c.dispose();
  } super.dispose(); }
  @override Widget build(BuildContext context) => RepaintBoundary(child: Row(
    mainAxisAlignment:MainAxisAlignment.center, crossAxisAlignment:CrossAxisAlignment.end,
    children:List.generate(5,(i)=>AnimatedBuilder(animation:_cs[i],
      builder:(_,__)=>Container(width:4,height:8+_cs[i].value*widget.height,margin:const EdgeInsets.symmetric(horizontal:2),
        decoration:BoxDecoration(color:widget.color ?? C.accent,borderRadius:BorderRadius.circular(2)))))));
}

// ── Slide Up Fade ─────────────────────────────────────────────
class SlideUpFade extends StatefulWidget {
  final Widget child; final Duration delay;
  const SlideUpFade({super.key, required this.child, this.delay=Duration.zero});
  @override State<SlideUpFade> createState() => _SlideUpFadeState();
}
class _SlideUpFadeState extends State<SlideUpFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    // Built ONCE (not on every build) and driven by the transitions directly —
    // no wrapping AnimatedBuilder — so this fires far fewer rebuilds per frame.
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero).animate(_fade);
    Future.delayed(widget.delay, () { if (mounted) _c.forward(); });
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

// ── Dark Card ────────────────────────────────────────────────
class DCard extends StatefulWidget {
  final Widget child; final Color? borderColor; final Color? color; final EdgeInsets? padding; final VoidCallback? onTap;
  const DCard({super.key, required this.child, this.borderColor, this.color, this.padding, this.onTap});
  @override State<DCard> createState() => _DCardState();
}

class _DCardState extends State<DCard> {
  bool _pressed = false;
  void _press(bool v) {
    if (widget.onTap != null && _pressed != v) setState(() => _pressed = v);
  }

  @override Widget build(BuildContext context) {
    final accent = widget.borderColor ?? C.border;
    final card = Container(
      padding: widget.padding ?? const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: accent.withValues(alpha: widget.borderColor != null ? 0.45 : 0.32),
        ),
        boxShadow: AppTheme.cardShadow(accent),
      ),
      child: widget.child,
    );
    if (widget.onTap == null) return card;
    // A subtle press-scale + a light haptic tick gives every tappable card the
    // same premium, tactile feedback (like iOS).
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        _press(true);
      },
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutBack,
        child: card,
      ),
    );
  }
}

// ── Premium empty state ──────────────────────────────────────
/// A polished "nothing here yet" placeholder — a soft haloed icon, a title, a
/// helpful line, and an optional call-to-action. Used across the app so every
/// empty screen feels intentional instead of blank.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Concentric soft halos behind the icon for a premium, crafted look.
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: C.accent.withValues(alpha: 0.06),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: C.accent.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: C.accent, size: 32),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: C.textMuted, fontSize: 13, height: 1.5),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section Header ───────────────────────────────────────────
class SecHeader extends StatelessWidget {
  final String text;
  final IconData? icon;
  const SecHeader(this.text, {super.key, this.icon});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: C.accent, size: 16),
          const SizedBox(width: 8),
        ] else ...[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: C.textMuted,
            fontSize: 10.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ── Toggle Row ────────────────────────────────────────────────
class TRow extends StatelessWidget {
  final String label; final bool value; final ValueChanged<bool> onChanged; final String? sub;
  const TRow({super.key, required this.label, required this.value, required this.onChanged, this.sub});
  @override Widget build(BuildContext context) => Padding(
    padding:const EdgeInsets.symmetric(vertical:8),
    child:Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w500)),
        if(sub!=null) Text(sub!,style:TextStyle(color:C.textMuted,fontSize:11)),
      ])),
      Switch(value:value,onChanged:onChanged),
    ]));
}

// ── Big Button ───────────────────────────────────────────────
class BigBtn extends StatefulWidget {
  final String label; final Color color; final VoidCallback onTap; final IconData? icon;
  const BigBtn({super.key, required this.label, required this.color, required this.onTap, this.icon});
  @override State<BigBtn> createState() => _BigBtnState();
}

class _BigBtnState extends State<BigBtn> {
  bool _pressed = false;
  void _set(bool v) { if (_pressed != v) setState(() => _pressed = v); }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        _set(true);
      },
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, Colors.black, 0.12)!],
            ),
            borderRadius: BorderRadius.circular(14.0),
            // Softer, more premium elevation (was a hard red glow).
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 18),
                const SizedBox(width: 12.0),
              ],
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Grid Painter ─────────────────────────────────────────────
class GridPainter extends CustomPainter {
  @override void paint(Canvas canvas,Size size){
    final p=Paint()..color=C.accent.withValues(alpha: .05)..strokeWidth=.5;
    for(double x=0;x<size.width;x+=28) {
      canvas.drawLine(Offset(x,0),Offset(x,size.height),p);
    }
    for(double y=0;y<size.height;y+=28) {
      canvas.drawLine(Offset(0,y),Offset(size.width,y),p);
    }
  }
  @override bool shouldRepaint(_)=>false;
}

// ── Status Chip ───────────────────────────────────────────────
class StatusChip extends StatelessWidget {
  final String label; final Color color;
  const StatusChip({super.key, required this.label, required this.color});
  @override Widget build(BuildContext context) => Container(
    padding:const EdgeInsets.symmetric(horizontal:9,vertical:4),
    decoration:BoxDecoration(
      color:color.withValues(alpha: .13),
      borderRadius:BorderRadius.circular(8),
      border:Border.all(color:color.withValues(alpha: .28)),
    ),
    // softWrap:false stops a squeezed chip from breaking its label one letter
    // per line ("F/a/m/i/l/y") — it ellipsises on a single line instead.
    child:Text(label,maxLines:1,softWrap:false,overflow:TextOverflow.ellipsis,
      style:TextStyle(color:color,fontSize:10,fontWeight:FontWeight.w700,letterSpacing:.2)));
}

// ── Emergency Number Button ───────────────────────────────────
class EmerBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const EmerBtn({super.key, required this.icon, required this.label, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap:onTap,
    child:Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:13),
      decoration:BoxDecoration(color:color.withValues(alpha: .1),borderRadius:BorderRadius.circular(12),
        border:Border.all(color:color.withValues(alpha: .4))),
      child:Row(children:[
        Icon(icon,color:color,size:20),const SizedBox(width:12),
        Text(label,style:TextStyle(color:color,fontSize:14,fontWeight:FontWeight.w700)),
        const Spacer(),Icon(Icons.call_rounded,color:color,size:18),
      ])));
}

// ── Ambient background (gradient orbs + dot grid) ─────────────
class DotGrid extends StatelessWidget {
  const DotGrid({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        // RepaintBoundary caches this static background as its own layer, so
        // content scrolling/animating on top never forces it to re-rasterize.
        child: RepaintBoundary(
          child: SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: AmbientGlowPainter()),
                CustomPaint(painter: DotGridPainter()),
              ],
            ),
          ),
        ),
      );
}

class AmbientGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void orb(Offset c, double r, Color color) {
      final rect = Rect.fromCircle(center: c, radius: r);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect);
      canvas.drawCircle(c, r, paint);
    }

    final orbAlpha = AppTheme.isDark ? 0.15 : 0.06;
    orb(Offset(size.width * 0.85, size.height * 0.08), size.width * 0.45, C.accent.withValues(alpha: orbAlpha));
    orb(Offset(size.width * 0.1, size.height * 0.22), size.width * 0.38, C.accent.withValues(alpha: orbAlpha * 0.5));
    orb(Offset(size.width * 0.7, size.height * 0.55), size.width * 0.32, C.accent.withValues(alpha: orbAlpha * 0.3));
    orb(Offset(size.width * 0.2, size.height * 0.88), size.width * 0.28, C.accent.withValues(alpha: orbAlpha * 0.2));

    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          C.bg.withValues(alpha: 0.2),
          C.bg,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
  }

  @override
  bool shouldRepaint(covariant AmbientGlowPainter old) => false;
}

class DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Subtle texture only near the top & bottom edges — the middle stays clean
    // so content never competes with a busy dotted background.
    final base = AppTheme.isDark ? 0.030 : 0.045;
    final p = Paint();
    for (double x = 24; x < size.width; x += 44) {
      for (double y = 24; y < size.height; y += 44) {
        // Vertical fade: 1 at the very top/bottom, 0 across the middle band.
        final t = (y / size.height); // 0..1
        final edge = (1 - (2 * t - 1).abs()); // 1 at center, 0 at edges
        final fade = (1 - edge).clamp(0.0, 1.0); // 0 center, 1 at edges
        final a = base * (fade * fade); // ease so the fade-out is gentle
        if (a < 0.004) continue;
        p.color = C.accent.withValues(alpha: a);
        canvas.drawCircle(Offset(x, y), 2.0, p);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Gradient brand title for headers.
class BrandTitle extends StatelessWidget {
  final String text;
  final double size;
  const BrandTitle(this.text, {super.key, this.size = 22});

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
        child: Text(
          text,
          style: AppTheme.displayFont.copyWith(
            fontSize: size,
            color: Colors.white,
          ),
        ),
      );
}

// ── Added compatibility widgets ──────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onActionTap;
  const SectionHeader({super.key, required this.title, this.action, this.onActionTap});
  @override
  Widget build(BuildContext context) {
    if (action != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SecHeader(title),
            GestureDetector(
              onTap: onActionTap,
              child: Text(
                action!,
                style: TextStyle(
                  color: C.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SecHeader(title);
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const StatusBadge({super.key, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => StatusChip(label: label, color: color);
}

class AvatarWidget extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;
  const AvatarWidget({super.key, required this.initials, required this.color, required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: C.accent.withValues(alpha: 0.12),
        border: Border.all(color: C.accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: C.accent,
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── SmartSafe Themed Loader (inline) ─────────────────────────
class SmartSafeLoader extends StatefulWidget {
  final double dotSize;
  final Color? color;
  const SmartSafeLoader({super.key, this.dotSize = 8, this.color});
  @override State<SmartSafeLoader> createState() => _SmartSafeLoaderState();
}
class _SmartSafeLoaderState extends State<SmartSafeLoader> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final col = widget.color ?? C.accent;
    return RepaintBoundary(child: AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final raw = (_c.value - i * 0.22).clamp(0.0, 1.0);
          final opacity = (math.sin(raw * math.pi)).clamp(0.15, 1.0);
          return Container(
            width: widget.dotSize,
            height: widget.dotSize,
            margin: EdgeInsets.symmetric(horizontal: widget.dotSize * 0.45),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: col.withValues(alpha: opacity.toDouble()),
            ),
          );
        }),
      ),
    ));
  }
}

// ── Full-screen Loading Page ──────────────────────────────────
class LoadingPage extends StatelessWidget {
  final String? message;
  const LoadingPage({super.key, this.message});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          const DotGrid(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.sosGradient,
                    boxShadow: AppTheme.glowShadow(C.accent),
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 28),
                const SmartSafeLoader(dotSize: 9),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    message!,
                    style: TextStyle(color: C.textMuted, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated Button (Squish Effect) ──────────────────────────
class AnimatedButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const AnimatedButton({super.key, required this.child, required this.onTap});

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: DesignTokens.durationFast,
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: _isPressed ? 0.85 : 1.0,
          duration: DesignTokens.durationFast,
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Glass Card (Glassmorphism) ──────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassCard({super.key, required this.child, this.padding, this.borderColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = borderColor ?? C.border;
    // Frosted look WITHOUT a real-time BackdropFilter blur — that blur re-samples
    // everything behind the card every frame and is a major jank source on
    // low-end phones. A near-opaque translucent fill looks all but identical and
    // is dramatically cheaper, so cards and lists that use it scroll smoothly.
    final card = Container(
      padding: padding ?? const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: C.bg2.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: accent.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: -4,
          )
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return AnimatedButton(onTap: onTap!, child: card);
    }
    return card;
  }
}

// ── Custom Empty State ─────────────────────────────────────────
class CustomEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? iconColor;

  const CustomEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final col = iconColor ?? C.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(DesignTokens.space24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: col.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 48, color: col),
            ),
            const SizedBox(height: DesignTokens.space24),
            Text(
              title,
              style: DesignTokens.h2.copyWith(color: C.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignTokens.space8),
            Text(
              subtitle,
              style: DesignTokens.body.copyWith(color: C.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
