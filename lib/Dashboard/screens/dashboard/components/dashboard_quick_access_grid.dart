import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/controllers/menu_app_controller.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/models/app_structure.dart';
import 'package:smartsafe/services/app_structure_service.dart';
import 'package:smartsafe/theme/colors.dart';

/// All modules shown openly — grouped by folder, card grid (no accordion).
class DashboardQuickAccessGrid extends StatelessWidget {
  const DashboardQuickAccessGrid({super.key});

  static const _knownSources = {
    'emergency_contacts',
    'danger_zones',
    'incident_reports',
    'sos_events',
    'app_notifications',
    'safety_tips',
    'users',
  };

  Future<int> _countForSource(String source) async {
    if (source.isEmpty) return 0;
    try {
      final db = FirebaseFirestore.instance;
      // Server-side COUNT — reads only the total, not every document.
      if (source == 'alerts') {
        final agg = await db
            .collection('alerts')
            .where('status', isEqualTo: 'Active')
            .count()
            .get();
        return agg.count ?? 0;
      }
      if (_knownSources.contains(source)) {
        final agg = await db.collection(source).count().get();
        return agg.count ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppSection>>(
      stream: AppStructureService.instance.watchSections(contextFilter: 'dashboard'),
      builder: (context, secSnap) {
        final sections = secSnap.data ?? [];
        return StreamBuilder<List<AppSectionItem>>(
          stream: AppStructureService.instance.watchItems(contextFilter: 'dashboard'),
          builder: (context, itemSnap) {
            final allItems = itemSnap.data ?? [];
            if (sections.isEmpty) {
              return Text('No modules — use Edit Layout in sidebar', style: TextStyle(color: C.textMuted));
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Quick Access',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: C.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          context.read<MenuAppController>().setSelectedRoute('app_structure'),
                      icon: Icon(Icons.tune_rounded, color: C.accent, size: 18),
                      label: Text('Edit layout', style: TextStyle(color: C.accent)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...sections.map((section) {
                  final items = allItems.where((i) => i.sectionId == section.id).toList();
                  if (items.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.folder_rounded, color: C.warning, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                section.title,
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final crossCount = Responsive.isMobile(context)
                                ? 1
                                : Responsive.isTablet(context)
                                    ? 2
                                    : 3;
                            // Desktop/tablet keep the original 2.4 ratio. In the
                            // single-column mobile layout the ratio is derived
                            // from the real column width so a wide phone/
                            // foldable doesn't produce absurdly tall cards.
                            const spacing = 12.0;
                            final columnWidth = (constraints.maxWidth -
                                    (spacing * (crossCount - 1))) /
                                crossCount;
                            final double aspectRatio = crossCount > 1
                                ? 2.4
                                : (columnWidth / 96).clamp(2.2, 5.0).toDouble();
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossCount,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                                childAspectRatio: aspectRatio,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return _ModuleCard(
                                  item: item,
                                  countForSource: _countForSource,
                                  onOpen: () {
                                    if (item.routeKey.isNotEmpty) {
                                      context
                                          .read<MenuAppController>()
                                          .setSelectedRoute(item.routeKey);
                                    }
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final AppSectionItem item;
  final Future<int> Function(String) countForSource;
  final VoidCallback onOpen;

  const _ModuleCard({
    required this.item,
    required this.countForSource,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final btn = item.buttonText.isNotEmpty ? item.buttonText : 'Open';
    return Material(
      color: secondaryColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: item.color.withValues(alpha: 0.35)),
          ),
          child: FutureBuilder<int>(
            future: countForSource(item.dataSource),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: item.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.label,
                          style: TextStyle(
                            color: C.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            if (item.subtitle.isNotEmpty) item.subtitle,
                            if (count > 0) '$count records',
                          ].join(' · '),
                          style: TextStyle(color: C.textMuted, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Flexible + ellipsis: a long custom button label can never
                  // push the card into a horizontal overflow.
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        btn,
                        style: TextStyle(color: item.color, fontWeight: FontWeight.w700, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
