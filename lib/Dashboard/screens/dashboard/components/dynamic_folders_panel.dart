import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/controllers/menu_app_controller.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/models/app_structure.dart';
import 'package:smartsafe/services/app_structure_service.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/user_app_shell.dart';

/// Folders = sections; files expand inside dropdown (ExpansionTile).
class DynamicFoldersPanel extends StatelessWidget {
  const DynamicFoldersPanel({super.key});

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

            if (sections.isEmpty && allItems.isEmpty) {
              return _emptyState(context);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Folders & Files',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: C.textPrimary),
                    ),
                    Row(
                      children: [
                        if (!Responsive.isDesktop(context))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const UserAppShell()),
                                );
                              },
                              icon: Icon(Icons.phone_android_rounded, color: C.accent, size: 18),
                              label: Text('App', style: TextStyle(color: C.accent)),
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
                  ],
                ),
                const SizedBox(height: defaultPadding),
                ...sections.map((section) {
                  final items = allItems.where((i) => i.sectionId == section.id).toList();
                  if (items.isEmpty) return const SizedBox.shrink();
                  return _FolderExpansion(
                    section: section,
                    items: items,
                    countForSource: _countForSource,
                    onOpen: (item) {
                      if (item.routeKey.isNotEmpty) {
                        context.read<MenuAppController>().setSelectedRoute(item.routeKey);
                      }
                    },
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Column(
      children: [
        Text('No folders yet', style: TextStyle(color: C.textMuted)),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => FirebaseService.instance.seedInitialDemoData(),
          child: const Text('Seed default layout'),
        ),
      ],
    );
  }
}

class _FolderExpansion extends StatefulWidget {
  final AppSection section;
  final List<AppSectionItem> items;
  final Future<int> Function(String) countForSource;
  final void Function(AppSectionItem) onOpen;

  const _FolderExpansion({
    required this.section,
    required this.items,
    required this.countForSource,
    required this.onOpen,
  });

  @override
  State<_FolderExpansion> createState() => _FolderExpansionState();
}

class _FolderExpansionState extends State<_FolderExpansion> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border.withValues(alpha: 0.35)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(Icons.folder_rounded, color: C.warning, size: 28),
          title: Text(
            widget.section.title,
            style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          subtitle: Text(
            '${widget.items.length} files — tap to expand',
            style: TextStyle(color: C.textMuted, fontSize: 12),
          ),
          iconColor: C.accent,
          collapsedIconColor: C.textMuted,
          children: widget.items.map((item) {
            return FutureBuilder<int>(
              future: widget.countForSource(item.dataSource),
              builder: (context, snap) {
                final count = snap.data ?? 0;
                final btn = item.buttonText.isNotEmpty ? item.buttonText : 'Open';
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, color: item.color, size: 20),
                  ),
                  title: Text(item.label, style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [
                      if (item.subtitle.isNotEmpty) item.subtitle,
                      if (count > 0) '$count records',
                    ].join(' · '),
                    style: TextStyle(color: C.textMuted, fontSize: 11),
                  ),
                  trailing: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: item.color.withValues(alpha: 0.15),
                      foregroundColor: item.color,
                    ),
                    onPressed: () => widget.onOpen(item),
                    child: Text(btn),
                  ),
                  onTap: () => widget.onOpen(item),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
