import '../services/app_structure_service.dart';
import '../models/app_structure.dart';
import '../navigation/app_page_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../navigation/dark_route.dart';
import '../services/user_profile_service.dart';
import '../theme/colors.dart';
import '../pages/11_women_safety_page.dart';
import '../pages/13_evidence_page.dart';
import '../pages/15_emergency_will_page.dart';
import '../pages/16_emergency_dial_page.dart';
import '../pages/28_enhanced_community_sos_page.dart';
import '../pages/hub_emergency.dart';

/// Side menu for Safety Hub features (kept off the home screen).
class SmartSafeDrawer extends StatelessWidget {
  final VoidCallback? onSOSTap;

  const SmartSafeDrawer({super.key, this.onSOSTap});

  void _go(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.push(context, darkRoute(page));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [C.bg, C.bg3.withValues(alpha: 0.95)],
          ),
          border:
              Border(right: BorderSide(color: C.border.withValues(alpha: 0.6))),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DrawerHeader(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  children: [
                    const _SectionLabel('Crisis & SOS'),
                    _DrawerTile(
                      icon: Icons.groups_rounded,
                      label: 'Community SOS',
                      subtitle: 'Alert nearby SmartSafe users',
                      color: C.accent,
                      onTap: () => _go(
                        context,
                        const EnhancedCommunitySosPage(),
                      ),
                    ),
                    _DrawerTile(
                      icon: Icons.campaign_rounded,
                      label: 'Crisis Hub',
                      subtitle: 'All emergency tools',
                      color: C.accent,
                      onTap: () => _go(
                        context,
                        EmergencyHubPage(onSOSTap: onSOSTap),
                      ),
                    ),
                    _DrawerTile(
                      icon: Icons.female_rounded,
                      label: 'Women Safety',
                      color: C.accent,
                      onTap: () => _go(context, const WomenSafetyPage()),
                    ),
                    _DrawerTile(
                      icon: Icons.camera_alt_rounded,
                      label: 'Evidence Recorder',
                      color: C.accent,
                      onTap: () => _go(context, const EvidencePage()),
                    ),
                    _DrawerTile(
                      icon: Icons.phone_forwarded_rounded,
                      label: 'Emergency Dial',
                      color: C.accent,
                      onTap: () => _go(context, const EmergencyDialPage()),
                    ),
                    _DrawerTile(
                      icon: Icons.gavel_rounded,
                      label: 'Emergency Will',
                      color: C.warning,
                      onTap: () => _go(context, const EmergencyWillPage()),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 8),
                    StreamBuilder<List<AppSection>>(
                      stream: AppStructureService.instance
                          .watchSections(contextFilter: 'app'),
                      builder: (context, secSnap) {
                        final sections = secSnap.data ?? [];
                        return StreamBuilder<List<AppSectionItem>>(
                          stream: AppStructureService.instance
                              .watchItems(contextFilter: 'app'),
                          builder: (context, itemSnap) {
                            final items = itemSnap.data ?? [];
                            if (sections.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: sections.map((section) {
                                if (section.title
                                        .toLowerCase()
                                        .contains('crisis') ||
                                    section.title
                                        .toLowerCase()
                                        .contains('sos')) {
                                  return const SizedBox.shrink();
                                }

                                final sectionItems = items
                                    .where((i) => i.sectionId == section.id)
                                    .toList();
                                if (sectionItems.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _SectionLabel(section.title),
                                    ...sectionItems.map((item) {
                                      return _DrawerTile(
                                        icon: item.icon,
                                        label: item.label,
                                        subtitle: item.subtitle.isEmpty
                                            ? null
                                            : item.subtitle,
                                        color: item.color,
                                        onTap: () {
                                          Navigator.pop(context);
                                          AppPageRouter.open(
                                              context, item.routeKey,
                                              onSOSTap: onSOSTap);
                                        },
                                      );
                                    }).toList(),
                                    const SizedBox(height: 8),
                                  ],
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
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        border:
            Border(bottom: BorderSide(color: C.border.withValues(alpha: 0.5))),
      ),
      child: StreamBuilder<UserProfile?>(
        stream: UserProfileService.instance.profileStream(),
        builder: (context, snapshot) {
          final user = FirebaseAuth.instance.currentUser;
          final profile = snapshot.data ??
              (user != null ? UserProfile.fromAuthUser(user) : null);

          return Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppTheme.sosGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppTheme.glowShadow(C.accent),
                ),
                child: Center(
                  child: profile != null && profile.name.isNotEmpty
                      ? Text(
                          profile.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : const Icon(Icons.shield_rounded,
                          color: Colors.white, size: 26),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile != null && profile.name.isNotEmpty
                          ? profile.name
                          : 'SmartSafe',
                      style: AppTheme.displayFont.copyWith(
                        color: C.textPrimary,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile != null && profile.email.isNotEmpty
                          ? profile.email
                          : 'Safety Hubs & tools',
                      style: AppTheme.bodyFont
                          .copyWith(color: C.textMuted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: C.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: color.withValues(alpha: 0.12),
          highlightColor: color.withValues(alpha: 0.06),
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.25)),
              boxShadow: AppTheme.cardShadow(color),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.25),
                          color.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: C.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(color: C.textMuted, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: C.textMuted.withValues(alpha: 0.6),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
