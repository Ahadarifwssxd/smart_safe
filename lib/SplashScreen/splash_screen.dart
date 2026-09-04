import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

// ────────────────────────────────────────────────────────────────────
//  SmartSafe — Animated Splash Screen
//  Drop this file into your project and set SplashScreen() as the
//  initial route. It navigates to MainShell after the animation.
// ────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  /// Called when the splash is done — navigate to your home page here.
  final Widget nextScreen;
  final Future<void>? initFuture;

  const SplashScreen({super.key, required this.nextScreen, this.initFuture});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── controllers ──────────────────────────────────────────────────
  late AnimationController _pulseCtrl;   // outer pulse rings
  late AnimationController _logoCtrl;    // logo scale + fade in
  late AnimationController _textCtrl;    // text slide + fade
  late AnimationController _scanCtrl;    // radar scan line
  late AnimationController _exitCtrl;    // whole-screen exit fade

  // ── animations ───────────────────────────────────────────────────
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _taglineOpacity;
  late Animation<Offset> _taglineSlide;
  late Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    // 1. Pulse rings — run forever
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();

    // 2. Logo — pop in after 400ms
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _logoScale = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.0, 0.5, curve: Curves.easeIn)));

    // 3. Title text — slides up after logo
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _textOpacity = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _textSlide =
        Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));

    // 4. Tagline — slightly delayed from title
    _taglineOpacity = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _textCtrl,
            curve: const Interval(0.4, 1.0, curve: Curves.easeOut)));
    _taglineSlide =
        Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _textCtrl,
                curve:
                    const Interval(0.4, 1.0, curve: Curves.easeOut)));

    // 5. Radar scan
    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();

    // 6. Exit fade-out (kept at constant 1.0 opacity during active display)
    _exitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _exitOpacity = const AlwaysStoppedAnimation(1.0);

    _startSequence();
  }

  Future<void> _startSequence() async {
    // Total splash budget used to be ~3.1s+ (800ms of animation start delays
    // ran BEFORE the init await, then a 1800ms minimum hold on top, then a
    // 550ms transition). Now everything runs in parallel: the init future is
    // awaited from t=0 while the logo/text animations start on their own
    // timers, the minimum hold is a short 900ms, and the cross-fade is 350ms.
    final startTime = DateTime.now();

    // Animation start timers — fire-and-forget, they don't gate navigation.
    Future.delayed(const Duration(milliseconds: 300))
        .then((_) => _logoCtrl.forward());
    Future.delayed(const Duration(milliseconds: 700))
        .then((_) => _textCtrl.forward());

    // Await background service initialization (runs in parallel with the
    // animation timers above).
    if (widget.initFuture != null) {
      try {
        await widget.initFuture;
      } catch (e) {
        debugPrint('[SplashScreen] App initialization failed: $e');
      }
    }

    // Short minimum hold so the logo/tagline are actually seen, even when
    // init finishes instantly.
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    const minSplashDuration = 900;
    if (elapsed < minSplashDuration) {
      await Future.delayed(
          Duration(milliseconds: minSplashDuration - elapsed));
    }

    if (mounted) {
      // Freeze the forever-loops before the transition — otherwise the pulse
      // and radar painters keep ticking (and repainting) under the next
      // screen during the cross-fade.
      _pulseCtrl.stop();
      _scanCtrl.stop();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          // opaque: true because nextScreen (MainShell) fully replaces it
          opaque: true,
          pageBuilder: (_, __, ___) => widget.nextScreen,
          transitionsBuilder: (_, anim, __, child) => Stack(
            children: [
              // Permanent dark base layer so a frame drop under web never shows white
              Container(color: const Color(0xFF0A0F1E)),
              FadeTransition(
                opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                child: child,
              ),
            ],
          ),
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _scanCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _exitOpacity,
      builder: (_, child) => Opacity(opacity: _exitOpacity.value, child: child),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F1E),
        // Ensure the system nav/status bars also stay dark
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            // ── dot grid background ──────────────────────────────
            CustomPaint(
                painter: _DotGridPainter(), size: Size.infinite),

            // ── radar scan ──────────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: _scanCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _RadarScanPainter(_scanCtrl.value),
                  size: const Size(320, 320),
                ),
              ),
            ),

            // ── pulse rings ──────────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _PulseRingPainter(_pulseCtrl.value),
                  size: const Size(300, 300),
                ),
              ),
            ),

            // ── logo circle ──────────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: _logoCtrl,
                builder: (_, __) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: _LogoCircle(),
                  ),
                ),
              ),
            ),

            // ── text block (title + tagline) ─────────────────────
            Positioned(
              bottom: 140,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Title
                  FadeTransition(
                    opacity: _textOpacity,
                    child: SlideTransition(
                      position: _textSlide,
                      // Splash background is always dark, so use a fixed bright
                      // white→indigo gradient (not the themed colour, which is
                      // dark on the light theme and vanished here) + soft glow.
                      child: ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          colors: [Colors.white, Color(0xFFB9C2FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(r),
                        child: const Text(
                          'SmartSafe',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(color: Color(0x66818CF8), blurRadius: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tagline
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: SlideTransition(
                      position: _taglineSlide,
                      child: const Text(
                        'Because every second counts.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFAEB7D6),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── loading dots ─────────────────────────────────────
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _textOpacity,
                child: const _LoadingDots(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Logo Circle ───────────────────────────────────────────────────
class _LogoCircle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.sosGradient,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7A0C13).withValues(alpha: 0.55),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.health_and_safety_rounded,
                color: Colors.white, size: 40),
            SizedBox(height: 3),
            Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading Dots ──────────────────────────────────────────────────
class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
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
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final t = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
            final opacity = sin(t * pi).clamp(0.2, 1.0);
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: C.accent.withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Pulse Rings Painter ───────────────────────────────────────────
class _PulseRingPainter extends CustomPainter {
  final double progress;

  _PulseRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const ringCount = 4;
    for (int i = 0; i < ringCount; i++) {
      final p = ((progress - i / ringCount) % 1.0).clamp(0.0, 1.0);
      final radius = 60.0 + p * 90.0;
      final opacity = (1.0 - p) * 0.35;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = C.accent.withValues(alpha: opacity)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter old) =>
      old.progress != progress;
}

// ── Radar Scan Painter ────────────────────────────────────────────
class _RadarScanPainter extends CustomPainter {
  final double progress;

  _RadarScanPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final angle = progress * 2 * pi - pi / 2;

    // Radar circles
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(
        center,
        maxR * i / 3,
        Paint()
          ..color = const Color(0xFF2EC4B6).withValues(alpha: 0.06)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    // Sweep gradient
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle - pi / 2.5,
        endAngle: angle,
        colors: [
          Colors.transparent,
          const Color(0xFF2EC4B6).withValues(alpha: 0.18),
        ],
        transform: GradientRotation(angle - pi / 2 - pi / 2.5),
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR, sweepPaint);

    // Sweep line
    canvas.drawLine(
      center,
      Offset(center.dx + maxR * cos(angle), center.dy + maxR * sin(angle)),
      Paint()
        ..color = const Color(0xFF2EC4B6).withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarScanPainter old) =>
      old.progress != progress;
}

// ── Dot Grid Background ───────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = C.textPrimary.withValues(alpha: 0.025)
      ..strokeCap = StrokeCap.round;
    const spacing = 26.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
