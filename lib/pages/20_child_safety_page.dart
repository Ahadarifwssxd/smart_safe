import 'package:flutter/material.dart';
import '../navigation/dark_route.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../widgets/responsive.dart';
import '../widgets/safety_guides_view.dart';
import '../models/safety_guide.dart';
import '14_family_radar_page.dart';

class ChildSafetyPage extends StatelessWidget {
  const ChildSafetyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: ResponsiveCenter(child: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            if (Navigator.canPop(context)) ...[
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
              ),
              const SizedBox(width: 12),
            ],
            DynText('child_safety', 'title', 'Child Safety', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          ]),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: C.accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: C.accent.withValues(alpha: .4))),
            child: Text('PARENTS GUIDE', style: TextStyle(color: C.accent, fontSize: 10, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        Text('Teach your child, track their safety', style: TextStyle(color: C.textMuted, fontSize: 12)),
        const SizedBox(height: 24),

        // Live child tracking → opens the real Family Radar.
        SlideUpFade(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecHeader('Track Your Child Live', icon: Icons.my_location_rounded),
          GestureDetector(
            onTap: () => Navigator.push(context, darkRoute(const FamilyRadarPage())),
            child: DCard(borderColor: C.accent, child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: C.accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.radar_rounded, color: C.accent, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Open Family Radar', style: TextStyle(color: C.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                Text('See your child\'s live location & distance. Add them as an emergency contact (with SmartSafe installed) to track in real time.',
                  style: TextStyle(color: C.textMuted, fontSize: 11)),
              ])),
              Icon(Icons.chevron_right_rounded, color: C.textMuted, size: 22),
            ])),
          ),
        ])),

        const SizedBox(height: 24),

        const SafetyGuidesView(category: kGuideChild),

        const SizedBox(height: 24),
      ]),
    )),
  ));
}
