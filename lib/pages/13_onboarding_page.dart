import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/models/onboarding_slide.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.onDone});
  @override State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _ctrl = PageController();
  int _page = 0;

  // Slides load live from Firestore; start with the built-in defaults so the
  // walkthrough is never blank while offline or before the first sync.
  List<OnboardingSlide> _slides = defaultOnboardingSlides;

  void _next() {
    if (_page < _slides.length - 1) {
      _ctrl.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: SafeArea(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.instance.getOnboardingStream(),
        builder: (context, snap) {
          if (snap.hasData && snap.data!.docs.isNotEmpty) {
            final loaded = snap.data!.docs
                .map((d) =>
                    OnboardingSlide.fromMap(d.data() as Map<String, dynamic>))
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
            _slides = loaded;
          } else {
            _slides = defaultOnboardingSlides;
          }
          // Keep the current page in range if the slide count shrank.
          if (_page > _slides.length - 1) _page = _slides.length - 1;
          return _buildBody();
        },
      ),
    ),
  );

  Widget _buildBody() => Column(children: [
      // Skip
      Align(alignment: Alignment.topRight,
        child: Padding(padding: const EdgeInsets.all(20),
          child: GestureDetector(onTap: widget.onDone,
            child: Text('Skip', style: TextStyle(color: C.textMuted, fontSize: 14))))),

      // Slides
      Expanded(child: PageView.builder(
        controller: _ctrl,
        onPageChanged: (i) => setState(() => _page = i),
        itemCount: _slides.length,
        itemBuilder: (_, i) {
          final s = _slides[i];
          final color = Color(s.colorHex);
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 120, height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: color.withValues(alpha: .15),
                  border: Border.all(color: color.withValues(alpha: .4), width: 2)),
                child: Center(child: Text(s.emoji, style: const TextStyle(fontSize: 52)))),
              const SizedBox(height: 32),
              Text(s.title, textAlign: TextAlign.center,
                style: TextStyle(color: C.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Text(s.subtitle, textAlign: TextAlign.center,
                style: TextStyle(color: C.textMuted, fontSize: 14, height: 1.6)),
            ]));
        },
      )),

      // Dots
      Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_slides.length, (i) =>
        AnimatedContainer(duration: const Duration(milliseconds: 250),
          width: _page == i ? 24 : 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _page == i ? C.accent : C.textDim,
            borderRadius: BorderRadius.circular(4))))),

      const SizedBox(height: 32),

      // Permissions
      if (_page == _slides.length - 1)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            _PermRow(icon: Icons.location_on_rounded, color: C.accent, label: 'Location access', sub: 'For GPS tracking and crash detection'),
            const SizedBox(height: 8),
            _PermRow(icon: Icons.message_rounded, color: C.warning, label: 'SMS permission', sub: 'To send alerts without internet'),
            const SizedBox(height: 8),
            _PermRow(icon: Icons.phone_rounded, color: C.accent, label: 'Phone access', sub: 'To auto-call 1122 on crash'),
            const SizedBox(height: 24),
          ])),

      // Next / Get started
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: BigBtn(
          label: _page == _slides.length - 1 ? 'Get Started' : 'Next',
          color: C.accent,
          onTap: _next)),
    ]);
}

class _PermRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, sub;
  const _PermRow({required this.icon, required this.color, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) => DCard(
    child: Row(children: [
      Container(width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: C.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(sub, style: TextStyle(color: C.textMuted, fontSize: 11)),
      ])),
      Icon(Icons.check_circle_rounded, color: C.success, size: 20),
    ]),
  );
}
