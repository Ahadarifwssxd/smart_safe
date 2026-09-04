import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bootstrap/app_bootstrap.dart';
import 'theme/colors.dart';
import 'navigation/dark_route.dart';
import 'pages/01_home_page.dart';
import 'pages/02_alert_page.dart';
import 'pages/chats_page.dart';
import 'pages/04_map_page.dart';
import 'pages/08_notifications_page.dart';
import 'pages/09_settings_page.dart';
import 'pages/03_contacts_page.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'services/sim_sos_service.dart';
import 'pages/23_login_page.dart';
import 'pages/24_signup_page.dart';
import 'pages/25_forgot_password_page.dart';
import 'pages/phone_verify_gate_page.dart';
import 'SplashScreen/splash_screen.dart';
import 'chatbot/chatbot_overlay.dart';
import 'widgets/community_sos_watcher.dart';
import 'services/auth_service.dart';
import 'services/app_firestore_service.dart';
import 'services/presence_service.dart';
import 'services/push_service.dart';
import 'services/live_tracking_service.dart';
import 'services/page_content_service.dart';
import 'chatbot/services/chatbot_faq_service.dart';
import 'models/user_roles.dart';
import 'package:provider/provider.dart';
import 'Dashboard/controllers/menu_app_controller.dart';
import 'Dashboard/screens/main/main_screen.dart';
import 'Dashboard/services/firebase_service.dart' as db;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/location_service.dart';
import 'services/local_notification_service.dart';
import 'services/sensor_service.dart';
import 'services/background_sos_service.dart';
import 'services/subscription_service.dart';
import 'pages/06_crash_detection_page.dart';

/// FCM background/terminated-app handler. SOS pushes carry a `notification`
/// payload, so Android displays them in the tray automatically even when the
/// app is fully closed — this handler just guarantees the messaging isolate is
/// wired (and lets data-only messages be processed) so no push is dropped.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No extra work needed for notification-payload messages; the OS shows them.
}

class UserLaunchState {
  static bool? isAdmin;
  static bool? phoneVerified;
  static bool loaded = false;

  static Future<void> loadForUser(User user) async {
    // 1. Try loading cached values first from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      isAdmin = prefs.getBool('cached_is_admin_${user.uid}');
      phoneVerified = prefs.getBool('cached_phone_verified_${user.uid}');
      if (isAdmin != null) {
        loaded = true;
      }
    } catch (_) {}

    // 2. Fetch fresh profile from Firestore with a short timeout
    try {
      final profile = await db.FirebaseService.instance
          .getUserProfile(user.uid)
          .timeout(const Duration(milliseconds: 1500));
      if (profile != null) {
        final role = profile['role']?.toString();
        isAdmin = (profile['isAdmin'] == true || UserRoles.isAdminRole(role)) ||
            user.email?.trim().toLowerCase() == 'donnaevo073@gmail.com';
        phoneVerified = profile['phoneVerified'] == true;
        loaded = true;

        // Cache the fresh values
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('cached_is_admin_${user.uid}', isAdmin!);
        await prefs.setBool('cached_phone_verified_${user.uid}', phoneVerified!);
      } else {
        // Fallback for new user or if profile doesn't exist
        if (isAdmin == null) {
          isAdmin = user.email?.trim().toLowerCase() == 'donnaevo073@gmail.com';
          phoneVerified = false;
          loaded = true;
        }
      }
    } catch (e) {
      debugPrint('[UserLaunchState] Profile pre-fetch failed/timed out: $e');
      // If we don't have cached values yet, set fallback values so we don't block
      if (isAdmin == null) {
        isAdmin = user.email?.trim().toLowerCase() == 'donnaevo073@gmail.com';
        phoneVerified = true; // Default to true on timeout/offline to not block gate
        loaded = true;
      }
    }
  }
}

Future<void> _initializeApp() async {
  // SELF-HEAL + FIREBASE IN PARALLEL: the background-service recovery used to
  // run BEFORE Firebase init (serially), adding up to 2s to every cold start.
  // It only reads a flag + stops a service — it has no Firebase dependency —
  // so both now start at the same instant and we wait for whichever is slower
  // (max instead of sum).
  final selfHeal = !kIsWeb
      ? BackgroundSosService.recoverIfPreviousStartCrashed()
          .timeout(const Duration(seconds: 2)).catchError((_) => false)
      : Future<bool>.value(false);

  // Firebase is core, but even a hiccup must not leave a black screen.
  final firebaseInit = AppBootstrap.ensureFirebase().catchError((e) {
    debugPrint('[main] Firebase init failed: $e');
  });

  await Future.wait([firebaseInit, selfHeal]);
  AppBootstrap.scheduleBackgroundSeeding();

  // If a user is already logged in, pre-fetch/load their status in parallel!
  final user = FirebaseAuth.instance.currentUser;
  Future<void>? userLoadFuture;
  if (user != null) {
    userLoadFuture = UserLaunchState.loadForUser(user);
  }

  // Start non-critical service initializations in parallel in the background (unawaited)
  unawaited(_initializeNonCriticalServices());

  // Warm up the Google Sign-In engine in the background while the login screen
  // is loading, so the first "Continue with Google" tap is instant instead of
  // paying the one-time initialization cost. Only needed when nobody's logged in.
  if (user == null) {
    unawaited(AuthService.instance.warmUpGoogleSignIn());
  }

  // Start listening for admin-edited page content (headings, hero copy, button
  // labels) so every DynText across the app shows live values from the dashboard.
  try {
    PageContentService.instance.start();
  } catch (e) {
    debugPrint('[main] PageContent listener failed: $e');
  }
  // Admin-managed chatbot FAQ (dashboard-editable answers + suggestions).
  try {
    ChatbotFaqService.instance.start();
  } catch (e) {
    debugPrint('[main] Chatbot FAQ listener failed: $e');
  }

  // Register the FCM handler for pushes that arrive while the app is
  // backgrounded or fully closed, so Community-SOS alerts are never dropped.
  if (!kIsWeb) {
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[main] FCM bg handler registration failed: $e');
    }
  }

  // Await only the critical user status load before completing this future (which the splash screen awaits)
  if (userLoadFuture != null) {
    await userLoadFuture;
  }
}

Future<void> _initializeNonCriticalServices() async {
  await Future.wait([
    LocationService.instance.init().timeout(const Duration(seconds: 6)).catchError((e) {
      debugPrint('[main] Location init skipped: $e');
    }),
    LocalNotificationService.instance
        .init()
        .timeout(const Duration(seconds: 6))
        .catchError((e) {
      debugPrint('[main] Notification init skipped: $e');
    }),
    () async {
      if (!kIsWeb) {
        try {
          await BackgroundSosService.initialize()
              .timeout(const Duration(seconds: 6));
          // Re-arm the NATIVE shake/crash detector if the user has protection on.
          // It's what actually catches events once the app is closed, and it must
          // come back after an app restart or a reboot.
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getBool('setting_background_protection') == true) {
            await BackgroundSosService.startNativeDetector()
                .timeout(const Duration(seconds: 6));
          }
        } catch (e) {
          debugPrint('[main] Background SOS init skipped: $e');
        }
      }
    }(),
  ]);
}

void main() {
  // Wrap the ENTIRE app in a guarded zone so an uncaught async error from ANY
  // background service (push, presence, live tracking, foreground SOS, a
  // Firestore stream) is LOGGED instead of killing the process. Together with
  // the guarded inits below, this is what stops the app "opening once and then
  // never opening again" — nothing can bring the whole app down at launch.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Framework (build/layout) errors → log them, never hard-crash the app.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[FlutterError] ${details.exception}');
    };

    // Restore the user's saved light/dark choice before the first frame.
    unawaited(AppTheme.loadSavedTheme());

    // Trigger app initialization in the background immediately without blocking runApp
    final initFuture = _initializeApp();

    if (!kIsWeb) {
      try {
        await SystemChrome.setPreferredOrientations(
            [DeviceOrientation.portraitUp]);
      } catch (_) {}
    }

    runApp(SmartSafeApp(initFuture: initFuture));
  }, (error, stack) {
    // Last-resort catch for ANY uncaught async error anywhere in the app — log
    // it, never let it kill the process (a common "opens once, then never" cause).
    debugPrint('[UncaughtError] $error\n$stack');
  });
}

class SmartSafeApp extends StatelessWidget {
  final Future<void> initFuture;
  const SmartSafeApp({super.key, required this.initFuture});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeNotifier,
      builder: (context, mode, child) {
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: AppTheme.isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: C.nav,
          systemNavigationBarIconBrightness: AppTheme.isDark ? Brightness.light : Brightness.dark,
        ));
        
        return MaterialApp(
          title: 'SmartSafe',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          // Smooth, momentum-based scrolling on every page.
          scrollBehavior: const _SmoothScrollBehavior(),
          // Background color fills any gaps before routes render — prevents white flash
          color: C.bg,
          // Clamp text scaling so very large/small device font settings can't
          // break layouts — keeps the UI consistent on EVERY phone.
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.15,
            child: child!,
          ),
          home: SplashScreen(nextScreen: const MainShell(), initFuture: initFuture),
        );
      },
    );
  }
}

/// App-wide scroll behaviour: bouncing physics for a smooth, premium feel and
/// drag support across touch, mouse and trackpad.
class _SmoothScrollBehavior extends MaterialScrollBehavior {
  const _SmoothScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  // Tabs the user has opened at least once. We keep those pages ALIVE in an
  // IndexedStack so switching between them is INSTANT (no rebuild jank), while
  // still building each page lazily on first open (fast startup).
  final Set<int> _visited = {0};
  // Memoized tab pages for the current login. Rebuilding the list on every
  // setState created NEW widget instances each time, so IndexedStack rebuilt
  // EVERY visited page on every tab switch / theme tick.
  List<Widget>? _pagesForUid;
  String _authScreen = 'login'; // 'login', 'signup', 'forgot'
  bool? _isAdmin;
  bool? _phoneVerified;
  String? _lastUid;

  @override
  void initState() {
    super.initState();
    AppTheme.themeNotifier.addListener(_onThemeChanged);
    
    // Initialize SensorService for global shake and crash triggers
    SensorService.instance.onShakeSOSTrigger = () {
      debugPrint('MainShell: Shake triggered SOS!');
      _triggerSOS(kind: 'shake');
    };
    SensorService.instance.onCrashSOSTrigger = () {
      debugPrint('MainShell: Crash detected, navigating to Crash Detection warning screen!');
      // Navigate to Crash Detection page which has the countdown warning overlay
      Navigator.push(
          context, darkRoute(const CrashDetectionPage(autoStart: true)));
    };
    SensorService.instance.startListening();
    _applySensorSettings();

    // Crash-free "SOS without opening the app first": a persistent notification
    // in the shade that, when tapped, opens the app and fires an SOS. Post it,
    // listen for taps while the app is alive, and handle a cold launch from it.
    sosQuickTapSignal.addListener(_onQuickSosTap);
    // A crash detected while the app was CLOSED pops the app open via a
    // full-screen intent — land straight on the crash countdown, not Home.
    crashAlertSignal.addListener(_onCrashAlert);
    // The background shake/crash detector opens the app here so it can run the
    // real SOS (call + WhatsApp) that a background isolate can't.
    sosAutoSignal.addListener(_onAutoSos);
    // The NATIVE detector (SosSensorService) is what actually catches a shake or
    // crash while the app is closed — Flutter's background isolate can't read the
    // accelerometer reliably then. It notifies us here.
    if (!kIsWeb) {
      BackgroundSosService.listenForDetections((kind) {
        if (mounted) _dispatchAutoSos(kind);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await LocalNotificationService.instance.showQuickSosButton();
      // Cold launch straight from the native detector's full-screen alert.
      if (!kIsWeb) {
        final nativeKind = await BackgroundSosService.consumePendingSos();
        if (nativeKind != null && nativeKind.isNotEmpty) {
          if (mounted) _dispatchAutoSos(nativeKind);
          return;
        }
      }
      final autoKind =
          await LocalNotificationService.instance.launchedFromAutoSos();
      if (autoKind != null) {
        if (mounted) _dispatchAutoSos(autoKind);
        return;
      }
      if (await LocalNotificationService.instance.launchedFromCrashAlert()) {
        if (mounted) _onCrashAlert();
        return;
      }
      if (await LocalNotificationService.instance.launchedFromQuickSos()) {
        if (mounted) _triggerSOS(kind: 'sos');
      }
    });
  }

  void _onQuickSosTap() {
    if (mounted) _triggerSOS(kind: 'sos');
  }

  void _onCrashAlert() {
    if (!mounted) return;
    Navigator.push(
        context, darkRoute(const CrashDetectionPage(autoStart: true)));
  }

  void _onAutoSos() {
    final kind = sosAutoSignal.value;
    if (kind != null) {
      sosAutoSignal.value = null;
      _dispatchAutoSos(kind);
    }
  }

  /// The app was popped open by the background shake/crash detector. Run the
  /// real SOS from the foreground: a crash goes through the cancellable
  /// countdown (which dials Rescue 1122); a shake fires the SOS immediately
  /// (call → WhatsApp → SMS to the emergency contacts).
  void _dispatchAutoSos(String kind) {
    if (!mounted) return;
    LocalNotificationService.instance.cancelSosFullScreen();
    if (kind == 'crash') {
      Navigator.push(
          context, darkRoute(const CrashDetectionPage(autoStart: true)));
    } else {
      _triggerSOS(kind: 'shake');
    }
  }

  /// Runs once right after a user signs in: request location permission (SOS is
  /// location-based) and nudge users with no emergency contacts to add one.
  bool _afterLoginRan = false;
  Future<void> _afterLoginSetup() async {
    if (_afterLoginRan) return;
    _afterLoginRan = true;
    // 1. Location permission — needed for SOS live location + community nearby.
    try {
      await LocationService.instance.requestPermission();
    } catch (_) {}
    // 2. If the user has no emergency contacts, prompt them to add one (after a
    //    short delay so it doesn't fight the first frame / other dialogs).
    try {
      await Future.delayed(const Duration(milliseconds: 900));
      final hasContacts =
          await SimSosService.instance.hasEmergencyContacts();
      if (!mounted || hasContacts) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: C.bg2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: C.border),
          ),
          icon: Icon(Icons.group_add_rounded, color: C.accent, size: 40),
          title: Text('Add an emergency contact',
              style: TextStyle(
                  color: C.textPrimary, fontWeight: FontWeight.w700)),
          content: Text(
            'SOS sends your live location and a call/SMS to your emergency '
            'contacts — but you haven\'t added anyone yet. Add at least one '
            'person so help can reach you.',
            style: TextStyle(color: C.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later', style: TextStyle(color: C.textMuted)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: C.accent, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, darkRoute(const ContactsPage()));
              },
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Add Contact'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  /// Load cached admin/verification status for instant rendering
  Future<void> _loadCachedUserStatus(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedIsAdmin = prefs.getBool('cached_is_admin_$uid');
      final cachedPhoneVerified = prefs.getBool('cached_phone_verified_$uid');
      if (mounted && _lastUid == uid) {
        setState(() {
          _isAdmin = cachedIsAdmin;
          _phoneVerified = cachedPhoneVerified;
        });
      }
    } catch (_) {}
  }

  /// Applies the saved Shake/Crash toggle states so turning them OFF in Settings
  /// actually stops them firing — even before the Settings page is opened.
  Future<void> _applySensorSettings() async {
    final prefs = await SharedPreferences.getInstance();
    SensorService.instance.shakeEnabled =
        prefs.getBool('setting_shake_to_sos') ?? true;
    SensorService.instance.crashEnabled =
        prefs.getBool('setting_crash_detection') ?? true;
  }

  @override
  void dispose() {
    AppTheme.themeNotifier.removeListener(_onThemeChanged);
    sosQuickTapSignal.removeListener(_onQuickSosTap);
    crashAlertSignal.removeListener(_onCrashAlert);
    sosAutoSignal.removeListener(_onAutoSos);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _triggerSOS({String kind = 'sos'}) async {
    // SOS is useless without someone to alert. If the user has no emergency
    // contacts, don't fail silently — give them a clear choice: add a contact,
    // or call emergency services right now.
    final hasContacts =
        await SimSosService.instance.hasEmergencyContacts();
    if (!mounted) return;
    if (!hasContacts) {
      _showNoContactsDialog();
      return;
    }
    AppFirestoreService.instance.recordSosPress(
      source: kind == 'shake' ? 'shake_gesture' : 'home_sos_button',
      location: 'GPS acquiring…',
    );
    Navigator.push(context, darkRoute(AlertPage(kind: kind)));
  }

  /// No emergency contacts yet — offer to add one OR call emergency services now
  /// (so a real emergency still gets help).
  void _showNoContactsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: C.border),
        ),
        icon: Icon(Icons.contact_emergency_rounded, color: C.accent, size: 40),
        title: Text('No emergency contacts',
            style: TextStyle(
                color: C.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          "SOS sends your live location and a call/SMS to your emergency "
          "contacts — but you haven't added anyone yet. Add a contact, or call "
          "emergency services right now.",
          style: TextStyle(color: C.textMuted),
        ),
        actionsOverflowButtonSpacing: 6,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FlutterPhoneDirectCaller.callNumber('1122');
              } catch (_) {}
            },
            icon: Icon(Icons.call_rounded, color: C.success, size: 18),
            label: Text('Call 1122',
                style: TextStyle(
                    color: C.success, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: C.accent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, darkRoute(const ContactsPage()));
            },
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add Contact'),
          ),
        ],
      ),
    );
  }

  /// Locks the theme for the current surface (app = light, dashboard = dark).
  /// Deferred to post-frame so we never call setState during build.
  void _setTheme(ThemeMode mode) {
    if (AppTheme.themeNotifier.value == mode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppTheme.themeNotifier.value = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: C.bg,
            body: Center(child: CircularProgressIndicator(color: C.accent)),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          _setTheme(AppTheme.userAppMode); // login/signup = user's app theme
          PresenceService.instance.stopHeartbeat();
          _lastUid = null;
          _pagesForUid = null; // rebuild tabs for the next login session
          _isAdmin = null;
          _phoneVerified = null;
          _afterLoginRan = false; // re-run location + contacts prompt next login
          // Not logged in
          if (_authScreen == 'signup') {
            return SignupPage(
              onSignup: () {}, // Handled internally by SignupPage now
              onLogin: () => setState(() => _authScreen = 'login'),
            );
          } else if (_authScreen == 'forgot') {
            return ForgotPasswordPage(
              onBack: () => setState(() => _authScreen = 'login'),
            );
          } else {
            return LoginPage(
              onLogin: () {}, // Handled internally by LoginPage
              onSignup: () => setState(() => _authScreen = 'signup'),
              onForgot: () => setState(() => _authScreen = 'forgot'),
            );
          }
        }

        if (user.uid != _lastUid) {
          _lastUid = user.uid;
          if (UserLaunchState.loaded && UserLaunchState.isAdmin != null) {
            _isAdmin = UserLaunchState.isAdmin;
            _phoneVerified = UserLaunchState.phoneVerified;
          } else {
            _isAdmin = null;
            _phoneVerified = null;
            _loadCachedUserStatus(user.uid); // Load cached values first
          }
          
          // Re-run the (idempotent) seeders now that we're authenticated. The
          // launch-time pass runs before sign-in, and Firestore rules reject
          // writes from a signed-out client — so on a FRESH install the default
          // content (safety tips, guides, page copy) would otherwise stay empty
          // until the next app start.
          AppBootstrap.scheduleBackgroundSeeding();

          // Initialize subscription service (RevenueCat) for premium features.
          // Must be called AFTER Firebase Auth has a signed-in user.
          AppBootstrap.initSubscriptionService();

          // Right after login: ask for location (SOS needs it) and, if the user
          // has no emergency contacts yet, gently prompt them to add one — an
          // SOS is useless without someone to alert.
          _afterLoginSetup();

          PresenceService.instance.startHeartbeat();
          // Register this device for Community-SOS push notifications.
          PushService.instance.registerForUser(user.uid);
          // Broadcast location so this user can be FOUND as "nearby" when
          // someone raises a Community SOS (community-wide, fixes "0 help").
          LiveTrackingService().startPresence();
          // NOTE: we deliberately do NOT start the always-on foreground service
          // here. Starting it during app startup killed the app on MIUI/Xiaomi
          // (observed on a real device: it reached the login screen, then died
          // and wouldn't reopen). The service is now started ONLY from an
          // explicit foreground tap — the Home "Enable background protection"
          // card or the Settings toggle — which is the safest way to launch a
          // foreground service on Android 12+. After a device reboot the
          // service's own autoStartOnBoot re-arms it (and stops itself if the
          // user never opted in). This keeps every app launch crash-proof.
          //
          // Shake/crash while the app is OPEN is unaffected — that runs off
          // SensorService in MainShell.initState, with no service involved.
          db.FirebaseService.instance
              .getUserProfile(user.uid)
              .timeout(const Duration(seconds: 4))
              .then((profile) {
            if (mounted && _lastUid == user.uid) {
              final role = profile?['role']?.toString();
              final isAdmin = (profile != null &&
                      (profile['isAdmin'] == true || UserRoles.isAdminRole(role))) ||
                  user.email?.trim().toLowerCase() == 'donnaevo073@gmail.com';
              final phoneVerified = profile?['phoneVerified'] == true;
              
              setState(() {
                _isAdmin = isAdmin;
                _phoneVerified = phoneVerified;
              });
              
              // Cache these updated values for the next launch
              SharedPreferences.getInstance().then((prefs) {
                prefs.setBool('cached_is_admin_${user.uid}', isAdmin);
                prefs.setBool('cached_phone_verified_${user.uid}', phoneVerified);
              }).catchError((_) {});
            }
          }).catchError((err) {
            debugPrint('MainShell: getUserProfile timed out/failed: $err');
            if (mounted && _lastUid == user.uid && _isAdmin == null) {
              setState(() {
                _isAdmin = user.email?.trim().toLowerCase() == 'donnaevo073@gmail.com';
                _phoneVerified = true; // Fallback to true to let them use the app
              });
            }
          });
        }

        if (_isAdmin == null) {
          return Scaffold(
            backgroundColor: C.bg,
            body: Center(child: CircularProgressIndicator(color: C.accent)),
          );
        }

        if (_isAdmin == true) {
          // The admin dashboard is designed dark (indigo accents match the app).
          // The user app is light — so we lock the theme per surface.
          // (Heartbeat was already started in the login-change block above.)
          _setTheme(ThemeMode.dark);
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (context) => MenuAppController(),
              ),
            ],
            child: const MainScreen(initialAuthenticated: true),
          );
        }
        // The user app respects the user's saved light/dark choice.
        _setTheme(AppTheme.userAppMode);

        // Logged in (non-admin). Require a verified phone number first —
        // Google sign-ups and legacy accounts land here until they verify.
        if (_phoneVerified != true) {
          return PhoneVerifyGatePage(
            onVerified: () => setState(() => _phoneVerified = true),
            onLogout: () async {
              // Fire-and-forget cleanup so a slow network call can never block
              // the actual sign-out.
              unawaited(PresenceService.instance.goOffline().catchError((_) {}));
              unawaited(LiveTrackingService().stopPresence().catchError((_) {}));
              unawaited(SubscriptionService.instance.reset().catchError((_) {}));
              if (!kIsWeb) {
                unawaited(BackgroundSosService.stop().catchError((_) {}));
              }
              unawaited(
                  PushService.instance.unregister(user.uid).catchError((_) {}));
              try {
                await AuthService.instance.signOut();
              } catch (_) {}
              if (mounted) {
                setState(() {
                  _authScreen = 'login';
                  _tab = 0;
                });
              }
            },
          );
        }

        PresenceService.instance.startHeartbeat();
        // Build the tab pages ONCE per login (see _pagesForUid) — stable widget
        // instances mean IndexedStack skips rebuilding every visited tab.
        final pages = _pagesForUid ??= [
          HomePage(
            onSOSTap: _triggerSOS,
            onViewContacts: () =>
                Navigator.push(context, darkRoute(const ContactsPage())),
            // Notifications live at index 4 now (moved off the bottom bar to
            // the home header bell). Opening it keeps the exact same screen.
            onOpenNotifications: () => setState(() {
              _tab = 4;
              _visited.add(4);
            }),
          ),
          const ChatsPage(),
          const MapPage(),
          SettingsPage(onLogout: () async {
            // Sign out must ALWAYS work — so the presence/tracking/push cleanup
            // is fire-and-forget (a slow or failed network call could otherwise
            // hang before signOut() ever ran, which is why sign-out "did
            // nothing" from the app).
            unawaited(PresenceService.instance.goOffline().catchError((_) {}));
            unawaited(LiveTrackingService().stopPresence().catchError((_) {}));
            unawaited(SubscriptionService.instance.reset().catchError((_) {}));
            unawaited(PushService.instance.unregister(user.uid).catchError((_) {}));
            try {
              await AuthService.instance.signOut();
            } catch (_) {}
            // authStateChanges now emits null → the Login screen shows itself.
            if (mounted) {
              setState(() {
                _authScreen = 'login';
                _tab = 0;
              });
            }
          }),
          const NotificationsPage(),
        ];

    return CommunitySosWatcher(
      child: ChatBotOverlay(
      child: PopScope(
        // Back button: if we're not on Home, go to Home first; only on Home does
        // back try to leave the app, and then we ask to confirm (like WhatsApp).
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (_tab != 0) {
            setState(() => _tab = 0);
            return;
          }
          final leave = await _confirmExit();
          if (leave) SystemNavigator.pop();
        },
        child: Scaffold(
        backgroundColor: C.bg,
        body: ColoredBox(
          color: C.bg,
          // IndexedStack keeps visited tabs ALIVE so switching is INSTANT (no
          // rebuild/jank). Unvisited tabs render nothing until first opened.
          child: IndexedStack(
            index: _tab,
            children: List.generate(
              pages.length,
              (i) => _visited.contains(i)
                  ? pages[i]
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        bottomNavigationBar: _BottomNav(
          current: _tab,
          onTap: (i) => setState(() {
            _tab = i;
            _visited.add(i);
          }),
        ),
      ),
      ),
    ),
    );
      },
    );
  }

  /// WhatsApp-style "leave the app?" confirmation on the Home back press.
  Future<bool> _confirmExit() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: C.border),
        ),
        icon: Icon(Icons.exit_to_app_rounded, color: C.accent, size: 36),
        title: Text('Exit SmartSafe?',
            style: TextStyle(
                color: C.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Are you sure you want to close the app? Shake & crash SOS only work '
          'while SmartSafe is running.',
          style: TextStyle(color: C.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Stay', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: C.accent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}

class _BottomNav extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const _BottomNav({
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Notifications moved to the home-header bell, so it's no longer a tab.
    final items = [
      const _NavItem(Icons.home_rounded, 'Home'),
      const _NavItem(Icons.chat_bubble_rounded, 'Chats'),
      const _NavItem(Icons.location_on_rounded, 'Map'),
      const _NavItem(Icons.settings_rounded, 'Settings'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: C.border.withValues(alpha: 0.85)),
        boxShadow: AppTheme.cardShadow(),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final item = items[i];
              final isActive = current == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      // Modern solid-tint pill for the active tab.
                      color: isActive
                          ? C.accent.withValues(alpha: 0.14)
                          : null,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: isActive ? 1.12 : 1.0,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          child: Icon(
                            item.icon,
                            color: isActive ? C.accent : C.textMuted,
                            size: 26,
                            weight: 700,
                            grade: 200,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: isActive ? C.accent : C.textMuted,
                            fontSize: 11,
                            fontWeight:
                                isActive ? FontWeight.w800 : FontWeight.w600,
                          ),
                          child: Text(item.label),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

/// Short pre-SOS countdown for a SHAKE gesture (which can be accidental). Shows
/// a big cancellable timer; returns true if it runs out (send SOS), false if the
/// user cancels. Vibrates each second so it's felt even in a pocket.
class _SosCountdownDialog extends StatefulWidget {
  final int seconds;
  const _SosCountdownDialog({required this.seconds});

  @override
  State<_SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<_SosCountdownDialog> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        Navigator.of(context).pop(true); // time up → send SOS
      } else {
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: C.bg2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: C.red.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Shake SOS',
                style: TextStyle(
                    color: C.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Sending SOS to your contacts in…',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.textMuted, fontSize: 13)),
            const SizedBox(height: 18),
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: C.red.withValues(alpha: 0.15),
                border: Border.all(color: C.red, width: 3),
              ),
              child: Text('$_left',
                  style: TextStyle(
                      color: C.red,
                      fontSize: 44,
                      fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: C.textPrimary,
                      side: BorderSide(color: C.border),
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("I'm OK — Cancel",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Send now',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
