import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../services/user_profile_service.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../theme/design_tokens.dart';
import '../utils/emoji_icon.dart';
import '../models/models.dart';
import '../models/app_structure.dart';
import '../services/app_firestore_service.dart';
import '../widgets/widgets.dart';
import '../widgets/dynamic_app_drawer.dart';
import '../services/app_structure_service.dart';
import '../navigation/app_page_router.dart';
import '../widgets/app_search_bar.dart';

import 'package:intl/intl.dart';
import '../models/subscription_plan.dart';
import '../services/subscription_service.dart';
import 'paywall_screen.dart';
import 'subscription_management_screen.dart';
import '28_enhanced_community_sos_page.dart';

/// A time-of-day greeting that matches how people actually experience the day:
/// morning (5-11), afternoon (12-16), evening (17-20), night (21-4).
String timeGreeting() {
  final h = DateTime.now().hour;
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  if (h >= 17 && h < 21) return 'Good evening';
  return 'Good night';
}

class HomePage extends StatefulWidget {
  final VoidCallback? onSOSTap;
  final VoidCallback? onViewContacts;
  final VoidCallback? onOpenNotifications;
  const HomePage(
      {super.key,
      this.onSOSTap,
      this.onViewContacts,
      this.onOpenNotifications});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final String _date;

  @override
  void initState() {
    super.initState();
    // Date only needs computing once — it does not change second to second,
    // so we avoid rebuilding the whole page every second (major perf win).
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    _date = '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';

    // First-time guide so a brand-new user knows how SOS works + to add
    // contacts. Background protection is NOT requested here: starting the
    // always-on foreground service at launch kills the app on aggressive OEMs
    // (MIUI/Xiaomi). It stays opt-in from Settings → Background Protection.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeShowIntro();
    });
  }

  Future<void> _maybeShowIntro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('home_sos_intro_v1') == true) return;
      await prefs.setBool('home_sos_intro_v1', true);
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => _SosIntroDialog(
          onAddContacts: () {
            Navigator.pop(ctx);
            widget.onViewContacts?.call();
          },
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final isSmall = screenH < 700;
    final sosSize = isSmall ? 120.0 : 150.0;
    return Scaffold(
      backgroundColor: C.bg,
      drawer: DynamicAppDrawer(onSOSTap: widget.onSOSTap),
      drawerEdgeDragWidth: 24,
      body: Stack(
        children: [
          const DotGrid(),
          SafeArea(
            child: SingleChildScrollView(
              padding: responsiveScrollPadding(context, horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header — fully responsive, no overflow
                  SlideUpFade(
                    delay: const Duration(milliseconds: 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Builder(
                          builder: (ctx) => GestureDetector(
                            onTap: () => Scaffold.of(ctx).openDrawer(),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: AppTheme.cardGradient,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusMd),
                                border: Border.all(
                                    color: C.border),
                                boxShadow: AppTheme.cardShadow(C.accent),
                              ),
                              child: Icon(
                                Icons.menu_rounded,
                                color: C.accent,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StreamBuilder<UserProfile?>(
                            stream: UserProfileService.instance.profileStream(),
                            builder: (context, snapshot) {
                              final user = FirebaseAuth.instance.currentUser;
                              final profile = snapshot.data ??
                                  (user != null
                                      ? UserProfile.fromAuthUser(user)
                                      : null);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Force the brand title onto a single line on
                                  // every width: FittedBox scales it down to fit
                                  // the space left of the bell + clock instead of
                                  // wrapping to a second line / clipping mid-word.
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: BrandTitle('SmartSafe', size: 22),
                                    ),
                                  ),
                                  if (profile != null &&
                                      profile.name.isNotEmpty)
                                    Text(
                                      '${timeGreeting()}, ${profile.firstName}',
                                      style: AppTheme.bodyFont.copyWith(
                                        color: C.accent,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    _date,
                                    style: AppTheme.bodyFont.copyWith(
                                      color: C.textMuted,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Notifications — moved up here from the bottom tab bar.
                        _NotifBell(onTap: widget.onOpenNotifications),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SlideUpFade(
                    delay: const Duration(milliseconds: 50),
                    child: AppSearchBar(onSOSTap: widget.onSOSTap),
                  ),
                  const SizedBox(height: 24),

                  // SOS Button Area
                  SlideUpFade(
                    delay: const Duration(milliseconds: 100),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PulseRing(color: C.red, size: sosSize + 10),
                          PulseSOSButton(
                            size: sosSize,
                            onTap: () => widget.onSOSTap?.call(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SlideUpFade(
                    delay: const Duration(milliseconds: 150),
                    child: Center(
                      child: Text(
                        'TAP OR SHAKE TO SEND SOS',
                        style: TextStyle(
                          color: C.textMuted,
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Quick Access Section (Main critical features)
                  const SlideUpFade(
                    delay: Duration(milliseconds: 200),
                    child: SectionHeader(title: 'Quick Access'),
                  ),
                  const SizedBox(height: 12),
                  _DynamicQuickAccess(onSOSTap: widget.onSOSTap),
                  const SizedBox(height: 20),

                  _DynamicFeaturedCard(onSOSTap: widget.onSOSTap),
                  const SizedBox(height: 16),

                  // ── SmartSafe PRO Live Subscription Card ─────────
                  SlideUpFade(
                    delay: const Duration(milliseconds: 260),
                    child: _HomeProSubscriptionCard(),
                  ),
                  const SizedBox(height: C.spaceMd),

                  // Drawer hint
                  SlideUpFade(
                    delay: const Duration(milliseconds: 300),
                    child: Builder(
                      builder: (ctx) => GestureDetector(
                        onTap: () => Scaffold.of(ctx).openDrawer(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: AppTheme.cardGradient,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMd),
                            border: Border.all(color: C.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.apps_rounded, color: C.accent, size: 22),
                              const SizedBox(width: C.spaceMd),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'More safety tools',
                                      style: AppTheme.displayFont.copyWith(
                                        fontSize: 13,
                                        color: C.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Open menu for hubs, reports & insights',
                                      style: AppTheme.bodyFont.copyWith(
                                        color: C.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: C.textMuted, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: C.spaceLg),

                  // Trusted Circle — live from Firestore
                  SlideUpFade(
                    delay: const Duration(milliseconds: 300),
                    child: SectionHeader(
                      title: 'Trusted Circle',
                      action: 'View All',
                      onActionTap: widget.onViewContacts,
                    ),
                  ),
                  const SizedBox(height: C.spaceMd),
                  SlideUpFade(
                    delay: const Duration(milliseconds: 350),
                    child: StreamBuilder<List<Contact>>(
                      stream: AppFirestoreService.instance
                          .watchMyEmergencyContacts(),
                      builder: (context, snap) {
                        // While the first load is still in flight, show a quiet
                        // placeholder instead of flashing the empty-state CTA
                        // and then swapping to the avatar row.
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return Container(
                            height: 76,
                            decoration: BoxDecoration(
                              color: C.bg2,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: C.border),
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: C.accent),
                              ),
                            ),
                          );
                        }
                        final contacts = snap.data ?? [];
                        if (contacts.isEmpty) {
                          // Empty → make it an obvious "add family/friends" CTA.
                          return GestureDetector(
                            onTap: widget.onViewContacts,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(C.spaceMd),
                              decoration: BoxDecoration(
                                color: C.accent.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: C.accent.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.person_add_alt_1_rounded,
                                      color: C.accent, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Add family & friends',
                                          style: TextStyle(
                                              color: C.textPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Add their number & email so SOS can call, SMS & email them',
                                          style: TextStyle(
                                              color: C.textMuted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded,
                                      color: C.accent, size: 22),
                                ],
                              ),
                            ),
                          );
                        }
                        return GestureDetector(
                          onTap: widget.onViewContacts,
                          behavior: HitTestBehavior.opaque,
                          child: DCard(
                          color: C.bg2,
                          padding: const EdgeInsets.all(C.spaceMd),
                          child: Row(
                            children: [
                              ...contacts.take(4).map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Column(
                                        children: [
                                          Stack(
                                            children: [
                                              AvatarWidget(
                                                initials: c.initials,
                                                color: c.avatarColor,
                                                size: 46,
                                              ),
                                              // Polished online badge — green dot
                                              // with a ring so it reads clearly.
                                              Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  width: 14,
                                                  height: 14,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: c.isOnline
                                                        ? C.success
                                                        : C.textDim,
                                                    border: Border.all(
                                                        color: C.bg2, width: 2.5),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: C.spaceSm),
                                          Text(
                                            c.displayFirstName,
                                            style: TextStyle(
                                              color: C.textPrimary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            c.isOnline ? 'Online' : 'Offline',
                                            style: TextStyle(
                                              color: c.isOnline
                                                  ? C.success
                                                  : C.textMuted,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              // Add more contacts affordance
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: C.accent.withValues(alpha: 0.15),
                                      border: Border.all(
                                          color: C.accent.withValues(alpha: 0.4)),
                                    ),
                                    child: Icon(Icons.add_rounded,
                                        color: C.accent, size: 22),
                                  ),
                                  const SizedBox(height: C.spaceSm),
                                  Text('Add',
                                      style: TextStyle(
                                          color: C.accent, fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: C.spaceLg),

                  // Shake tip
                  SlideUpFade(
                    delay: const Duration(milliseconds: 400),
                    child: Container(
                      padding: const EdgeInsets.all(C.spaceMd),
                      decoration: BoxDecoration(
                        color: C.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: C.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.vibration_rounded,
                              color: C.accent, size: 22),
                          const SizedBox(width: C.spaceMd),
                          Expanded(
                            child: Text(
                              'Shake your phone 3× rapidly to trigger SOS instantly',
                              style: TextStyle(color: C.textPrimary, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: C.spaceLg),

                  // Safety Tips
                  const SlideUpFade(
                    delay: Duration(milliseconds: 450),
                    child: SectionHeader(title: 'Safety Tips'),
                  ),
                  const SizedBox(height: C.spaceMd),
                  StreamBuilder<List<SafetyTip>>(
                    stream: AppFirestoreService.instance.watchSafetyTips(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final tips = snap.data ?? const <SafetyTip>[];
                      if (tips.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No safety tips available yet.',
                            style: TextStyle(color: C.textMuted, fontSize: 12),
                          ),
                        );
                      }
                      return Column(
                        children: tips
                            .asMap()
                            .entries
                            .map((e) {
                              final featured = e.key == 0;
                              return SlideUpFade(
                                  delay: Duration(
                                      milliseconds: (500 + e.key * 50).toInt()),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: DCard(
                                      color: featured
                                          ? C.accent.withValues(alpha: 0.08)
                                          : C.bg2,
                                      borderColor: featured
                                          ? C.accent.withValues(alpha: 0.45)
                                          : null,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (featured) ...[
                                            Row(children: [
                                              Icon(Icons.star_rounded,
                                                  color: C.accent, size: 14),
                                              const SizedBox(width: 5),
                                              Text("TODAY'S SAFETY TIP",
                                                  style: TextStyle(
                                                      color: C.accent,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.8)),
                                            ]),
                                            const SizedBox(height: 10),
                                          ],
                                          Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: C.accent
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              iconForEmoji(e.value.emoji),
                                              color: C.accent,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: C.spaceMd),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(e.value.title,
                                                    style: TextStyle(
                                                        color: C.textPrimary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 13.5,
                                                        letterSpacing: 0.1)),
                                                const SizedBox(height: 4),
                                                Text(e.value.body,
                                                    style: TextStyle(
                                                        color: C.textMuted,
                                                        fontSize: 11.5,
                                                        height: 1.4)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                            }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Notifications bell for the header (moved up from the bottom tab bar).
/// Opens the same Notifications screen and shows a live unread badge.
class _NotifBell extends StatelessWidget {
  final VoidCallback? onTap;
  const _NotifBell({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: C.border),
              boxShadow: AppTheme.cardShadow(C.accent),
            ),
            child: Icon(Icons.notifications_rounded, color: C.accent, size: 22),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: StreamBuilder<int>(
              stream:
                  AppFirestoreService.instance.watchUnreadNotificationCount(),
              builder: (context, snap) {
                final n = snap.data ?? 0;
                if (n <= 0) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(4),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    gradient: AppTheme.sosGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.glowShadow(C.accent, blur: 8),
                  ),
                  child: Center(
                    child: Text(
                      n > 99 ? '99+' : '$n',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


/// One-time welcome guide for new users — explains how SOS works and nudges
/// them to add emergency contacts (without which SOS has no one to alert).
class _SosIntroDialog extends StatelessWidget {
  final VoidCallback onAddContacts;
  const _SosIntroDialog({required this.onAddContacts});

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: C.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: TextStyle(color: C.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Dialog(
      backgroundColor: C.bg2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_rounded, color: C.accent, size: 26),
                const SizedBox(width: 10),
                Text('Welcome to SmartSafe',
                    style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Here is how it keeps you safe:',
                style: TextStyle(color: C.textMuted, fontSize: 12)),
            const SizedBox(height: 18),
            step(Icons.person_add_alt_1_rounded, '1. Add your people',
                'Add family & friends with their phone number and email.'),
            step(Icons.touch_app_rounded, '2. Press SOS (or shake)',
                'One tap in danger — or shake your phone 3×.'),
            step(Icons.campaign_rounded, '3. They get alerted instantly',
                'A call, SMS, WhatsApp & email go to them with your live location.'),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAddContacts,
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: const Text('Add emergency contacts',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("I'll do it later",
                    style: TextStyle(color: C.textMuted, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DynamicQuickAccess extends StatelessWidget {
  final VoidCallback? onSOSTap;
  const _DynamicQuickAccess({this.onSOSTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppSection>>(
      stream: AppStructureService.instance.watchSections(contextFilter: 'app'),
      builder: (context, secSnap) {
        AppSection? homeSection;
        for (final s in secSnap.data ?? []) {
          if (s.title.toLowerCase().contains('quick')) {
            homeSection = s;
            break;
          }
        }
        return StreamBuilder<List<AppSectionItem>>(
          stream: AppStructureService.instance.watchItems(contextFilter: 'app'),
          builder: (context, itemSnap) {
            var items = itemSnap.data ?? [];
            final quickSec = homeSection;
            if (quickSec != null) {
              items = items.where((i) => i.sectionId == quickSec.id).toList();
            } else {
              items = items
                  .where((i) => i.itemType == 'button' && i.routeKey.isNotEmpty)
                  .take(3)
                  .toList();
            }
            if (items.isEmpty) {
              return GridView.count(
                crossAxisCount:
                    MediaQuery.of(context).size.width < 600 ? 3 : 6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.86,
                children: [
                  _QuickCard(
                      icon: Icons.location_on_rounded,
                      label: 'Live GPS',
                      color: C.accent,
                      onTap: () => AppPageRouter.open(context, 'live_gps',
                          onSOSTap: onSOSTap)),
                  _QuickCard(
                      icon: Icons.route_rounded,
                      label: 'Safe Route',
                      color: C.accent,
                      onTap: () => AppPageRouter.open(context, 'safe_route',
                          onSOSTap: onSOSTap)),
                  _QuickCard(
                      icon: Icons.campaign_rounded,
                      label: 'Panic Tool',
                      color: C.accent,
                      onTap: () => AppPageRouter.open(context, 'panic_toolkit',
                          onSOSTap: onSOSTap)),
                ],
              );
            }
            return GridView.count(
              crossAxisCount:
                  MediaQuery.of(context).size.width < 600 ? 3 : 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.86,
              children: items.map((item) {
                final label =
                    item.buttonText.isNotEmpty ? item.buttonText : item.label;
                return _QuickCard(
                  icon: item.icon,
                  label: label,
                  color: item.color,
                  onTap: () => AppPageRouter.open(context, item.routeKey,
                      onSOSTap: onSOSTap),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}

class _DynamicFeaturedCard extends StatelessWidget {
  final VoidCallback? onSOSTap;
  const _DynamicFeaturedCard({this.onSOSTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppSection>>(
      stream: AppStructureService.instance.watchSections(contextFilter: 'app'),
      builder: (context, secSnap) {
        AppSection? feat;
        for (final s in secSnap.data ?? []) {
          if (s.title.toLowerCase().contains('featured')) {
            feat = s;
            break;
          }
        }
        return StreamBuilder<List<AppSectionItem>>(
          stream: AppStructureService.instance.watchItems(contextFilter: 'app'),
          builder: (context, itemSnap) {
            final items = itemSnap.data ?? [];
            AppSectionItem? item;
            final featSec = feat;
            if (featSec != null) {
              final list =
                  items.where((i) => i.sectionId == featSec.id).toList();
              if (list.isNotEmpty) item = list.first;
            }
            item ??=
                items.where((i) => i.routeKey == 'community_sos').isNotEmpty
                    ? items.firstWhere((i) => i.routeKey == 'community_sos')
                    : null;
            final label = item?.label ?? 'Community SOS';
            final sub = item?.subtitle ?? 'Alert nearby users';
            final btn = item?.buttonText ?? 'Tap to Open';
            return SlideUpFade(
              delay: const Duration(milliseconds: 280),
              child: AnimatedButton(
                onTap: () {
                  if (item?.routeKey.isNotEmpty == true) {
                    AppPageRouter.open(context, item!.routeKey,
                        onSOSTap: onSOSTap);
                  } else {
                    EnhancedCommunitySosPage.open(context);
                  }
                },
                child: GlassCard(
                  padding: const EdgeInsets.all(DesignTokens.space16),
                  borderColor: C.border,
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppTheme.sosGradient,
                          borderRadius: DesignTokens.borderRadius16,
                          boxShadow: AppTheme.glowShadow(C.accent, blur: 16),
                        ),
                        child: Icon(item?.icon ?? Icons.groups_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: DesignTokens.spaceMd),
                      // Title sits on its own line with the call-to-action in the
                      // top-right corner; the subtitle then gets the card's full
                      // width beneath them. Previously the CTA was a sibling of
                      // this column, so it stole horizontal space and forced both
                      // the title and the subtitle to wrap.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title gets the FULL width on its own line so
                            // "Community SOS" is never truncated to "Community S…".
                            Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesignTokens.h3
                                    .copyWith(color: C.textPrimary)),
                            const SizedBox(height: 4),
                            // Subtitle + call-to-action share the second line,
                            // where there's room; the subtitle flexes/ellipsises.
                            Row(
                              children: [
                                Expanded(
                                  child: Text(sub,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DesignTokens.caption
                                          .copyWith(color: C.textMuted)),
                                ),
                                const SizedBox(width: 8),
                                Text(btn,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: DesignTokens.label
                                        .copyWith(color: C.accent)),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward_ios_rounded,
                                    color: C.accent, size: 14),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedButton(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space8, vertical: DesignTokens.space12),
        borderColor: C.border,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: C.accent.withValues(alpha: 0.13),
                border: Border.all(color: C.accent.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: C.accent, size: 22),
            ),
            const SizedBox(height: DesignTokens.space8),
            // Center + wrap to 2 lines so longer labels (e.g. "Open Toolkit")
            // never get clipped inside the near-square card.
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.bodyStrong.copyWith(
                  color: C.textPrimary,
                  fontSize: 11.5,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeProSubscriptionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionInfo>(
      stream: SubscriptionService.instance.subscriptionInfoStream,
      initialData: SubscriptionService.instance.currentInfo,
      builder: (context, snap) {
        final info = snap.data ?? SubscriptionInfo.free;
        final isPremium = info.isActive && info.plan == PlanType.premium;

        if (isPremium) {
          // VIP Gold/Emerald Card
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  C.accent.withValues(alpha: 0.25),
                  C.bg2,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: C.accent.withValues(alpha: 0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: C.accent.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: C.accent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: Colors.amber, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                info.displayName,
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: C.success.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: C.success,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            info.paymentMethod != null
                                ? 'Paid via ${info.displayPaymentMethod}'
                                : 'All PRO features unlocked',
                            style: TextStyle(
                              color: C.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const SubscriptionManagementScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: C.bg3,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: C.border.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Manage',
                              style: TextStyle(
                                color: C.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded,
                                color: C.accent, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (info.expiresAt != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          color: C.accent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Valid until ${DateFormat('dd MMM yyyy').format(info.expiresAt!)}',
                        style: TextStyle(color: C.textMuted, fontSize: 11),
                      ),
                      if (info.daysRemaining != null) ...[
                        Text(
                          ' (${info.daysRemaining} days left)',
                          style: TextStyle(
                              color: C.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          );
        }

        // Free plan: High-converting upgrade card
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                C.accent.withValues(alpha: 0.15),
                C.bg2,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: C.accent.withValues(alpha: 0.3),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: C.accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.star_rounded,
                        color: C.accent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'SmartSafe PRO',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: C.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'PREMIUM',
                                style: TextStyle(
                                  color: C.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Unlock Crash Detection, Live Radar & Vault',
                          style: TextStyle(color: C.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PaywallScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Upgrade',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
