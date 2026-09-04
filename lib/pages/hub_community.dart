import 'package:flutter/material.dart';
import '../navigation/dark_route.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

import '07_alert_history_page.dart';
import '28_enhanced_community_sos_page.dart';
import '11_safety_score_page.dart';
import '14_family_radar_page.dart';
import '17_safety_feed_page.dart';

class CommunityHubPage extends StatelessWidget {
  const CommunityHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = [
      {
        'icon': Icons.groups_rounded,
        'title': 'Community SOS',
        'desc':
            'Send an instant alert to the whole SmartSafe community so anyone can respond.',
        'color': C.accent,
        'page': const EnhancedCommunitySosPage(),
      },
      {
        'icon': Icons.shield_rounded,
        'title': 'Safety Score Analytics',
        'desc':
            'Interactive security posture assessments and risk recommendations.',
        'color': C.accent,
        'page': const SafetyScorePage(),
      },
      {
        'icon': Icons.radar_rounded,
        'title': 'Family Radar',
        'desc': 'Real-time family distance radar tracking and pinging system.',
        'color': C.accent,
        'page': const FamilyRadarPage(),
      },
      {
        'icon': Icons.history_rounded,
        'title': 'Alert History Logs',
        'desc':
            'Exhaustive history logs of all SOS triggers, crashes, and safe check-ins.',
        'color': C.accent,
        'page': const AlertHistoryPage(),
      },
      {
        'icon': Icons.rss_feed_rounded,
        'title': 'Live Safety Feed',
        'desc':
            'Local threat alerts, safety reports, and community warnings in real time.',
        'color': C.warning,
        'page': const SafetyFeedPage(),
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
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: C.textPrimary, size: 16),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DynText(
                              'hub_community',
                              'title',
                              'Insights & Community',
                              style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800),
                            ),
                            DynText(
                              'hub_community',
                              'subtitle',
                              'Safety Metrics, Circle Audits & Public Feeds',
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
                            child: Icon(Icons.hub_rounded,
                                color: C.accent, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('COMMUNITY SYNCED',
                                        style: TextStyle(
                                            color: C.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                    const SizedBox(width: 6),
                                    BlinkDot(
                                        color: C.accent, size: 8),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Linked with 3 local safety nodes',
                                  style:
                                      TextStyle(color: C.textMuted, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const SecHeader('Insights & Circle Tracking'),
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
                                  border:
                                      Border.all(color: color.withValues(alpha: 0.2)),
                                ),
                                child: Icon(tool['icon'] as IconData,
                                    color: color, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tool['title'] as String,
                                      style: TextStyle(
                                          color: C.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      tool['desc'] as String,
                                      style: TextStyle(
                                          color: C.textMuted,
                                          fontSize: 11.5,
                                          height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.arrow_forward_ios_rounded,
                                  color: C.textMuted.withValues(alpha: 0.5), size: 14),
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
