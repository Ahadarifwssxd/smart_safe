import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../models/user_roles.dart';
import '../models/subscription_plan.dart';
import '../navigation/dark_route.dart';
import '../services/user_profile_service.dart';
import '../services/app_firestore_service.dart';
import '../services/location_service.dart';
import '../services/sensor_service.dart';
import '../services/background_sos_service.dart';
import '../services/subscription_service.dart';
import 'my_sos_history_page.dart';
import 'primary_sos_contact_page.dart';
import '25_forgot_password_page.dart';
import 'privacy_policy_page.dart';
import 'paywall_screen.dart';
import 'subscription_management_screen.dart';
import '../widgets/feedback_sheet.dart';
import '../utils/media_image.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../widgets/widgets.dart';
import 'edit_profile_page.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onLogout;
  const SettingsPage({super.key, this.onLogout});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Entrance animations should play ONCE on open. After they finish we freeze
  // the page to static widgets so toggling a switch (which calls setState)
  // never re-runs the slide-in — that was making the whole screen jump.
  bool _animated = false;

  // Futures for the Primary SOS Contact card. They were created inline in
  // build(), so every setState (theme toggles, switches, animations) re-ran
  // the SharedPreferences lookup AND the Firestore contacts query.
  Future<String?>? _primaryContactPrefFuture;
  Future<List<dynamic>>? _emergencyContactsFuture;

  @override
  void initState() {
    super.initState();
    _reloadPrimaryContactCard();
    _toggles['Background Location'] = LocationService.instance.isTracking;
    _loadToggles();
    // Longest stagger (~620ms) + 450ms animation + buffer.
    Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _animated = true);
    });
  }

  /// (Re)fetches the data behind the Primary SOS Contact card. Called once on
  /// open and again after returning from the contact-picker page.
  void _reloadPrimaryContactCard() {
    _primaryContactPrefFuture = SharedPreferences.getInstance()
        .then((p) => p.getString(PrimarySosContactPage.prefKey));
    _emergencyContactsFuture =
        AppFirestoreService.instance.getEmergencyContacts();
  }

  /// Plays a one-shot slide-up + fade the first time the page builds; once
  /// [_animated] flips true it returns the child as-is, so a toggle's setState
  /// can never re-trigger an entrance (the cause of the whole-screen jump).
  /// Self-contained (no SlideUpFade) so it never re-animates on rebuild.
  Widget _intro({required Widget child, Duration delay = Duration.zero}) {
    if (_animated) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 22), child: c),
      ),
      child: child,
    );
  }

  String _prefKey(String k) =>
      'setting_${k.toLowerCase().replaceAll(' ', '_')}';

  /// Loads saved toggle states so they persist across app restarts, and applies
  /// the sensor-driven ones (Shake / Crash) to the live SensorService.
  Future<void> _loadToggles() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final key in _toggles.keys.toList()) {
        if (key == 'Background Location') continue; // driven by LocationService
        final saved = prefs.getBool(_prefKey(key));
        if (saved != null) _toggles[key] = saved;
      }
    });
    SensorService.instance.shakeEnabled = _toggles['Shake to SOS'] ?? true;
    SensorService.instance.crashEnabled = _toggles['Crash Detection'] ?? true;
  }

  /// Applies a toggle and returns the value that should actually be shown.
  /// (Background Location stays OFF if permission is denied.) Crucially this
  /// does NOT call the page's setState — only the individual [_ToggleTile]
  /// rebuilds, so the whole screen stays perfectly still (no jump/vibrate).
  Future<bool> _handleToggle(String key, bool v) async {
    if (key == 'Background Location') {
      if (v) {
        final errorMsg = await LocationService.instance.requestPermission();
        if (errorMsg == null) {
          LocationService.instance.startTracking();
          _toggles[key] = true;
          return true;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: C.accent,
              behavior: SnackBarBehavior.floating,
              content: Text(errorMsg),
            ),
          );
        }
        _toggles[key] = false;
        return false;
      }
      LocationService.instance.stopTracking();
      _toggles[key] = false;
      return false;
    }
    _toggles[key] = v;
    await _saveToggle(key, v);
    return v;
  }

  /// Persists a toggle and applies it live where it controls real behaviour.
  Future<void> _saveToggle(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(key), v);
    if (key == 'Shake to SOS') SensorService.instance.shakeEnabled = v;
    if (key == 'Crash Detection') SensorService.instance.crashEnabled = v;
    // Keep the NATIVE background detector's copy of these toggles in sync.
    if (key == 'Shake to SOS' || key == 'Crash Detection') {
      await BackgroundSosService.syncNativeSettings();
    }
    // Always-on protection: start/stop the "location"-type foreground service so
    // shake/crash fire an SOS even when the app is fully closed. This runs from
    // an explicit foreground tap (the safest way on Android 12+), start() is
    // fully guarded, and a crash-recovery flag means that even if an aggressive
    // OEM rejects it, the app self-heals on the next launch instead of looping.
    if (key == 'Background Protection') {
      if (v) {
        // The NATIVE detector is what actually catches a shake/crash while the
        // app is closed (a Flutter background isolate can't read the
        // accelerometer reliably then). Ask for the battery exemption first so
        // the OS doesn't doze it.
        await BackgroundSosService.requestBatteryExemption(force: true);
        await BackgroundSosService.startNativeDetector();
        // On Xiaomi/Oppo/Vivo/Huawei, open the Autostart page so the service
        // survives app-close — the user flips SmartSafe on there. No-op on stock.
        await BackgroundSosService.openAutoStartSettings();
        // On MIUI, the crash/shake alert can only POP THE APP OPEN by itself if
        // "Display pop-up windows while running in background" + "Show on lock
        // screen" are granted. Guide the user to that screen.
        if (mounted) await _showBgPopupGuide();
      } else {
        await BackgroundSosService.stopNativeDetector();
        await BackgroundSosService.stop();
      }
    }
  }

  /// One-time guide to the MIUI/OEM permissions that let the app auto-open on a
  /// detected crash/shake. Optional but strongly recommended.
  Future<void> _showBgPopupGuide() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: C.border),
        ),
        icon: Icon(Icons.open_in_new_rounded, color: C.accent, size: 34),
        title: Text('One more step',
            style: TextStyle(
                color: C.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'For SmartSafe to OPEN BY ITSELF on a crash or shake (even on the lock '
          'screen), turn ON these in the next screen:\n\n'
          '•  Display pop-up windows while running in background\n'
          '•  Show on lock screen\n\n'
          'Without them, you\'ll get a notification to tap instead.',
          style: TextStyle(color: C.textMuted, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: C.accent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              BackgroundSosService.openBgPopupPermission();
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  final Map<String, bool> _toggles = {
    'Shake to SOS': true,
    'Crash Detection': true,
    // OFF by default, opt-in only. This is the always-on foreground service that
    // lets SHAKE and CRASH detection fire an SOS while the app is fully closed.
    // Auto-starting it after login kills the app on MIUI/Xiaomi (seen on a real
    // device), so the user turns it on here deliberately. In-app shake/crash SOS
    // works regardless, with no service.
    'Background Protection': false,
    'SMS Offline Backup': true,
    'Silent SOS Mode': false,
    'Night Travel Alerts': true,
    'Auto-Call Police': false,
    'Background Location': true,
  };

  final Map<String, Color> _toggleColors = {
    'Shake to SOS': C.accent,
    'Crash Detection': C.warning,
    'Background Protection': C.success,
    'SMS Offline Backup': C.accent,
    'Silent SOS Mode': C.accent,
    'Night Travel Alerts': C.accent,
    'Auto-Call Police': C.accent,
    'Background Location': C.success,
  };

  final Map<String, IconData> _toggleIcons = {
    'Shake to SOS': Icons.vibration_rounded,
    'Crash Detection': Icons.car_crash_rounded,
    'Background Protection': Icons.shield_moon_rounded,
    'SMS Offline Backup': Icons.sms_rounded,
    'Silent SOS Mode': Icons.volume_off_rounded,
    'Night Travel Alerts': Icons.nightlight_round,
    'Auto-Call Police': Icons.local_police_rounded,
    'Background Location': Icons.location_on_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: SingleChildScrollView(
              padding: responsiveScrollPadding(context, horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _intro(
                    child: Row(
                      children: [
                        if (Navigator.canPop(context)) ...[
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Icon(Icons.arrow_back_ios_new_rounded,
                                color: C.textPrimary, size: 18),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text('Settings',
                            style: TextStyle(
                              color: C.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Profile card — live from Firestore / auth
                  _intro(
                    delay: const Duration(milliseconds: 80),
                    child: StreamBuilder<UserProfile?>(
                      stream: UserProfileService.instance.profileStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return DCard(
                            color: C.bg2,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                    color: C.accent, strokeWidth: 2),
                              ),
                            ),
                          );
                        }

                        final user = FirebaseAuth.instance.currentUser;
                        final profile = snapshot.data ??
                            (user != null
                                ? UserProfile.fromAuthUser(user)
                                : null);

                        if (profile == null) {
                          return const SizedBox.shrink();
                        }

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              final updated = await Navigator.push<bool>(
                                context,
                                darkRoute(EditProfilePage(profile: profile)),
                              );
                              if (updated == true && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: C.accent,
                                    behavior: SnackBarBehavior.floating,
                                    content: const Text(
                                      'Profile updated successfully',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: DCard(
                              color: C.bg2,
                              child: Row(
                                children: [
                                  Builder(builder: (_) {
                                    final photo =
                                        mediaImageProvider(profile.photoUrl);
                                    return Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: photo == null
                                            ? AppColors.sosGradient
                                            : null,
                                        image: photo != null
                                            ? DecorationImage(
                                                image: photo, fit: BoxFit.cover)
                                            : null,
                                      ),
                                      child: photo != null
                                          ? null
                                          : Center(
                                              child: Text(
                                                profile.initials,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                    );
                                  }),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          profile.name.isNotEmpty
                                              ? profile.name
                                              : 'Your Profile',
                                          style: TextStyle(
                                            color: C.textPrimary,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (profile.email.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            profile.email,
                                            style: TextStyle(
                                                color: C.textMuted, fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (profile.phone.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            profile.phone,
                                            style: TextStyle(
                                                color: C.textMuted, fontSize: 12),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            StatusBadge(
                                                label: 'Protected',
                                                color: C.success),
                                            if (profile.isAdmin) ...[
                                              const SizedBox(width: 8),
                                              StatusBadge(
                                                  label: 'Admin', color: C.accent),
                                            ] else ...[
                                              const SizedBox(width: 8),
                                              StatusBadge(
                                                label: UserRoles.user
                                                    .toUpperCase(),
                                                color: C.accent,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.edit_rounded,
                                      color: C.accent, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Premium subscription card ──────────────────────────
                  _intro(
                    delay: const Duration(milliseconds: 90),
                    child: StreamBuilder<SubscriptionInfo>(
                      stream: SubscriptionService.instance.subscriptionInfoStream,
                      initialData: SubscriptionService.instance.currentInfo,
                      builder: (context, snap) {
                        final info = snap.data ?? SubscriptionInfo.free;
                        final isPremium =
                            info.isActive && info.plan == PlanType.premium;

                        if (isPremium) {
                          // Premium user — show "Manage Subscription" entry.
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                darkRoute(
                                    const SubscriptionManagementScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: C.bg2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: C.border.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: C.accent.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.workspace_premium_rounded,
                                      color: C.accent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Manage Subscription',
                                          style: TextStyle(
                                            color: C.textPrimary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Premium active',
                                          style: TextStyle(
                                            color: C.accent,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      color: C.textMuted, size: 16),
                                ],
                              ),
                            ),
                          );
                        }

                        // Free user — show upgrade card.
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              darkRoute(const PaywallScreen()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  C.accent.withValues(alpha: 0.2),
                                  C.accent.withValues(alpha: 0.05),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: C.accent.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: C.accent.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.workspace_premium_rounded,
                                    color: C.accent,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Upgrade to Premium',
                                        style: TextStyle(
                                          color: C.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Unlock crash detection, live tracking, unlimited contacts & more',
                                        style: TextStyle(
                                          color: C.textMuted,
                                          fontSize: 12,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios_rounded,
                                    color: C.accent, size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  _intro(
                    delay: const Duration(milliseconds: 100),
                    child: StreamBuilder(
                      stream: AppFirestoreService.instance.watchMySosHistory(),
                      builder: (context, snap) {
                        final count = snap.data?.length ?? 0;
                        return GestureDetector(
                          onTap: () => Navigator.push(
                              context, darkRoute(const MySosHistoryPage())),
                          child: DCard(
                            color: C.bg2,
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: C.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child:
                                      Icon(Icons.history_rounded, color: C.accent),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('My SOS History',
                                          style: TextStyle(
                                              color: C.textPrimary,
                                              fontWeight: FontWeight.w700)),
                                      Text(
                                        count > 0
                                            ? 'You pressed SOS $count times. View the date and time.'
                                            : 'No SOS history yet',
                                        style: TextStyle(
                                            color: C.textMuted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded,
                                    color: C.textMuted),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Primary SOS Contact ──────────────────────────────────
                  _intro(
                    delay: const Duration(milliseconds: 110),
                    child: FutureBuilder<String?>(
                      future: _primaryContactPrefFuture,
                      builder: (context, prefSnap) {
                        final selectedId = prefSnap.data;
                        return FutureBuilder<List<dynamic>>(
                          future: _emergencyContactsFuture,
                          builder: (context, contactSnap) {
                            // Find the selected contact name if any
                            String subtitle = 'All contacts alerted (tap to set one)';
                            if (selectedId != null &&
                                contactSnap.hasData &&
                                contactSnap.data!.isNotEmpty) {
                              final match = contactSnap.data!.cast<dynamic>().where(
                                  (c) => c.id == selectedId);
                              if (match.isNotEmpty) {
                                subtitle = '${match.first.name}  ·  ${match.first.phone}';
                              }
                            }
                            return GestureDetector(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  darkRoute(const PrimarySosContactPage()),
                                );
                                // Rebuild to reflect new selection
                                if (context.mounted) {
                                  setState(_reloadPrimaryContactCard);
                                }
                              },
                              child: DCard(
                                color: C.bg2,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            C.accent.withValues(alpha: 0.3),
                                            C.accentLight.withValues(alpha: 0.12),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.star_rounded,
                                          color: C.accent, size: 20),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Primary SOS Contact',
                                            style: TextStyle(
                                              color: C.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitle,
                                            style: TextStyle(
                                                color: C.textMuted, fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded,
                                        color: C.textMuted),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Theme Toggle Card
                  _intro(
                    delay: const Duration(milliseconds: 120),
                    child: const SectionHeader(title: 'Theme Settings'),
                  ),
                  const SizedBox(height: 12),
                  _intro(
                    delay: const Duration(milliseconds: 160),
                    child: DCard(
                      color: C.bg2,
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.isDark
                                  ? C.accent.withValues(alpha: 0.15)
                                  : C.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              AppTheme.isDark
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              color: AppTheme.isDark ? C.accent : C.warning,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppTheme.isDark
                                  ? 'Dark Luxury Active'
                                  : 'Light Premium Active',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Switch(
                            // ON = dark (intuitive). Sets + persists the choice.
                            value: AppTheme.isDark,
                            onChanged: (v) {
                              AppTheme.setUserAppMode(
                                  v ? ThemeMode.dark : ThemeMode.light);
                              setState(() {});
                            },
                            activeThumbColor: C.accent,
                            activeTrackColor: C.accent.withValues(alpha: 0.3),
                            inactiveThumbColor: C.warning,
                            inactiveTrackColor: C.warning.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Safety Toggles
                  _intro(
                    delay: const Duration(milliseconds: 200),
                    child: const SectionHeader(title: 'Safety Settings'),
                  ),
                  const SizedBox(height: 16),
                  ..._toggles.entries.toList().asMap().entries.map((e) {
                    final idx = e.key;
                    final key = e.value.key;
                    return _intro(
                      delay: Duration(milliseconds: 240 + idx * 40),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        // Self-contained tile: toggling it rebuilds ONLY this
                        // tile (not the page), so the screen never jumps.
                        child: _ToggleTile(
                          label: key,
                          initialValue: _toggles[key]!,
                          color: _toggleColors[key]!,
                          icon: _toggleIcons[key]!,
                          onChanged: (v) => _handleToggle(key, v),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),

                  // Emergency numbers
                  _intro(
                    delay: const Duration(milliseconds: 500),
                    child: const SectionHeader(title: 'Emergency Numbers'),
                  ),
                  const SizedBox(height: 12),
                  _intro(
                    delay: const Duration(milliseconds: 540),
                    child: DCard(
                      color: C.bg2,
                      child: Row(
                        children: [
                          _EmergencyNum('1122', 'Rescue', C.accent),
                          const SizedBox(width: 8),
                          _EmergencyNum('15', 'Police', C.accent),
                          const SizedBox(width: 8),
                          _EmergencyNum('115', 'Edhi', C.success),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // About
                  _intro(
                    delay: const Duration(milliseconds: 580),
                    child: DCard(
                      color: C.bg2,
                      child: Column(
                        children: [
                          const _AboutRow(
                              'Version', '1.0.0', Icons.info_outline_rounded),
                          const SizedBox(height: 12),
                          _AboutRow('Privacy Policy', 'View',
                              Icons.privacy_tip_rounded,
                              onTap: () => Navigator.push(context,
                                  darkRoute(const PrivacyPolicyPage()))),
                          const SizedBox(height: 12),
                          _AboutRow('Send Feedback', 'Rate us',
                              Icons.star_outline_rounded,
                              onTap: () => showFeedbackSheet(context)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Account — password reset
                  _intro(
                    delay: const Duration(milliseconds: 600),
                    child: const SectionHeader(title: 'Account'),
                  ),
                  const SizedBox(height: 12),
                  _intro(
                    delay: const Duration(milliseconds: 610),
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        darkRoute(ForgotPasswordPage(
                            onBack: () => Navigator.pop(context))),
                      ),
                      child: DCard(
                        color: C.bg2,
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: C.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.lock_reset_rounded,
                                  color: C.accent, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Change / Forgot Password',
                                    style: TextStyle(
                                      color: C.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Reset your password via email OTP',
                                    style: TextStyle(
                                        color: C.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: C.textMuted, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sign out
                  _intro(
                    delay: const Duration(milliseconds: 620),
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: C.bg2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: C.border),
                            ),
                            title: Text(
                              'Sign Out',
                              style: TextStyle(
                                  color: C.textPrimary, fontWeight: FontWeight.w700),
                            ),
                            content: Text(
                              'Are you sure you want to sign out?',
                              style: TextStyle(color: C.textMuted),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Cancel',
                                    style: TextStyle(color: C.textMuted)),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onLogout?.call();
                                },
                                child: Text(
                                  'Sign Out',
                                  style: TextStyle(
                                      color: C.accent,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: C.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: C.accent.withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.logout_rounded,
                                  color: C.accent, size: 20),
                              const SizedBox(width: 8),
                              Text('Sign Out',
                                  style: TextStyle(
                                    color: C.accent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A safety switch that owns its own state. Toggling it rebuilds ONLY this
/// widget — never the whole Settings page — so the screen stays perfectly
/// still (fixes the "whole page jumps/vibrates on toggle" bug). [onChanged]
/// returns the value that should actually be shown (e.g. Background Location
/// stays OFF when permission is denied).
class _ToggleTile extends StatefulWidget {
  final String label;
  final bool initialValue;
  final Color color;
  final IconData icon;
  final Future<bool> Function(bool) onChanged;

  const _ToggleTile({
    required this.label,
    required this.initialValue,
    required this.color,
    required this.icon,
    required this.onChanged,
  });

  @override
  State<_ToggleTile> createState() => _ToggleTileState();
}

class _ToggleTileState extends State<_ToggleTile> {
  late bool _val = widget.initialValue;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _ToggleTile old) {
    super.didUpdateWidget(old);
    // Sync when the parent loads saved values from prefs after first build.
    if (old.initialValue != widget.initialValue &&
        widget.initialValue != _val) {
      _val = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return DCard(
      color: C.bg2,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _val ? color.withValues(alpha: 0.15) : C.bg3,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon,
                color: _val ? color : C.textMuted, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(widget.label,
                style: TextStyle(
                  color: _val ? C.textPrimary : C.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                )),
          ),
          Switch(
            value: _val,
            onChanged: _busy
                ? null
                : (v) async {
                    setState(() => _busy = true);
                    final resolved = await widget.onChanged(v);
                    if (mounted) {
                      setState(() {
                        _val = resolved;
                        _busy = false;
                      });
                    }
                  },
            activeThumbColor: color,
            activeTrackColor: color.withValues(alpha: 0.3),
            inactiveThumbColor: C.textMuted,
            inactiveTrackColor: C.border,
          ),
        ],
      ),
    );
  }
}

class _EmergencyNum extends StatefulWidget {
  final String number;
  final String label;
  final Color color;

  const _EmergencyNum(this.number, this.label, this.color);

  @override
  State<_EmergencyNum> createState() => _EmergencyNumState();
}

class _EmergencyNumState extends State<_EmergencyNum> {
  bool _pressed = false;

  Future<void> _handleTap() async {
    HapticFeedback.selectionClick();
    // Confirm before dialing — a stray tap must not instantly call an
    // emergency helpline.
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Call ${widget.label}?',
                style: TextStyle(color: C.textPrimary)),
            content: Text(
              'This will dial ${widget.number} now.',
              style: TextStyle(color: C.textMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyle(color: C.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Call',
                    style: TextStyle(
                        color: widget.color, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    HapticFeedback.mediumImpact();
    try {
      await FlutterPhoneDirectCaller.callNumber(widget.number);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: _pressed ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: widget.color.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(Icons.phone_rounded, color: widget.color, size: 20),
                const SizedBox(height: 6),
                Text(widget.number,
                    style: TextStyle(
                        color: widget.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                Text(widget.label,
                    style: TextStyle(color: C.textMuted, fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _AboutRow(this.label, this.value, this.icon, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, color: C.textMuted, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: C.textMuted, fontSize: 13)),
          const Spacer(),
          Text(value, style: TextStyle(color: C.textMuted, fontSize: 12)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: C.textMuted, size: 18),
        ],
      ),
    );
  }
}
