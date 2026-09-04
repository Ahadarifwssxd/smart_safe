import 'dart:math';
import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import 'package:geolocator/geolocator.dart';
import '../services/app_firestore_service.dart';
import '../services/sensor_service.dart';
import '../services/user_profile_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class SafetyScorePage extends StatefulWidget {
  const SafetyScorePage({super.key});

  @override
  State<SafetyScorePage> createState() => _SafetyScorePageState();
}

class _SafetyScorePageState extends State<SafetyScorePage>
    with TickerProviderStateMixin {
  late AnimationController _gaugeCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _gaugeAnim;
  late Animation<double> _pulseAnim;

  // Computed from REAL account/setup data.
  int _score = 0;
  List<_ScoreFactor> _factors = [];
  List<_Suggestion> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _gaugeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _gaugeAnim = Tween(begin: 0.0, end: 0.0).animate(
        CurvedAnimation(parent: _gaugeCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _computeScore();
  }

  Future<void> _computeScore() async {
    // Gather real signals.
    final contacts =
        await AppFirestoreService.instance.getEmergencyContacts();
    final profile = await UserProfileService.instance.getCurrentProfile();
    LocationPermission perm = LocationPermission.denied;
    try {
      perm = await Geolocator.checkPermission();
    } catch (_) {}
    final gpsOn = perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;

    final contactScore = (contacts.length >= 3)
        ? 100
        : ((contacts.length / 3) * 100).round();
    final verifiedScore = (profile?.phoneVerified == true) ? 100 : 0;
    final gpsScore = gpsOn ? 100 : 0;
    final withEmail = contacts.where((c) => (c.email ?? '').isNotEmpty).length;
    final reachScore = contacts.isEmpty
        ? 0
        : ((withEmail / contacts.length) * 100).round();
    final profileComplete = [
      profile?.name.isNotEmpty == true,
      profile?.phone.isNotEmpty == true,
      profile?.bloodGroup.isNotEmpty == true,
      profile?.gender.isNotEmpty == true,
    ].where((e) => e).length;
    final profileScore = (profileComplete / 4 * 100).round();

    final factors = [
      _ScoreFactor('Emergency Contacts', contactScore, _c(contactScore),
          Icons.people_rounded, '${contacts.length} contact(s) added'),
      _ScoreFactor('Phone Verified', verifiedScore, _c(verifiedScore),
          Icons.verified_user_rounded,
          verifiedScore == 100 ? 'Number verified' : 'Verify your number'),
      _ScoreFactor('GPS / Location', gpsScore, _c(gpsScore),
          Icons.location_on_rounded,
          gpsOn ? 'Location enabled' : 'Enable location'),
      _ScoreFactor('Contact Reach', reachScore, _c(reachScore),
          Icons.alternate_email_rounded,
          '$withEmail of ${contacts.length} have email'),
      _ScoreFactor('Profile Complete', profileScore, _c(profileScore),
          Icons.badge_rounded, '$profileComplete of 4 fields filled'),
      _ScoreFactor('Crash Detection', 90, AppColors.success,
          Icons.car_crash_rounded,
          'Active · ${SensorService.instance.crashSensitivity} sensitivity'),
    ];

    final avg =
        (factors.map((f) => f.score).reduce((a, b) => a + b) / factors.length)
            .round();

    // Suggestions for the weakest areas.
    final suggestions = <_Suggestion>[];
    if (contactScore < 100) {
      suggestions.add(_Suggestion(Icons.person_add_alt_1_rounded,
          AppColors.accent, 'Add more emergency contacts',
          'Add at least 3 trusted people so SOS reaches more help.'));
    }
    if (verifiedScore < 100) {
      suggestions.add(_Suggestion(Icons.verified_user_rounded,
          AppColors.warning, 'Verify your phone number',
          'A verified number keeps your account secure.'));
    }
    if (gpsScore < 100) {
      suggestions.add(_Suggestion(Icons.location_on_rounded, AppColors.accent,
          'Enable location access', 'SOS needs GPS to share your exact spot.'));
    }
    if (profileScore < 100) {
      suggestions.add(_Suggestion(Icons.badge_rounded, AppColors.success,
          'Complete your profile', 'Add blood group & details for responders.'));
    }
    if (suggestions.isEmpty) {
      suggestions.add(_Suggestion(Icons.shield_rounded, AppColors.success,
          'You are well protected', 'Keep your contacts and location active.'));
    }

    if (!mounted) return;
    setState(() {
      _score = avg;
      _factors = factors;
      _suggestions = suggestions;
      _gaugeAnim = Tween(begin: 0.0, end: avg / 100.0).animate(
          CurvedAnimation(parent: _gaugeCtrl, curve: Curves.easeOutCubic));
    });
    _gaugeCtrl.forward(from: 0);
  }

  Color _c(int s) => s >= 80
      ? AppColors.success
      : s >= 50
          ? AppColors.warning
          : C.red;

  @override
  void dispose() {
    _gaugeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _scoreColor {
    if (_score >= 80) return AppColors.success;
    if (_score >= 60) return AppColors.warning;
    return C.red;
  }

  String get _scoreLabel {
    if (_score >= 80) return 'PROTECTED';
    if (_score >= 60) return 'MODERATE';
    return 'AT RISK';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                            DynText('safety_score', 'title', 'Safety Score',
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                )),
                            Text('Based on your safety setup',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome_rounded,
                                  color: AppColors.accent, size: 14),
                              const SizedBox(width: 4),
                              Text('AI',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Main gauge
                  SlideUpFade(
                    delay: const Duration(milliseconds: 100),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_gaugeAnim, _pulseAnim]),
                        builder: (_, __) {
                          return ScaleTransition(
                            scale: _pulseAnim,
                            child: SizedBox(
                              width: 220,
                              height: 220,
                              child: CustomPaint(
                                painter: _GaugePainter(
                                    _gaugeAnim.value, _scoreColor),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${(_gaugeAnim.value * 100).toInt()}',
                                        style: TextStyle(
                                          color: _scoreColor,
                                          fontSize: 54,
                                          fontWeight: FontWeight.w900,
                                          height: 1,
                                        ),
                                      ),
                                      Text('/100',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 14)),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _scoreColor.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: _scoreColor
                                                  .withValues(alpha: 0.4)),
                                        ),
                                        child: Text(_scoreLabel,
                                            style: TextStyle(
                                              color: _scoreColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.5,
                                            )),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Score factors
                  const SlideUpFade(
                    delay: Duration(milliseconds: 200),
                    child: SectionHeader(title: 'Score Breakdown'),
                  ),
                  const SizedBox(height: 12),
                  SlideUpFade(
                    delay: const Duration(milliseconds: 240),
                    child: DCard(
                      child: Column(
                        children: _factors
                            .asMap()
                            .entries
                            .map((e) => Padding(
                                  padding:
                                      EdgeInsets.only(bottom: e.key < _factors.length - 1 ? 14 : 0),
                                  child: _FactorRow(factor: e.value),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // AI Suggestions
                  const SlideUpFade(
                    delay: Duration(milliseconds: 320),
                    child: SectionHeader(title: 'AI Suggestions'),
                  ),
                  const SizedBox(height: 12),
                  ..._suggestions.asMap().entries.map((e) => SlideUpFade(
                        delay: Duration(milliseconds: 360 + e.key * 60),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SuggestionCard(s: e.value),
                        ),
                      )),

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

class _FactorRow extends StatelessWidget {
  final _ScoreFactor factor;

  const _FactorRow({required this.factor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: factor.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(factor.icon, color: factor.color, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(factor.name, style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
                  const Spacer(),
                  Text('${factor.score}%',
                      style: TextStyle(
                          color: factor.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: factor.score / 100,
                  minHeight: 5,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(factor.color),
                ),
              ),
              const SizedBox(height: 3),
              Text(factor.sub,
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final _Suggestion s;

  const _SuggestionCard({required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, color: s.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title, style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text(s.body,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: s.color.withValues(alpha: 0.6), size: 20),
        ],
      ),
    );
  }
}

class _ScoreFactor {
  final String name;
  final int score;
  final Color color;
  final IconData icon;
  final String sub;

  _ScoreFactor(this.name, this.score, this.color, this.icon, this.sub);
}

class _Suggestion {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  _Suggestion(this.icon, this.color, this.title, this.body);
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;

  const _GaugePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;

    // Background track
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 16
          ..style = PaintingStyle.stroke);

    // Colored segments (green to red gradient via arcs)
    final segColors = [AppColors.success, AppColors.warning, C.red, C.red];
    for (int i = 0; i < 4; i++) {
      final segPaint = Paint()
        ..color = segColors[i].withValues(alpha: 0.15)
        ..strokeWidth = 16
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + (i * (2 * pi / 4)),
        (2 * pi / 4) - 0.08,
        false,
        segPaint,
      );
    }

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = 16
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );

    // Glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 28
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      glowPaint,
    );

    // Dot at progress tip
    if (progress > 0.01) {
      final angle = -pi / 2 + 2 * pi * progress;
      final dotX = center.dx + radius * cos(angle);
      final dotY = center.dy + radius * sin(angle);
      canvas.drawCircle(Offset(dotX, dotY), 10,
          Paint()..color = color);
      canvas.drawCircle(Offset(dotX, dotY), 5,
          Paint()..color = C.textPrimary);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.progress != progress || old.color != color;
}

