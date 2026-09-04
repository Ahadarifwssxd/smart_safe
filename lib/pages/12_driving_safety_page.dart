import 'package:flutter/material.dart';
import '../navigation/dark_route.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../widgets/responsive.dart';
import '../widgets/safety_guides_view.dart';
import '../models/safety_guide.dart';
import '06_crash_detection_page.dart';

class DrivingSafetyPage extends StatelessWidget {
  const DrivingSafetyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: ResponsiveCenter(child: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            if(Navigator.canPop(context)) ...[
              GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18)),
              const SizedBox(width: 12),
            ],
            DynText('driving_safety', 'title', 'Driving Safety', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          ]),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: C.warning.withValues(alpha: .15), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: C.warning.withValues(alpha: .4))),
            child: Text('ROAD GUIDE', style: TextStyle(color: C.warning, fontSize: 10, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        Text('Prevent accidents before they happen', style: TextStyle(color: C.textMuted, fontSize: 12)),
        const SizedBox(height: 24),

        const SafetyGuidesView(category: kGuideDriving),

        const SizedBox(height: 24),

        // Crash detection — tap to configure the real crash detector.
        GestureDetector(
          onTap: () => Navigator.push(
              context, darkRoute(const CrashDetectionPage())),
          child: DCard(borderColor: C.warning, child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(shape: BoxShape.circle, color: C.warning.withValues(alpha: .2)),
              child: Icon(Icons.car_crash_rounded, color: C.warning, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SmartSafe Crash Detection', style: TextStyle(color: C.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              Text('Detects impact via accelerometer. Auto-calls 1122 + sends GPS to family in 15 seconds. Tap to set sensitivity.',
                style: TextStyle(color: C.textMuted, fontSize: 11)),
            ])),
            Icon(Icons.chevron_right_rounded, color: C.textMuted, size: 22),
          ])),
        ),

        const SizedBox(height: 24),
      ]),
    )),
  ));
}
