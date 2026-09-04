import 'dart:async';
import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class PanicBreathePage extends StatefulWidget {
  const PanicBreathePage({super.key});

  @override
  State<PanicBreathePage> createState() => _PanicBreathePageState();
}

class _PanicBreathePageState extends State<PanicBreathePage>
    with TickerProviderStateMixin {
  late AnimationController _breathCtrl;
  late AnimationController _bgCtrl;
  late Animation<double> _breathScale;
  late Animation<Color?> _bgColor;

  bool _isRunning = false;
  int _phase = 0; // 0=inhale 1=hold 2=exhale 3=hold
  int _count = 0;
  int _totalCycles = 0;
  Timer? _ticker;

  final List<_BreathPhase> _phases = [
    _BreathPhase('INHALE', 4, AppColors.accent),
    _BreathPhase('HOLD', 4, AppColors.accent),
    _BreathPhase('EXHALE', 6, AppColors.accent),
    _BreathPhase('HOLD', 2, AppColors.warning),
  ];

  // Pattern selector
  int _patternIndex = 0;
  final List<_BreathPattern> _patterns = [
    _BreathPattern('Box Breathing', [4, 4, 4, 4], AppColors.accent,
        'Military technique for calm focus'),
    _BreathPattern('4-7-8 Relaxing', [4, 7, 8, 0], AppColors.accent,
        'Induces sleep & calm quickly'),
    _BreathPattern('Panic Relief', [3, 3, 6, 0], AppColors.accent,
        'Activates parasympathetic system'),
  ];

  int _phaseRemaining = 4;
  int _phaseTotal = 4;

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4));
    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4));
    _breathScale = Tween(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));
    _bgColor = ColorTween(
            begin: AppColors.accent.withValues(alpha: 0.05),
            end: AppColors.accent.withValues(alpha: 0.15))
        .animate(_bgCtrl);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _breathCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  _BreathPattern get _currentPattern => _patterns[_patternIndex];

  void _startStop() {
    if (_isRunning) {
      _ticker?.cancel();
      _breathCtrl.stop();
      _bgCtrl.stop();
      setState(() {
        _isRunning = false;
        _phase = 0;
        _count = 0;
      });
    } else {
      setState(() {
        _isRunning = true;
        _phase = 0;
        _count = 0;
        _phaseRemaining = _currentPattern.durations[0];
        _phaseTotal = _currentPattern.durations[0];
      });
      _runPhase();
    }
  }

  void _runPhase() {
    final dur = _currentPattern.durations[_phase];
    if (dur == 0) {
      // Skip this phase
      setState(() {
        _phase = (_phase + 1) % 4;
        if (_phase == 0) _totalCycles++;
        _phaseRemaining = _currentPattern.durations[_phase];
        _phaseTotal = _currentPattern.durations[_phase];
      });
      _runPhase();
      return;
    }

    final isInhale = _phase == 0;
    final isExhale = _phase == 2;

    if (isInhale) {
      _breathCtrl.duration = Duration(seconds: dur);
      _breathCtrl.forward(from: 0);
      _bgCtrl.duration = Duration(seconds: dur);
      _bgCtrl.forward(from: 0);
    } else if (isExhale) {
      _breathCtrl.duration = Duration(seconds: dur);
      _breathCtrl.reverse();
      _bgCtrl.duration = Duration(seconds: dur);
      _bgCtrl.reverse();
    }

    setState(() {
      _phaseRemaining = dur;
      _phaseTotal = dur;
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _phaseRemaining--);
      if (_phaseRemaining <= 0) {
        t.cancel();
        if (_isRunning) {
          setState(() {
            _phase = (_phase + 1) % 4;
            if (_phase == 0) _totalCycles++;
          });
          _runPhase();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pattern = _currentPattern;
    final currentPhaseInfo = _phases[_phase];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Animated background
          if (_isRunning)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _bgColor,
                builder: (_, __) => Container(color: _bgColor.value),
              ),
            ),
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Header
                  SlideUpFade(
                    child: Row(
                      children: [
                        if (Navigator.canPop(context)) ...[
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DynText('panic_breathe', 'title', 'Panic Breathe',
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                )),
                            DynText('panic_breathe', 'subtitle',
                                'Breathe to calm your nervous system',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        if (_totalCycles > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('$_totalCycles cycles',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Pattern selector
                  if (!_isRunning)
                    SlideUpFade(
                      delay: const Duration(milliseconds: 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Choose Technique',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(height: 12),
                          ..._patterns.asMap().entries.map((e) {
                            final sel = e.key == _patternIndex;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _patternIndex = e.key),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? e.value.color.withValues(alpha: 0.1)
                                      : AppColors.bg2,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: sel
                                        ? e.value.color.withValues(alpha: 0.4)
                                        : AppColors.border,
                                    width: sel ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: e.value.color.withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          e.value.durations
                                              .where((d) => d > 0)
                                              .map((d) => '$d')
                                              .join('-'),
                                          style: TextStyle(
                                            color: e.value.color,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(e.value.name,
                                              style: TextStyle(
                                                color: sel
                                                    ? C.textPrimary
                                                    : AppColors.textMuted,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              )),
                                          Text(e.value.description,
                                              style: TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    if (sel)
                                      Icon(Icons.check_circle_rounded,
                                          color: e.value.color, size: 20),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),

                  // Breathing circle
                  SlideUpFade(
                    delay: const Duration(milliseconds: 160),
                    child: Center(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                        animation: _breathScale,
                        builder: (ctx, __) {
                          // Cap to a fraction of screen width so the ring never
                          // clips on small phones (was a fixed 260).
                          final side = (MediaQuery.of(ctx).size.width * 0.72)
                              .clamp(200.0, 260.0);
                          return SizedBox(
                            width: side,
                            height: side,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer glow rings
                                for (int r = 3; r >= 1; r--)
                                  Opacity(
                                    opacity: 0.06 * r,
                                    child: Transform.scale(
                                      scale: _breathScale.value +
                                          0.08 * r,
                                      child: Container(
                                        width: 180,
                                        height: 180,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: pattern.color,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Main circle
                                Transform.scale(
                                  scale: _breathScale.value,
                                  child: Container(
                                    width: 180,
                                    height: 180,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          pattern.color.withValues(alpha: 0.9),
                                          pattern.color.withValues(alpha: 0.5),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              pattern.color.withValues(alpha: 0.3),
                                          blurRadius: 40,
                                          spreadRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(_isRunning ? _phases[_phase].label : 'READY', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                        if (_isRunning) ...[
                                          const SizedBox(height: 6),
                                          Text('$_phaseRemaining', style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, height: 1)),
                                          const Text('seconds',
                                              style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11)),
                                        ] else
                                          const SizedBox(height: 8),
                                        if (!_isRunning)
                                          const Icon(
                                              Icons.air_rounded,
                                              color: Colors.white70,
                                              size: 28),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Phase indicator dots
                  if (_isRunning)
                    SlideUpFade(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (i) {
                          final dur = pattern.durations[i];
                          if (dur == 0) return const SizedBox();
                          return Container(
                            width: _phase == i ? 24 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: _phase == i
                                  ? pattern.color
                                  : AppColors.border,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    ),

                  const SizedBox(height: 28),

                  // Start/Stop button
                  SlideUpFade(
                    delay: const Duration(milliseconds: 220),
                    child: GestureDetector(
                      onTap: _startStop,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isRunning
                                ? [
                                    AppColors.accent.withValues(alpha: 0.8),
                                    AppColors.accent
                                  ]
                                : [pattern.color, pattern.color.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: (_isRunning ? AppColors.accent : pattern.color)
                                  .withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isRunning
                                    ? Icons.stop_rounded
                                    : Icons.air_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(_isRunning ? 'Stop Breathing' : 'Start Breathing', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tip card
                  SlideUpFade(
                    delay: const Duration(milliseconds: 280),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.bg3,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_outline_rounded,
                              color: AppColors.warning, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Focus on the circle expanding and contracting. This activates your vagus nerve and reduces cortisol.',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreathPhase {
  final String label;
  final int seconds;
  final Color color;

  _BreathPhase(this.label, this.seconds, this.color);
}

class _BreathPattern {
  final String name;
  final List<int> durations; // [inhale, hold, exhale, hold]
  final Color color;
  final String description;

  _BreathPattern(
      this.name, this.durations, this.color, this.description);
}
