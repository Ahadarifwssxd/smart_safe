import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:smartsafe/chatbot/chatbot_overlay.dart';
import 'package:smartsafe/navigation/dark_route.dart';
import 'package:smartsafe/pages/01_home_page.dart';
import 'package:smartsafe/pages/02_alert_page.dart';
import 'package:smartsafe/pages/10_add_contact_page.dart';
import 'package:smartsafe/pages/chats_page.dart';
import 'package:smartsafe/pages/04_map_page.dart';
import 'package:smartsafe/pages/08_notifications_page.dart';
import 'package:smartsafe/pages/09_settings_page.dart';
import 'package:smartsafe/services/app_firestore_service.dart';
import 'package:smartsafe/services/auth_service.dart';
import 'package:smartsafe/services/sim_sos_service.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/theme/design_tokens.dart';

/// User mobile app tabs — opened from admin dashboard preview.
class UserAppShell extends StatefulWidget {
  const UserAppShell({super.key});

  @override
  State<UserAppShell> createState() => _UserAppShellState();
}

class _UserAppShellState extends State<UserAppShell> {
  int _tab = 0;

  Future<void> _triggerSOS() async {
    // Strong tactile confirmation the instant SOS is pressed — the app's most
    // important action should feel unmistakably real under the thumb.
    HapticFeedback.heavyImpact();

    // Guard: SOS is useless without emergency contacts. If none are saved,
    // guide the user to add one instead of opening a dispatch that can't reach
    // anybody. (Fast, cache-backed check — never blocks a real emergency.)
    final hasContacts = await SimSosService.instance.hasEmergencyContacts();
    if (!hasContacts) {
      if (mounted) _showNoContactsDialog();
      return;
    }

    // 1. Log the SOS event to Firestore (for dashboard tracking)
    AppFirestoreService.instance.recordSosPress(
      source: 'home_sos_button',
      location: 'GPS acquiring…',
    );

    // 2. Navigate to Alert page immediately so user sees feedback
    Navigator.push(context, darkRoute(const AlertPage()));

    // 3. Use phone's own SIM card — no Twilio, no API, no verification needed!
    //    Works directly on Android with user's own number.
    final result = await SimSosService.instance.triggerSos();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.summaryMessage,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          backgroundColor:
              result.hasError ? const Color(0xFFe63946) : const Color(0xFF2ecc71),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  /// Shown when SOS is pressed but the user has no emergency contacts — a clear,
  /// friendly prompt that takes them straight to add one.
  void _showNoContactsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.contact_emergency_rounded,
            color: AppColors.accent, size: 40),
        title: const Text('Add an emergency contact first'),
        content: const Text(
          'SOS sends your live location and a call/SMS to your emergency '
          'contacts — but you haven\'t added anyone yet. Add at least one '
          'person so help can reach you in an emergency.',
        ),
        actionsOverflowButtonSpacing: 6,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FlutterPhoneDirectCaller.callNumber('1122');
              } catch (_) {}
            },
            icon: const Icon(Icons.call_rounded,
                color: Color(0xFF22C55E), size: 18),
            label: const Text('Call 1122',
                style: TextStyle(color: Color(0xFF22C55E))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, darkRoute(const AddContactPage()));
            },
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add Contact'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        onSOSTap: _triggerSOS,
        // Notifications moved to the home-header bell (index 4 now), so it's no
        // longer a bottom tab.
        onOpenNotifications: () => setState(() => _tab = 4),
      ),
      const ChatsPage(),
      const MapPage(),
      SettingsPage(onLogout: () async {
        await AuthService.instance.signOut();
        if (mounted) Navigator.pop(context);
      }),
      const NotificationsPage(),
    ];

    return ChatBotOverlay(
      child: Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          backgroundColor: C.bg2,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SmartSafe',
                  style: TextStyle(
                      color: C.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 0.2)),
              Text('Protection Active',
                  style: TextStyle(
                      color: C.success, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: C.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
        ),
        bottomNavigationBar: _UserBottomNav(
          current: _tab,
          onTap: (i) {
            if (i != _tab) HapticFeedback.selectionClick();
            setState(() => _tab = i);
          },
        ),
      ),
    );
  }
}

class _UserBottomNav extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const _UserBottomNav({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Notifications live in the home-header bell now, not the bottom bar.
    const items = <Map<String, dynamic>>[
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.chat_bubble_rounded, 'label': 'Chats'},
      {'icon': Icons.location_on_rounded, 'label': 'Map'},
      {'icon': Icons.settings_rounded, 'label': 'Settings'},
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(DesignTokens.space12, 0, DesignTokens.space12, DesignTokens.space12),
      decoration: BoxDecoration(
        color: C.bg2.withValues(alpha: 0.8),
        borderRadius: DesignTokens.borderRadius24,
        border: Border.all(color: C.border.withValues(alpha: 0.6)),
        boxShadow: AppTheme.cardShadow(C.bg2),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          // LayoutBuilder gives the EXACT inner width, so the sliding pill
          // lines up perfectly under each item on every screen size.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / items.length;
              return Stack(
                children: [
                  // Sliding indicator pill
                  AnimatedPositioned(
                    duration: DesignTokens.durationNormal,
                    curve: Curves.easeOutCubic,
                    // Clamp so the pill never slides off when the notifications
                    // tab (index 4, opened from the header bell) is active.
                    left: itemWidth * current.clamp(0, items.length - 1),
                    width: itemWidth,
                    top: 8,
                    bottom: 8,
                    child: Center(
                      child: Container(
                        width: 48,
                        decoration: BoxDecoration(
                          color: C.accent.withValues(alpha: 0.15),
                          borderRadius: DesignTokens.borderRadius16,
                        ),
                      ),
                    ),
                  ),
                  // Nav items
                  Row(
                    children: List.generate(items.length, (i) {
                      final active = current == i;
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onTap(i),
                          // Smoothly tween icon scale + colour together so the
                          // transition glides instead of snapping.
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: active ? 1 : 0),
                            duration: DesignTokens.durationNormal,
                            curve: Curves.easeOutCubic,
                            builder: (context, t, _) => Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Transform.scale(
                                  scale: 1 + 0.15 * t,
                                  child: Icon(
                                    items[i]['icon'] as IconData,
                                    color: Color.lerp(
                                        C.textMuted, C.accent, t),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                ClipRect(
                                  child: Align(
                                    heightFactor: t,
                                    child: Opacity(
                                      opacity: t,
                                      child: Text(
                                        items[i]['label'] as String,
                                        style: DesignTokens.label.copyWith(
                                          color: C.accent,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
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
