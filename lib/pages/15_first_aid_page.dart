import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../widgets/widgets.dart';
import '../widgets/safety_guides_view.dart';
import '../models/safety_guide.dart';
import '16_emergency_dial_page.dart';

class FirstAidPage extends StatelessWidget {
  const FirstAidPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: EdgeInsets.fromLTRB(responsiveHInset(context), 16, responsiveHInset(context), 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            if (Navigator.canPop(context)) ...[
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
              ),
              const SizedBox(width: 12),
            ],
            DynText('first_aid', 'title', 'First Aid Guide', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          ]),
          GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyDialPage())),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: C.accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(20),
                border: Border.all(color: C.accent.withValues(alpha: .4))),
              child: Row(children: [
                Icon(Icons.call_rounded, color: C.accent, size: 14),
                const SizedBox(width: 4),
                Text('1122', style: TextStyle(color: C.accent, fontSize: 12, fontWeight: FontWeight.w700)),
              ]))),
        ]),
        const SizedBox(height: 4),
        Text('Tap any condition for step-by-step guide', style: TextStyle(color: C.textMuted, fontSize: 12)),
        const SizedBox(height: 12),
        DCard(borderColor: C.accent, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: C.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Call 1122 FIRST for any serious emergency. First aid is temporary help only.',
              style: TextStyle(color: C.textMuted, fontSize: 11))),
          ])),
      ])),

      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(responsiveHInset(context), 0, responsiveHInset(context), 12),
        child: const SafetyGuidesView(category: kGuideFirstAid),
      )),
    ])),
  );
}
