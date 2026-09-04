import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartsafe/Dashboard/controllers/menu_app_controller.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/models/app_structure.dart';
import 'package:smartsafe/services/app_structure_service.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/user_app_shell.dart';

/// Sidebar: folder-wise navigation (permanent on desktop/tablet, drawer on mobile).
class SideMenu extends StatelessWidget {
  final bool permanent;

  const SideMenu({super.key, this.permanent = false});

  @override
  Widget build(BuildContext context) {
    final body = _SideMenuBody(permanent: permanent);
    if (permanent) {
      return Container(
        width: 280,
        decoration: BoxDecoration(
          color: C.bg2,
          border: Border(right: BorderSide(color: C.border.withValues(alpha: 0.25))),
        ),
        child: body,
      );
    }
    return Drawer(
      backgroundColor: C.bg2,
      width: 280,
      child: body,
    );
  }
}

class _SideMenuBody extends StatelessWidget {
  final bool permanent;

  const _SideMenuBody({required this.permanent});

  @override
  Widget build(BuildContext context) {
    final menuController = Provider.of<MenuAppController>(context);
    final selectedRoute = menuController.selectedRouteKey;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: C.border.withValues(alpha: 0.2))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_rounded, color: C.accent, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SmartSafe',
                          style: TextStyle(
                            color: C.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text('Admin Panel', style: TextStyle(color: C.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        DrawerListTile(
          title: 'Dashboard',
          icon: Icons.dashboard_rounded,
          isSelected: selectedRoute == 'dashboard',
          press: () => _open(context, menuController, 'dashboard'),
        ),
        DrawerListTile(
          title: 'PRO Subscriptions',
          icon: Icons.workspace_premium_rounded,
          isSelected: selectedRoute == 'pro_subscribers',
          press: () => _open(context, menuController, 'pro_subscribers'),
        ),
        DrawerListTile(
          title: 'Open User App',
          icon: Icons.phone_android_rounded,
          isSelected: false,
          press: () {
            if (!permanent) Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const UserAppShell()));
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 6),
          child: Text(
            'FOLDERS',
            style: TextStyle(
              color: C.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        StreamBuilder<List<AppSection>>(
          stream: AppStructureService.instance.watchSections(contextFilter: 'dashboard'),
          builder: (context, secSnap) {
            final sections = secSnap.data ?? [];
            return StreamBuilder<List<AppSectionItem>>(
              stream: AppStructureService.instance.watchItems(contextFilter: 'dashboard'),
              builder: (context, itemSnap) {
                final items = itemSnap.data ?? [];
                if (sections.isEmpty) {
                  return _fallbackMenu(context, menuController, selectedRoute);
                }
                return Column(
                  children: sections.map((section) {
                    final sectionItems =
                        items.where((i) => i.sectionId == section.id).toList();
                    if (sectionItems.isEmpty) return const SizedBox.shrink();
                    return _SidebarFolder(
                      title: section.title,
                      items: sectionItems,
                      selectedRoute: selectedRoute,
                      onSelect: (route) => _open(context, menuController, route),
                      permanent: permanent,
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fallbackMenu(BuildContext context, MenuAppController c, String selected) {
    const fallback = [
      {'route': 'alerts', 'title': 'Emergency Alerts', 'icon': Icons.warning_amber_rounded},
      {'route': 'emergency_contacts', 'title': 'Contacts', 'icon': Icons.contact_phone_rounded},
      {'route': 'sos_activity', 'title': 'SOS Activity', 'icon': Icons.sos_rounded},
      {'route': 'app_structure', 'title': 'Edit Layout', 'icon': Icons.tune_rounded},
      {'route': 'settings', 'title': 'Settings', 'icon': Icons.settings_rounded},
    ];
    return Column(
      children: fallback.map((e) {
        return DrawerListTile(
          title: e['title'] as String,
          icon: e['icon'] as IconData,
          isSelected: selected == e['route'],
          press: () => _open(context, c, e['route'] as String),
        );
      }).toList(),
    );
  }

  void _open(BuildContext context, MenuAppController controller, String routeKey) {
    controller.setSelectedRoute(routeKey);
    if (!permanent && !Responsive.isDesktop(context)) {
      Navigator.pop(context);
    }
  }
}

class _SidebarFolder extends StatefulWidget {
  final String title;
  final List<AppSectionItem> items;
  final String selectedRoute;
  final void Function(String routeKey) onSelect;
  final bool permanent;

  const _SidebarFolder({
    required this.title,
    required this.items,
    required this.selectedRoute,
    required this.onSelect,
    required this.permanent,
  });

  @override
  State<_SidebarFolder> createState() => _SidebarFolderState();
}

class _SidebarFolderState extends State<_SidebarFolder> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final hasSelected =
        widget.items.any((i) => i.routeKey == widget.selectedRoute);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.only(left: 4, bottom: 4),
        leading: Icon(
          _expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
          color: hasSelected ? C.warning : C.textMuted,
          size: 22,
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: hasSelected ? C.textPrimary : C.textMuted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          '${widget.items.length} items',
          style: TextStyle(color: C.textMuted, fontSize: 10),
        ),
        iconColor: C.accent,
        collapsedIconColor: C.textMuted,
        children: widget.items.map((item) {
          final selected = widget.selectedRoute == item.routeKey;
          return DrawerListTile(
            title: item.label,
            icon: item.icon,
            isSelected: selected,
            dense: true,
            press: () => widget.onSelect(item.routeKey),
          );
        }).toList(),
      ),
    );
  }
}

class DrawerListTile extends StatelessWidget {
  const DrawerListTile({
    super.key,
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.press,
    this.dense = false,
  });

  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback press;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: press,
      dense: dense,
      horizontalTitleGap: 12,
      selected: isSelected,
      selectedTileColor: C.accent.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: EdgeInsets.symmetric(
        horizontal: dense ? 24 : 16,
        vertical: dense ? 2 : 4,
      ),
      leading: Icon(icon, color: isSelected ? C.accent : C.textMuted, size: dense ? 18 : 20),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? C.textPrimary : C.textMuted,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: dense ? 12 : 13,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
