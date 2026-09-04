import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class SafetyScorePage extends StatelessWidget {
  const SafetyScorePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Safety Score', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        const SizedBox(height: 4),
        Text('Based on your habits & app usage', style: TextStyle(color: C.textMuted, fontSize: 12)),
        const SizedBox(height: 24),

        // Big score ring
        SlideUpFade(child: Center(child: Column(children: [
          SizedBox(width: 180, height: 180, child: Stack(alignment: Alignment.center, children: [
            const CustomPaint(painter: _ScoreRingPainter(score: 82), size: Size(180, 180)),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('82', style: TextStyle(color: C.textPrimary, fontSize: 52, fontWeight: FontWeight.w900)),
              Text('out of 100', style: TextStyle(color: C.textMuted, fontSize: 12)),
              const SizedBox(height: 4),
              StatusChip(label: 'VERY SAFE', color: C.success),
            ]),
          ])),
          const SizedBox(height: 12),
          Text('You\'re safer than 78% of SmartSafe users!', style: TextStyle(color: C.accent, fontSize: 13, fontWeight: FontWeight.w600)),
        ]))),

        const SizedBox(height: 24),

        // Score breakdown
        const SecHeader('Score breakdown'),
        _ScoreRow(label: 'Contacts added',        score: 100, max: 100, color: C.success,  detail: '4/5 contacts — great!'),
        const SizedBox(height: 8),
        _ScoreRow(label: 'Crash detection ON',    score: 100, max: 100, color: C.success,  detail: 'Always active'),
        const SizedBox(height: 8),
        _ScoreRow(label: 'SMS backup enabled',    score: 100, max: 100, color: C.success,  detail: 'Works offline'),
        const SizedBox(height: 8),
        _ScoreRow(label: 'Safe route used',       score: 60,  max: 100, color: C.warning,  detail: 'Use more often'),
        const SizedBox(height: 8),
        _ScoreRow(label: 'Night travel alerts',   score: 40,  max: 100, color: C.warning,  detail: 'Enable in settings'),
        const SizedBox(height: 8),
        _ScoreRow(label: 'Check-in habit',        score: 20,  max: 100, color: C.accent,    detail: 'Never used — try it!'),

        const SizedBox(height: 24),

        // Badges
        const SecHeader('🏅 Your badges'),
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.0,
          children: const [
            _Badge(emoji: '🛡️', label: 'Guardian',      unlocked: true),
            _Badge(emoji: '📍', label: 'GPS Pro',        unlocked: true),
            _Badge(emoji: '👥', label: 'Circle Builder', unlocked: true),
            _Badge(emoji: '🌙', label: 'Night Owl',      unlocked: false),
            _Badge(emoji: '🚗', label: 'Safe Driver',    unlocked: false),
            _Badge(emoji: '⭐', label: 'Perfect 100',    unlocked: false),
          ],
        ),

        const SizedBox(height: 24),

        // Tips to improve
        const SecHeader('📈 Improve your score'),
        _ImproveTip(icon: Icons.nightlight_round, color: C.warning,
          tip: 'Enable Night Travel Alerts', detail: '+10 points', onTap: () {}),
        const SizedBox(height: 8),
        _ImproveTip(icon: Icons.check_circle_rounded, color: C.accent,
          tip: 'Set up Safe Check-In', detail: '+15 points', onTap: () {}),
        const SizedBox(height: 8),
        _ImproveTip(icon: Icons.person_add_rounded, color: C.accent,
          tip: 'Add 5th trusted contact', detail: '+5 points', onTap: () {}),

        const SizedBox(height: 24),
      ]),
    )),
  );
}

class _ScoreRow extends StatelessWidget {
  final String label, detail;
  final int score, max;
  final Color color;
  const _ScoreRow({required this.label, required this.score, required this.max, required this.color, required this.detail});

  @override
  Widget build(BuildContext context) => DCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: C.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
      Text('$score/$max', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    ]),
    const SizedBox(height: 6),
    ClipRRect(borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(value: score / max, backgroundColor: C.border,
        valueColor: AlwaysStoppedAnimation(color), minHeight: 6)),
    const SizedBox(height: 4),
    Text(detail, style: TextStyle(color: C.textMuted, fontSize: 11)),
  ]));
}

class _Badge extends StatelessWidget {
  final String emoji, label;
  final bool unlocked;
  const _Badge({required this.emoji, required this.label, required this.unlocked});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: C.bg2, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: unlocked ? C.success.withOpacity(.4) : C.textDim)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(unlocked ? emoji : '🔒', style: const TextStyle(fontSize: 24)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: unlocked ? C.textPrimary : C.textMuted, fontSize: 10,
        fontWeight: unlocked ? FontWeight.w700 : FontWeight.normal), textAlign: TextAlign.center),
    ]));
}

class _ImproveTip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tip, detail;
  final VoidCallback onTap;
  const _ImproveTip({required this.icon, required this.color, required this.tip, required this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: DCard(child: Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(tip, style: TextStyle(color: C.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: C.success.withOpacity(.15), borderRadius: BorderRadius.circular(6)),
        child: Text(detail, style: TextStyle(color: C.success, fontSize: 11, fontWeight: FontWeight.w700))),
      const SizedBox(width: 8),
      Icon(Icons.arrow_forward_ios_rounded, color: C.textMuted, size: 14),
    ])));
}

class _ScoreRingPainter extends CustomPainter {
  final int score;
  const _ScoreRingPainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 12;
    final bg = Paint()..color = C.border..strokeWidth = 14..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final fg = Paint()..color = score > 70 ? C.success : score > 40 ? C.warning : C.accent
      ..strokeWidth = 14..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), -math.pi / 2, 2 * math.pi, false, bg);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), -math.pi / 2, 2 * math.pi * score / 100, false, fg);
  }

  @override
  bool shouldRepaint(_) => false;
}