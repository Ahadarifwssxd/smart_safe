import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/controllers/menu_app_controller.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/theme/colors.dart';

class DashboardKpiRow extends StatelessWidget {
  const DashboardKpiRow({super.key});

  Future<Map<String, int>> _loadCounts() async {
    final db = FirebaseFirestore.instance;
    try {
      // Server-side COUNT aggregation — reads only the totals, not every
      // document, so the dashboard loads instantly instead of downloading and
      // parsing whole collections. Runs all four in parallel.
      final results = await Future.wait([
        db
            .collection('alerts')
            .where('status', isEqualTo: 'Active')
            .count()
            .get(),
        db.collection('emergency_contacts').count().get(),
        db.collection('sos_events').count().get(),
        db.collection('users').count().get(),
        db.collection('users').where('plan', isEqualTo: 'premium').count().get(),
      ]);
      return {
        'alerts': results[0].count ?? 0,
        'contacts': results[1].count ?? 0,
        'sos': results[2].count ?? 0,
        'users': results[3].count ?? 0,
        'pro_users': results[4].count ?? 0,
      };
    } catch (_) {
      return {'alerts': 0, 'contacts': 0, 'sos': 0, 'users': 0, 'pro_users': 0};
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _loadCounts(),
      builder: (context, snap) {
        final c = snap.data ?? {};
        final cards = [
          _KpiCard(
            label: 'Active Alerts',
            value: '${c['alerts'] ?? 0}',
            icon: Icons.warning_amber_rounded,
            color: C.warning, // amber — alerts read as "attention"
            routeKey: 'alerts',
          ),
          _KpiCard(
            label: 'SOS Presses',
            value: '${c['sos'] ?? 0}',
            icon: Icons.sos_rounded,
            color: C.red, // emergency red (matches the app)
            routeKey: 'sos_activity',
          ),
          _KpiCard(
            label: 'PRO Members',
            value: '${c['pro_users'] ?? 0}',
            icon: Icons.workspace_premium_rounded,
            color: Colors.amber, // gold VIP
            routeKey: 'pro_subscribers',
          ),
          _KpiCard(
            label: 'Trusted Contacts',
            value: '${c['contacts'] ?? 0}',
            icon: Icons.contact_phone_rounded,
            color: C.accent, // brand indigo
            routeKey: 'emergency_contacts',
          ),
          _KpiCard(
            label: 'Total Users',
            value: '${c['users'] ?? 0}',
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF8B5CF6), // violet (brand family)
            routeKey: 'users',
          ),
        ];

        if (Responsive.isMobile(context)) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final singleColumn = constraints.maxWidth < 460;
              if (singleColumn) {
                return Column(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      cards[i],
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards.map((c) {
                  final cardWidth = (constraints.maxWidth - 12) / 2;
                  return SizedBox(width: cardWidth, child: c);
                }).toList(),
              );
            },
          );
        }

        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: defaultPadding),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String routeKey;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.routeKey,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: secondaryColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.read<MenuAppController>().setSelectedRoute(routeKey),
        child: Container(
          padding: const EdgeInsets.all(defaultPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            // A whisper of the card's accent colour bleeds in from the left for
            // subtle depth (premium), fading into the base card colour.
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                color.withValues(alpha: 0.10),
                secondaryColor.withValues(alpha: 0.0),
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.22)),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5, // tight numerals read as premium
                        height: 1.05,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        color: C.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios_rounded, color: C.textMuted, size: 13),
            ],
          ),
        ),
      ),
    );
  }
}
