import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/confirm_delete_dialog.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/models/app_structure.dart';
import 'package:smartsafe/services/app_structure_service.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

/// Admin: edit folders (sections), files (items), button text, labels — app + dashboard.
class AppStructureScreen extends StatefulWidget {
  const AppStructureScreen({super.key});

  @override
  State<AppStructureScreen> createState() => _AppStructureScreenState();
}

class _AppStructureScreenState extends State<AppStructureScreen> {
  String _filter = 'both';

  Future<void> _deleteSection(AppSection section) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete folder?',
      message: 'All files inside this folder will also be removed from the app and dashboard.',
      itemName: section.title,
      isFolder: true,
    );
    if (!ok || !mounted) return;
    await AppStructureService.instance.deleteSection(section.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: C.success,
          content: Text('Folder deleted', style: TextStyle(color: C.textPrimary)),
        ),
      );
    }
  }

  Future<void> _restoreMissing() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Restore defaults?', style: TextStyle(color: C.textPrimary)),
        content: Text(
          'Missing folders and buttons (e.g. Open Editor) will be added back. Your existing custom items stay unchanged.',
          style: TextStyle(color: C.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: C.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final report = await AppStructureService.instance.restoreMissingDefaults();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: C.success,
        content: Text(
          'Restored: +${report.sectionsAdded} folders, +${report.itemsAdded} items',
          style: TextStyle(color: C.textPrimary),
        ),
      ),
    );
  }

  Future<void> _deleteItem(AppSectionItem item) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete this item?',
      message: 'Are you sure you want to delete this? It will be removed from menus and folders.',
      itemName: item.label,
    );
    if (!ok || !mounted) return;
    await AppStructureService.instance.deleteItem(item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: C.success,
          content: Text('Item deleted', style: TextStyle(color: C.textPrimary)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Header(),
            const SizedBox(height: defaultPadding),
            PageHeaderBar(
              icon: Icons.folder_copy_rounded,
              title: 'Folders, Files & Buttons',
              subtitle:
                  'App drawer aur dashboard — har label, subtitle aur button text yahan likhein',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                  onPressed: () => _showSectionDialog(),
                  icon: const Icon(Icons.create_new_folder_rounded, size: 18),
                  label: const Text('New Folder'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _filterChip('both', 'All'),
                _filterChip('dashboard', 'Dashboard'),
                _filterChip('app', 'Mobile App'),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.accentLight,
                    side: BorderSide(color: C.accent.withValues(alpha: 0.5)),
                  ),
                  onPressed: _restoreMissing,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('Restore missing defaults'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Agar "Open Editor" ya koi folder delete ho gaya ho — Restore dabayein (purana data safe rehta hai)',
              style: TextStyle(color: C.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<AppSection>>(
              stream: AppStructureService.instance.watchSections(),
              builder: (context, secSnap) {
                final sections = (secSnap.data ?? [])
                    .where((s) => _filter == 'both' || s.context == _filter || s.context == 'both')
                    .toList();
                return StreamBuilder<List<AppSectionItem>>(
                  stream: AppStructureService.instance.watchItems(),
                  builder: (context, itemSnap) {
                    final allItems = itemSnap.data ?? [];
                    if (sections.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: ElevatedButton(
                            onPressed: () => AppStructureService.instance.seedDefaultStructure(),
                            child: const Text('Seed default app sections'),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: sections.map((section) {
                        final items = allItems
                            .where((i) =>
                                i.sectionId == section.id &&
                                (_filter == 'both' || i.context == _filter || i.context == 'both'))
                            .toList();
                        return _FolderCard(
                          section: section,
                          items: items,
                          onEditSection: () => _showSectionDialog(section),
                          onDeleteSection: () async => _deleteSection(section),
                          onAddItem: () => _showItemDialog(sectionId: section.id, context: section.context),
                          onEditItem: (item) => _showItemDialog(sectionId: section.id, existing: item, context: section.context),
                          onDeleteItem: (item) async => _deleteItem(item),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final sel = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: C.accent.withValues(alpha: 0.2),
      checkmarkColor: C.accent,
      labelStyle: TextStyle(color: sel ? C.textPrimary : C.textMuted),
    );
  }

  void _showSectionDialog([AppSection? existing]) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    var ctx = existing?.context ?? 'both';
    var order = existing?.sortOrder ?? 0;

    showDialog(
      context: context,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          backgroundColor: C.bg2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(existing == null ? 'New Folder (Section)' : 'Edit Folder', style: TextStyle(color: C.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: TextStyle(color: C.textPrimary),
                decoration: const InputDecoration(labelText: 'Folder title *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: ctx,
                dropdownColor: C.bg2,
                decoration: const InputDecoration(labelText: 'Show in'),
                items: const [
                  DropdownMenuItem(value: 'both', child: Text('App + Dashboard')),
                  DropdownMenuItem(value: 'dashboard', child: Text('Dashboard only')),
                  DropdownMenuItem(value: 'app', child: Text('App only')),
                ],
                onChanged: (v) => setD(() => ctx = v ?? 'both'),
              ),
              TextField(
                style: TextStyle(color: C.textPrimary),
                decoration: InputDecoration(labelText: 'Sort order ($order)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => order = int.tryParse(v) ?? 0,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx2), child: Text('Cancel', style: TextStyle(color: C.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: C.accent),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: C.accent, content: Text('Folder title is required', style: TextStyle(color: C.textPrimary))),
                  );
                  return;
                }
                final sec = AppSection(id: existing?.id ?? '', title: title, sortOrder: order, context: ctx);
                if (existing == null) {
                  await AppStructureService.instance.addSection(sec);
                } else {
                  await AppStructureService.instance.updateSection(existing.id, sec);
                }
                if (ctx2.mounted) Navigator.pop(ctx2);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _routesForContext(String itemCtx) {
    return <String>{
      if (itemCtx == 'dashboard' || itemCtx == 'both') ...dashboardRouteKeys,
      if (itemCtx == 'app' || itemCtx == 'both') ...appRouteKeys,
    }.toList()..sort();
  }

  String? _validRouteValue(String routeKey, List<String> routes) {
    if (routeKey.isEmpty) return null;
    return routes.contains(routeKey) ? routeKey : null;
  }

  void _showItemDialog({
    required String sectionId,
    AppSectionItem? existing,
    String context = 'both',
  }) {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final subCtrl = TextEditingController(text: existing?.subtitle ?? '');
    final btnCtrl = TextEditingController(text: existing?.buttonText ?? '');
    final dataSourceCtrl = TextEditingController(text: existing?.dataSource ?? '');
    var iconName = normalizeIconName(existing?.iconName);
    var routeKey = existing?.routeKey ?? '';
    var itemCtx = existing?.context ?? context;
    var dataSource = existing?.dataSource ?? '';
    var order = existing?.sortOrder ?? 0;

    showDialog(
      context: this.context,
      barrierDismissible: false,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setD) {
          final routeList = _routesForContext(itemCtx);
          final routeValue = _validRouteValue(routeKey, routeList);
          final iconItems = availableIconNames
              .map((n) => DropdownMenuItem(
                    value: n,
                    child: Row(
                      children: [
                        Icon(iconFromName(n), color: C.accent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(n, style: TextStyle(color: C.textPrimary, fontSize: 12))),
                      ],
                    ),
                  ))
              .toList();

          return AlertDialog(
            backgroundColor: C.bg2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(existing == null ? 'New File / Button' : 'Edit Item', style: TextStyle(color: C.textPrimary)),
            content: SizedBox(
              width: MediaQuery.of(ctx2).size.width < 460
                  ? MediaQuery.of(ctx2).size.width * 0.9
                  : 420.0,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelCtrl,
                      style: TextStyle(color: C.textPrimary),
                      decoration: const InputDecoration(labelText: 'Label (title) *'),
                    ),
                    TextField(
                      controller: subCtrl,
                      style: TextStyle(color: C.textPrimary),
                      decoration: const InputDecoration(labelText: 'Subtitle'),
                    ),
                    TextField(
                      controller: btnCtrl,
                      style: TextStyle(color: C.textPrimary),
                      decoration: const InputDecoration(labelText: 'Button text (e.g. Open, Save)'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('icon-$iconName'),
                      initialValue: iconName,
                      isExpanded: true,
                      dropdownColor: C.bg2,
                      decoration: const InputDecoration(labelText: 'Icon'),
                      items: iconItems,
                      onChanged: (v) => setD(() => iconName = normalizeIconName(v)),
                    ),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('route-$itemCtx-$routeValue'),
                      initialValue: routeValue,
                      isExpanded: true,
                      dropdownColor: C.bg2,
                      decoration: const InputDecoration(labelText: 'Screen route'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('— none —')),
                        ...routeList.map(
                          (k) => DropdownMenuItem<String?>(
                            value: k,
                            child: Text(k, style: TextStyle(color: C.textPrimary, fontSize: 12)),
                          ),
                        ),
                      ],
                      onChanged: (v) => setD(() => routeKey = v ?? ''),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: itemCtx,
                      dropdownColor: C.bg2,
                      decoration: const InputDecoration(labelText: 'Show in'),
                      items: const [
                        DropdownMenuItem(value: 'both', child: Text('Both')),
                        DropdownMenuItem(value: 'dashboard', child: Text('Dashboard')),
                        DropdownMenuItem(value: 'app', child: Text('App')),
                      ],
                      onChanged: (v) {
                        setD(() {
                          itemCtx = v ?? 'both';
                          final routes = _routesForContext(itemCtx);
                          if (routeKey.isNotEmpty && !routes.contains(routeKey)) {
                            routeKey = '';
                          }
                        });
                      },
                    ),
                    TextField(
                      controller: dataSourceCtrl,
                      style: TextStyle(color: C.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Data badge source',
                        hintText: 'alerts, sos_events, emergency_contacts…',
                      ),
                      onChanged: (v) => dataSource = v,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx2), child: Text('Cancel', style: TextStyle(color: C.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: C.accent),
                onPressed: () async {
                  final label = labelCtrl.text.trim();
                  if (label.isEmpty) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      SnackBar(backgroundColor: C.accent, content: Text('Label is required', style: TextStyle(color: C.textPrimary))),
                    );
                    return;
                  }
                  final item = AppSectionItem(
                    id: existing?.id ?? '',
                    sectionId: sectionId,
                    label: label,
                    subtitle: subCtrl.text.trim(),
                    buttonText: btnCtrl.text.trim(),
                    iconName: normalizeIconName(iconName),
                    routeKey: routeKey,
                    dataSource: dataSourceCtrl.text.trim(),
                    sortOrder: order,
                    context: itemCtx,
                  );
                  try {
                    if (existing == null) {
                      await AppStructureService.instance.addItem(item);
                    } else {
                      await AppStructureService.instance.updateItem(existing.id, item);
                    }
                    if (ctx2.mounted) {
                      Navigator.pop(ctx2);
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            backgroundColor: C.success,
                            content: Text(
                              existing == null ? 'Item added successfully' : 'Item updated',
                              style: TextStyle(color: C.textPrimary),
                            ),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (ctx2.mounted) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(backgroundColor: C.accent, content: Text(friendlyErrorMessage(e), style: TextStyle(color: C.textPrimary))),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final AppSection section;
  final List<AppSectionItem> items;
  final VoidCallback onEditSection;
  final Future<void> Function() onDeleteSection;
  final VoidCallback onAddItem;
  final void Function(AppSectionItem) onEditItem;
  final Future<void> Function(AppSectionItem) onDeleteItem;

  const _FolderCard({
    required this.section,
    required this.items,
    required this.onEditSection,
    required this.onDeleteSection,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + the folder actions. On phones the actions drop to their own
          // row so the folder name isn't crushed to a couple of characters.
          Builder(
            builder: (context) {
              final titleRow = Row(
                children: [
                  Icon(Icons.folder_rounded, color: C.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          section.title,
                          style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${section.context} · order ${section.sortOrder}',
                          style: TextStyle(color: C.textMuted, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final actions = [
                IconButton(icon: Icon(Icons.edit, color: C.accent, size: 20), onPressed: onEditSection),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: C.accent, size: 20),
                  tooltip: 'Delete folder',
                  onPressed: () async => await onDeleteSection(),
                ),
                TextButton.icon(
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add file'),
                ),
              ];

              if (Responsive.isMobile(context)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 4),
                    Wrap(alignment: WrapAlignment.end, children: actions),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: titleRow),
                  ...actions,
                ],
              );
            },
          ),
          const Divider(color: Colors.white12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('No files in this folder', style: TextStyle(color: C.textMuted)),
            )
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 8),
                        child: Icon(item.icon, color: item.color, size: 22),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.label, style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w600)),
                            Text(
                              [
                                if (item.subtitle.isNotEmpty) item.subtitle,
                                if (item.buttonText.isNotEmpty) 'Button: ${item.buttonText}',
                                if (item.routeKey.isNotEmpty) '→ ${item.routeKey}',
                              ].join(' · '),
                              style: TextStyle(color: C.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit, color: C.accent, size: 18),
                        onPressed: () => onEditItem(item),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: C.accent, size: 18),
                        tooltip: 'Delete item',
                        onPressed: () async => await onDeleteItem(item),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
