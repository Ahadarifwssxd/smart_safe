import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/models/app_structure.dart';
import 'package:smartsafe/models/subscription_plan.dart';
import 'package:smartsafe/models/user_profile.dart';
import 'package:smartsafe/navigation/app_page_router.dart';
import 'package:smartsafe/pages/paywall_screen.dart';
import 'package:smartsafe/pages/subscription_management_screen.dart';
import 'package:smartsafe/services/app_structure_service.dart';
import 'package:smartsafe/services/subscription_service.dart';
import 'package:smartsafe/services/user_profile_service.dart';
import 'package:smartsafe/theme/colors.dart';

// ── Built-in fallback menu with PRO pages at the top ─────────────────────────
const List<AppSection> _fallbackSections = [
  AppSection(id: 'fb_pro', title: 'SmartSafe PRO 👑', sortOrder: 0),
  AppSection(id: 'fb_sos', title: 'Crisis & SOS', sortOrder: 1),
  AppSection(id: 'fb_tools', title: 'Safety Tools', sortOrder: 2),
  AppSection(id: 'fb_health', title: 'Health & Help', sortOrder: 3),
  AppSection(id: 'fb_more', title: 'More', sortOrder: 4),
];

const List<AppSectionItem> _fallbackItems = [
  // ── SmartSafe PRO Section ──────────────────────────────────
  AppSectionItem(
    id: 'pro_crash',
    sectionId: 'fb_pro',
    label: 'Crash Detection',
    subtitle: 'Auto-SOS on vehicle impact',
    iconName: 'car_crash_rounded',
    routeKey: 'crash_detection',
    sortOrder: 0,
  ),
  AppSectionItem(
    id: 'pro_danger',
    sectionId: 'fb_pro',
    label: 'Danger Zones',
    subtitle: 'High-risk map & perimeter alerts',
    iconName: 'local_fire_department_rounded',
    routeKey: 'danger_zone',
    sortOrder: 1,
  ),
  AppSectionItem(
    id: 'pro_radar',
    sectionId: 'fb_pro',
    label: 'Family Radar',
    subtitle: 'Live circle tracking & history',
    iconName: 'radar_rounded',
    routeKey: 'family_radar',
    sortOrder: 2,
  ),
  AppSectionItem(
    id: 'pro_evidence',
    sectionId: 'fb_pro',
    label: 'Evidence Vault',
    subtitle: 'Encrypted cloud locker',
    iconName: 'lock_rounded',
    routeKey: 'evidence',
    sortOrder: 3,
  ),
  AppSectionItem(
    id: 'pro_will',
    sectionId: 'fb_pro',
    label: 'Emergency Will',
    subtitle: 'Digital testament & directives',
    iconName: 'gavel_rounded',
    routeKey: 'emergency_will',
    sortOrder: 4,
  ),
  AppSectionItem(
    id: 'pro_driving',
    sectionId: 'fb_pro',
    label: 'Driving Safety',
    subtitle: 'AI speed & telemetry monitor',
    iconName: 'directions_car_rounded',
    routeKey: 'driving_safety',
    sortOrder: 5,
  ),

  // ── Crisis & SOS ───────────────────────────────────────────
  AppSectionItem(
    id: 'fb1',
    sectionId: 'fb_sos',
    label: 'Community SOS',
    iconName: 'sos_rounded',
    routeKey: 'community_sos',
    sortOrder: 0,
  ),
  AppSectionItem(
    id: 'fb2',
    sectionId: 'fb_sos',
    label: 'My SOS History',
    iconName: 'history_rounded',
    routeKey: 'my_sos_history',
    sortOrder: 1,
  ),
  AppSectionItem(
    id: 'fb3',
    sectionId: 'fb_sos',
    label: 'Panic Toolkit',
    iconName: 'campaign_rounded',
    routeKey: 'panic_toolkit',
    sortOrder: 2,
  ),
  AppSectionItem(
    id: 'fb4',
    sectionId: 'fb_sos',
    label: 'Emergency Dial',
    iconName: 'phone_forwarded_rounded',
    routeKey: 'emergency_dial',
    sortOrder: 3,
  ),

  // ── Safety Tools ───────────────────────────────────────────
  AppSectionItem(
    id: 'fb5',
    sectionId: 'fb_tools',
    label: 'Women Safety',
    iconName: 'female_rounded',
    routeKey: 'women_safety',
    sortOrder: 0,
  ),
  AppSectionItem(
    id: 'fb6',
    sectionId: 'fb_tools',
    label: 'Child Safety',
    iconName: 'child_care_rounded',
    routeKey: 'child_safety',
    sortOrder: 1,
  ),
  AppSectionItem(
    id: 'fb7',
    sectionId: 'fb_tools',
    label: 'Safe Route',
    iconName: 'route_rounded',
    routeKey: 'safe_route',
    sortOrder: 2,
  ),
  AppSectionItem(
    id: 'fb8',
    sectionId: 'fb_tools',
    label: 'Live GPS',
    iconName: 'location_on_rounded',
    routeKey: 'live_gps',
    sortOrder: 3,
  ),
  AppSectionItem(
    id: 'fb9',
    sectionId: 'fb_tools',
    label: 'Safe Check-in',
    iconName: 'timer_rounded',
    routeKey: 'safe_checkin',
    sortOrder: 4,
  ),

  // ── Health & Help ──────────────────────────────────────────
  AppSectionItem(
    id: 'fb10',
    sectionId: 'fb_health',
    label: 'First Aid',
    iconName: 'medical_services_rounded',
    routeKey: 'first_aid',
    sortOrder: 0,
  ),
  AppSectionItem(
    id: 'fb11',
    sectionId: 'fb_health',
    label: 'Panic Breathe',
    iconName: 'air_rounded',
    routeKey: 'panic_breathe',
    sortOrder: 1,
  ),

  // ── More ───────────────────────────────────────────────────
  AppSectionItem(
    id: 'fb13',
    sectionId: 'fb_more',
    label: 'Emergency Contacts',
    iconName: 'contact_phone_rounded',
    routeKey: 'contacts_page',
    sortOrder: 0,
  ),
  AppSectionItem(
    id: 'fb14',
    sectionId: 'fb_more',
    label: 'Alert History',
    iconName: 'notifications_rounded',
    routeKey: 'alert_history',
    sortOrder: 1,
  ),
  AppSectionItem(
    id: 'fb15',
    sectionId: 'fb_more',
    label: 'Safety Feed',
    iconName: 'rss_feed_rounded',
    routeKey: 'safety_feed',
    sortOrder: 2,
  ),
  AppSectionItem(
    id: 'fb16',
    sectionId: 'fb_more',
    label: 'Safety Score',
    iconName: 'shield_rounded',
    routeKey: 'safety_score',
    sortOrder: 3,
  ),
];

/// App side menu with PRO badges, real-time lock/unlock status, and subscription banner.
class DynamicAppDrawer extends StatelessWidget {
  final VoidCallback? onSOSTap;

  const DynamicAppDrawer({super.key, this.onSOSTap});

  void _handleItemTap(
      BuildContext context, String routeKey, String label, bool isPremium) {
    final isPro = SubscriptionInfo.isProRoute(routeKey);

    if (isPro && !isPremium) {
      // Locked PRO feature tapped by free user
      _showProLockModal(context, label);
      return;
    }

    Navigator.pop(context);
    AppPageRouter.open(context, routeKey, onSOSTap: onSOSTap);
  }

  void _showProLockModal(BuildContext context, String featureLabel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: C.accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: C.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: C.accent, width: 1.5),
              ),
              child: Icon(Icons.lock_person_rounded, color: C.accent, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              'Unlock $featureLabel',
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$featureLabel is an exclusive SmartSafe PRO security feature. Upgrade now to unlock all 6 premium security tools instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context); // Close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaywallScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.workspace_premium_rounded,
                      color: Colors.black, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Upgrade with JazzCash / Card / EasyPaisa',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
          child: StreamBuilder<SubscriptionInfo>(
            stream: SubscriptionService.instance.subscriptionInfoStream,
            initialData: SubscriptionService.instance.currentInfo,
            builder: (context, subSnap) {
              final subInfo = subSnap.data ?? SubscriptionInfo.free;
              final isPremium =
                  subInfo.isActive && subInfo.plan == PlanType.premium;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DrawerHeader(),

                  // ── Top PRO Subscription Status Banner ─────────────
                  _SubscriptionBanner(subInfo: subInfo, isPremium: isPremium),

                  Expanded(
                    child: StreamBuilder<List<AppSection>>(
                      stream: AppStructureService.instance
                          .watchSections(contextFilter: 'app'),
                      builder: (context, secSnap) {
                        final sections = secSnap.data ?? const <AppSection>[];
                        return StreamBuilder<List<AppSectionItem>>(
                          stream: AppStructureService.instance
                              .watchItems(contextFilter: 'app'),
                          builder: (context, itemSnap) {
                            final items =
                                itemSnap.data ?? const <AppSectionItem>[];

                            // If sections from Firestore exist, prepend PRO section if missing
                            List<AppSection> effectiveSections =
                                List.from(sections.isEmpty
                                    ? _fallbackSections
                                    : sections);
                            List<AppSectionItem> effectiveItems =
                                List.from(items.isEmpty ? _fallbackItems : items);

                            // Ensure PRO section always exists in drawer
                            if (!effectiveSections.any((s) => s.id == 'fb_pro')) {
                              effectiveSections.insert(
                                0,
                                const AppSection(
                                    id: 'fb_pro',
                                    title: 'SmartSafe PRO 👑',
                                    sortOrder: -1),
                              );
                              final proItems = _fallbackItems
                                  .where((i) => i.sectionId == 'fb_pro');
                              for (var pi in proItems) {
                                if (!effectiveItems
                                    .any((i) => i.routeKey == pi.routeKey)) {
                                  effectiveItems.add(pi);
                                }
                              }
                            }

                            return _DrawerSections(
                              sections: effectiveSections,
                              items: effectiveItems,
                              isPremium: isPremium,
                              onItem: (routeKey, label) => _handleItemTap(
                                context,
                                routeKey,
                                label,
                                isPremium,
                              ),
                            );
                          },
                        );
                      },
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

/// Dynamic subscription badge banner in the drawer header
class _SubscriptionBanner extends StatelessWidget {
  final SubscriptionInfo subInfo;
  final bool isPremium;

  const _SubscriptionBanner({
    required this.subInfo,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            if (isPremium) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SubscriptionManagementScreen()),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              );
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPremium
                    ? [
                        C.accent.withValues(alpha: 0.25),
                        C.bg2,
                      ]
                    : [
                        C.accent.withValues(alpha: 0.15),
                        C.bg2,
                      ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isPremium
                    ? C.accent
                    : C.accent.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isPremium
                        ? C.accent.withValues(alpha: 0.2)
                        : C.bg3,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPremium
                        ? Icons.workspace_premium_rounded
                        : Icons.star_rounded,
                    color: C.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isPremium
                                ? 'SmartSafe PRO'
                                : 'Upgrade to PRO',
                            style: TextStyle(
                              color: C.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isPremium
                                  ? C.success.withValues(alpha: 0.2)
                                  : C.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isPremium ? 'ACTIVE' : 'LOCKED',
                              style: TextStyle(
                                color: isPremium ? C.success : C.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        isPremium
                            ? (subInfo.daysRemaining != null
                                ? '${subInfo.daysRemaining} days left • Tap to manage'
                                : 'All features unlocked')
                            : 'Tap to unlock all 6 premium tools',
                        style: TextStyle(color: C.textMuted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: C.accent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerSections extends StatefulWidget {
  final List<AppSection> sections;
  final List<AppSectionItem> items;
  final bool isPremium;
  final void Function(String routeKey, String label) onItem;

  const _DrawerSections({
    required this.sections,
    required this.items,
    required this.isPremium,
    required this.onItem,
  });

  @override
  State<_DrawerSections> createState() => _DrawerSectionsState();
}

class _DrawerSectionsState extends State<_DrawerSections> {
  final Set<String> _expanded = {};
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    final visible = widget.sections
        .where((s) => widget.items.any((i) => i.sectionId == s.id))
        .toList();

    if (!_init && visible.isNotEmpty) {
      _expanded.add(visible.first.id); // Open PRO section first
      _init = true;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
      children: visible.map((section) {
        final sectionItems =
            widget.items.where((i) => i.sectionId == section.id).toList();
        final open = _expanded.contains(section.id);
        final isProSection = section.id == 'fb_pro';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: section.title,
              count: sectionItems.length,
              expanded: open,
              isProSection: isProSection,
              onTap: () => setState(() {
                if (open) {
                  _expanded.remove(section.id);
                } else {
                  _expanded.add(section.id);
                }
              }),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Column(
                children: [
                  const SizedBox(height: 4),
                  ...sectionItems.map((item) {
                    final isPro = SubscriptionInfo.isProRoute(item.routeKey);
                    return _DrawerTile(
                      icon: item.icon,
                      label: item.label,
                      subtitle: item.subtitle.isNotEmpty
                          ? item.subtitle
                          : (item.buttonText.isNotEmpty
                              ? item.buttonText
                              : null),
                      color: isPro ? C.accent : item.color,
                      isPro: isPro,
                      isUnlocked: widget.isPremium,
                      onTap: () => widget.onItem(item.routeKey, item.label),
                    );
                  }),
                ],
              ),
              crossFadeState:
                  open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 240),
              sizeCurve: Curves.easeOutCubic,
            ),
            const SizedBox(height: 6),
          ],
        );
      }).toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool expanded;
  final bool isProSection;
  final VoidCallback onTap;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    this.isProSection = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: isProSection
                        ? C.accent
                        : (expanded ? C.textPrimary : C.textMuted),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isProSection
                      ? C.accent.withValues(alpha: 0.15)
                      : C.bg3,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isProSection ? C.accent : C.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.chevron_right_rounded,
                    color: isProSection ? C.accent : C.textMuted, size: 20),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppTheme.sosGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: profile != null && profile.name.isNotEmpty
                      ? Text(profile.initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800))
                      : const Icon(Icons.shield_rounded,
                          color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.name.isNotEmpty == true
                          ? profile!.name
                          : 'SmartSafe',
                      style: AppTheme.displayFont
                          .copyWith(color: C.textPrimary, fontSize: 17),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      profile?.email.isNotEmpty == true
                          ? profile!.email
                          : 'Emergency & Protection',
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

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final bool isPro;
  final bool isUnlocked;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    this.isPro = false,
    this.isUnlocked = false,
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
          child: Ink(
            decoration: BoxDecoration(
              gradient: isPro
                  ? LinearGradient(
                      colors: isUnlocked
                          ? [
                              C.accent.withValues(alpha: 0.15),
                              C.bg2,
                            ]
                          : [
                              C.bg2,
                              C.bg3,
                            ],
                    )
                  : AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: isPro
                    ? (isUnlocked
                        ? C.accent.withValues(alpha: 0.45)
                        : C.accent.withValues(alpha: 0.2))
                    : color.withValues(alpha: 0.25),
                width: isPro ? 1.2 : 1,
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isPro ? 0.25 : 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isPro) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isUnlocked
                                        ? [C.accent, C.success]
                                        : [
                                            C.accent.withValues(alpha: 0.4),
                                            C.accent.withValues(alpha: 0.2),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'PRO',
                                      style: TextStyle(
                                        color: isUnlocked
                                            ? Colors.black
                                            : C.accent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      isUnlocked
                                          ? Icons.auto_awesome_rounded
                                          : Icons.lock_rounded,
                                      size: 10,
                                      color: isUnlocked
                                          ? Colors.black
                                          : C.accent,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: C.textMuted,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    isPro && !isUnlocked
                        ? Icons.lock_outline_rounded
                        : Icons.chevron_right_rounded,
                    color: isPro && !isUnlocked
                        ? C.accent.withValues(alpha: 0.7)
                        : C.textMuted.withValues(alpha: 0.6),
                    size: 20,
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
