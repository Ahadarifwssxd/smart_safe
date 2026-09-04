import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

import '04_map_page.dart';
import '05_safe_route_page.dart';
import '16_danger_zone_page.dart';
import '21_safe_checkin_page.dart';

class TravelHubPage extends StatelessWidget {
  final VoidCallback? onSOSTap;
  const TravelHubPage({super.key, this.onSOSTap});

  @override
  Widget build(BuildContext context) {
    final tools = [
      {
        'icon': Icons.location_on_rounded,
        'title': 'Live GPS Tracking',
        'desc': 'Real-time positioning and background sharing with chosen circle members.',
        'color': C.accent,
        'page': const MapPage(),
      },
      {
        'icon': Icons.route_rounded,
        'title': 'Safe Route Planner',
        'desc': 'Determine safest path home with incident logs, police alerts and lit streets.',
        'color': C.success,
        'page': const SafeRoutePage(),
      },
      {
        'icon': Icons.local_fire_department_rounded,
        'title': 'Danger Zones',
        'desc': 'View live regional security heatmaps and high-incident crime databases.',
        'color': C.accent,
        'page': const DangerZonePage(),
      },
      {
        'icon': Icons.timer_rounded,
        'title': 'Safe Check-In',
        'desc': 'Set arrival timers. If you do not check-in on time, emergency contacts are alerted.',
        'color': C.accent,
        'page': SafeCheckInPage(onSOSTap: () => onSOSTap?.call()),
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
                              'hub_travel',
                              'title',
                              'Travel Hub',
                              style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                            DynText(
                              'hub_travel',
                              'subtitle',
                              'Secure Navigation & Route Guard',
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
                      borderColor: C.success,
                      color: C.success.withValues(alpha: 0.04),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: C.success.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.share_location_rounded, color: C.success, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('ROUTE WATCH ACTIVE', style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(width: 6),
                                    BlinkDot(color: C.success, size: 8),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'GPS broadcast is live and secure',
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

                  const SecHeader('Navigation & Transit Safety'),
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
                            MaterialPageRoute(builder: (_) => tool['page'] as Widget),
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
