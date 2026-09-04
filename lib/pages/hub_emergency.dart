import 'package:flutter/material.dart';
import '../navigation/dark_route.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

import '11_women_safety_page.dart';
import '28_enhanced_community_sos_page.dart';
import '13_evidence_page.dart';
import '15_emergency_will_page.dart';
import '16_emergency_dial_page.dart';
import '19_panic_toolkit_page.dart';

class EmergencyHubPage extends StatelessWidget {
  final VoidCallback? onSOSTap;
  const EmergencyHubPage({super.key, this.onSOSTap});

  @override
  Widget build(BuildContext context) {
    final tools = [
      {
        'icon': Icons.campaign_rounded,
        'title': 'Panic Toolkit',
        'desc': 'Instant access to high-decibel siren, strobe light, and quick-call triggers.',
        'color': C.accent,
        'page': PanicToolkitPage(onSOSTap: () => onSOSTap?.call()),
      },
      {
        'icon': Icons.groups_rounded,
        'title': 'Community SOS',
        'desc': 'Broadcast your live location to nearby users and community responders instantly.',
        'color': C.accent,
        'page': const EnhancedCommunitySosPage(),
      },
      {
        'icon': Icons.female_rounded,
        'title': 'Women Safety',
        'desc': 'Dedicated help modes, swift circle alerts, and direct local police channels.',
        'color': C.accent,
        'page': const WomenSafetyPage(),
      },
      {
        'icon': Icons.camera_alt_rounded,
        'title': 'Evidence Recorder',
        'desc': 'Discreetly record camera and microphone feeds saved securely to the cloud.',
        'color': C.accent,
        'page': const EvidencePage(),
      },
      {
        'icon': Icons.phone_forwarded_rounded,
        'title': 'Emergency Dial',
        'desc': 'Instant offline access to police, ambulance, fire, and custom helplines.',
        'color': C.accent,
        'page': const EmergencyDialPage(),
      },
      {
        'icon': Icons.gavel_rounded,
        'title': 'Emergency Will',
        'desc': 'Securely log your medical and legal statements to be shared in critical cases.',
        'color': C.warning,
        'page': const EmergencyWillPage(),
      },
    ];

    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          const DotGrid(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button & Title
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: C.bg2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: C.border),
                          ),
                          child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 16),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DynText(
                              'hub_emergency',
                              'title',
                              'Crisis Hub',
                              style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                            DynText(
                              'hub_emergency',
                              'subtitle',
                              'Emergency Response Control Center',
                              style: TextStyle(color: C.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Hub Status panel
                  SlideUpFade(
                    delay: const Duration(milliseconds: 50),
                    child: DCard(
                      borderColor: C.accent,
                      color: C.accent.withValues(alpha: 0.04),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: C.accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.security_rounded, color: C.accent, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('SILENT SOS ACTIVE', style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(width: 6),
                                    BlinkDot(color: C.red, size: 8),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Ready to broadcast location to 4 contacts',
                                  style: TextStyle(color: C.textMuted, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const SecHeader('Emergency & SOS Tools'),
                  const SizedBox(height: 8),

                  // List of sub-pages
                  ...List.generate(tools.length, (i) {
                    final tool = tools[i];
                    final color = tool['color'] as Color;
                    return SlideUpFade(
                      delay: Duration(milliseconds: 100 + i * 50),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DCard(
                          onTap: () => Navigator.push(
                            context,
                            darkRoute(tool['page'] as Widget),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: color.withValues(alpha: 0.2)),
                                ),
                                child: Icon(tool['icon'] as IconData, color: color, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tool['title'] as String,
                                      style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      tool['desc'] as String,
                                      style: TextStyle(color: C.textMuted, fontSize: 11.5, height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.arrow_forward_ios_rounded, color: C.textMuted.withValues(alpha: 0.5), size: 14),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
