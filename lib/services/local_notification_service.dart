import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences flag the crash-countdown writes when the user taps the
/// "I'M OK — CANCEL" action on the crash notification. The background crash
/// detector ([BackgroundSosService]) polls this to abort the SOS. It lives at
/// top level because notification-action callbacks MUST be static/top-level
/// (they run in their own isolate when the app is closed).
const String kCrashCancelFlag = 'crash_cancel_requested';

/// The action id of the crash-cancel button.
const String kCrashCancelAction = 'cancel_crash';

/// Payload on the always-present "Tap to send SOS" notification. Tapping it
/// (which opens the app) trips [sosQuickTapSignal]; the app then fires an SOS —
/// a crash-free way to raise SOS from the notification shade WITHOUT opening the
/// app first, and with NO always-on foreground service.
const String kSosQuickPayload = 'sos_quick';

/// Bumped every time the "Tap to send SOS" notification is tapped while the app
/// is alive. MainShell listens and triggers the SOS flow. (Cold launches are
/// handled separately via getNotificationAppLaunchDetails.)
final ValueNotifier<int> sosQuickTapSignal = ValueNotifier<int>(0);

/// Payload on the crash-countdown notification. Its full-screen intent POPS THE
/// APP OPEN by itself after a detected road accident; the app then jumps
/// straight to the crash countdown screen instead of the home page.
const String kCrashAlertPayload = 'crash_alert';

/// Bumped when the crash notification opens the app (or is tapped).
final ValueNotifier<int> crashAlertSignal = ValueNotifier<int>(0);

/// Payload prefix for the auto-SOS full-screen alert fired by the BACKGROUND
/// detector. A phone call and WhatsApp can't be launched from a background
/// isolate (they need a foreground Activity), so instead of trying to dispatch
/// there, the detector pops the app open with this full-screen intent and the
/// app runs the real dispatch (call → WhatsApp → SMS). Value is 'sos_auto:shake'
/// or 'sos_auto:crash'.
const String kSosAutoPrefix = 'sos_auto:';

/// Carries the detected kind ('shake' | 'crash') when the auto-SOS alert opens
/// the app while it's alive. MainShell listens and dispatches.
final ValueNotifier<String?> sosAutoSignal = ValueNotifier<String?>(null);

/// Handles taps on notification action buttons — including from a background
/// isolate when the app is fully closed. On "I'M OK — CANCEL" it records the
/// cancel request so the crash detector aborts before alerting anyone.
@pragma('vm:entry-point')
void notificationActionHandler(NotificationResponse response) {
  if (response.actionId == kCrashCancelAction) {
    // This may run in a fresh background isolate — make sure plugins are wired.
    DartPluginRegistrant.ensureInitialized();
    SharedPreferences.getInstance()
        .then((p) => p.setBool(kCrashCancelFlag, true))
        .catchError((_) => false);
    return;
  }
  // Body tap on the "Tap to send SOS" notification → let the app raise SOS.
  if (response.payload == kSosQuickPayload) {
    sosQuickTapSignal.value++;
    return;
  }
  // The crash notification opened the app → show the countdown screen.
  if (response.payload == kCrashAlertPayload) {
    crashAlertSignal.value++;
    return;
  }
  // The auto-SOS alert (background shake/crash) opened the app → dispatch.
  final pl = response.payload ?? '';
  if (pl.startsWith(kSosAutoPrefix)) {
    sosAutoSignal.value = pl.substring(kSosAutoPrefix.length);
  }
}

/// LocalNotificationService
/// ─────────────────────────────────────────────────────────────────────────
/// Shows a REAL system notification on the user's own phone — e.g. when they
/// trigger SOS or cancel it. No backend / FCM needed; these are local
/// notifications fired by the app itself.
///
/// Works on Android (and iOS if built for it). Safe no-op on web.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const AndroidNotificationDetails _sosChannel =
      AndroidNotificationDetails(
    'sos_alerts',
    'SOS Alerts',
    channelDescription: 'Emergency SOS confirmations on your own device',
    importance: Importance.max,
    priority: Priority.high,
    color: Color(0xFFe63946),
    enableVibration: true,
    playSound: true,
    icon: '@mipmap/ic_launcher',
  );

  /// Call once at app startup (from main()).
  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(
        settings,
        // Handle taps on action buttons (e.g. crash "I'M OK — CANCEL") both in
        // the foreground and — via the @pragma entry point — when the app is
        // fully closed.
        onDidReceiveNotificationResponse: notificationActionHandler,
        onDidReceiveBackgroundNotificationResponse: notificationActionHandler,
      );

      // Android 13+ requires runtime permission to post notifications.
      final androidImpl =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      // Explicitly create the high-importance channel up front. FCM pushes that
      // arrive while the app is CLOSED are rendered by the system using this
      // channel id (set as the FCM default in AndroidManifest), so the channel
      // must already exist — it can't be created lazily on first show.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'sos_alerts',
          'SOS Alerts',
          description: 'Emergency SOS alerts — shown even when the app is closed',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      // Dedicated channel for the road-accident countdown (with a Cancel action).
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'crash_alerts',
          'Crash Detection',
          description:
              'Road-accident countdown — tap Cancel if it was a false alarm',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      _ready = true;
      debugPrint('[LocalNotif] Initialized');
    } catch (e) {
      debugPrint('[LocalNotif] init failed: $e');
    }
  }

  /// Show a notification immediately on this device.
  ///
  /// [fullScreen] makes it a maximum-urgency heads-up alert (like an incoming
  /// call) that pops OVER other apps and shows on the lock screen — used for
  /// SOS alerts so nobody misses them.
  Future<void> show({
    required String title,
    required String body,
    int id = 1001,
    bool fullScreen = false,
  }) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    try {
      final AndroidNotificationDetails android = fullScreen
          ? const AndroidNotificationDetails(
              'sos_alerts',
              'SOS Alerts',
              channelDescription:
                  'Emergency SOS alerts — shown even when the app is closed',
              importance: Importance.max,
              priority: Priority.max,
              color: Color(0xFFe63946),
              icon: '@mipmap/ic_launcher',
              fullScreenIntent: true,
              category: AndroidNotificationCategory.call,
              enableVibration: true,
              playSound: true,
            )
          : _sosChannel;
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(android: android),
      );
    } catch (e) {
      debugPrint('[LocalNotif] show failed: $e');
    }
  }

  /// Notification id for the always-present "Tap to send SOS" shortcut.
  static const int quickSosId = 8810;

  /// Posts a persistent (ongoing) notification in the shade with a one-tap SOS.
  /// It stays there so that, WITHOUT opening the app, the user can pull down the
  /// notification shade and tap it — the app opens and fires the SOS. This is a
  /// crash-free replacement for the always-on foreground service: it needs no
  /// background sensing, so it can never crash the app on aggressive OEMs.
  Future<void> showQuickSosButton() async {
    if (kIsWeb) return;
    if (!_ready) await init();
    try {
      const android = AndroidNotificationDetails(
        'sos_alerts',
        'SOS Alerts',
        channelDescription: 'One-tap SOS from the notification shade',
        importance: Importance.high,
        priority: Priority.high,
        color: Color(0xFFe63946),
        icon: '@mipmap/ic_launcher',
        ongoing: true, // can't be swiped away — always ready for an emergency
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        category: AndroidNotificationCategory.status,
      );
      await _plugin.show(
        quickSosId,
        '🆘 SmartSafe — Tap to send SOS',
        'Tap here anytime to open SmartSafe and alert your contacts.',
        const NotificationDetails(android: android),
        payload: kSosQuickPayload,
      );
    } catch (e) {
      debugPrint('[LocalNotif] quick SOS button failed: $e');
    }
  }

  /// Removes the quick-SOS notification (e.g. on logout).
  Future<void> cancelQuickSosButton() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(quickSosId);
    } catch (_) {}
  }

  /// Notification id for the auto-SOS full-screen alert.
  static const int autoSosId = 8811;

  /// Fired by the BACKGROUND detector on a shake/crash. Its full-screen intent
  /// pops the app open (over the lock screen, like an incoming call) so the app
  /// can place the call + WhatsApp, which a background isolate cannot do.
  Future<void> showSosFullScreen(String kind) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    try {
      final isCrash = kind == 'crash';
      final android = AndroidNotificationDetails(
        'sos_alerts',
        'SOS Alerts',
        channelDescription: 'Auto SOS from background shake/crash detection',
        importance: Importance.max,
        priority: Priority.max,
        color: const Color(0xFFe63946),
        icon: '@mipmap/ic_launcher',
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        ongoing: true,
        autoCancel: false,
        enableVibration: true,
        playSound: true,
      );
      await _plugin.show(
        autoSosId,
        isCrash
            ? '🚗 Crash detected — sending SOS'
            : '🆘 Shake SOS — alerting your contacts',
        'Opening SmartSafe to call and message your emergency contacts now…',
        NotificationDetails(android: android),
        payload: '$kSosAutoPrefix$kind',
      );
    } catch (e) {
      debugPrint('[LocalNotif] auto SOS full-screen failed: $e');
    }
  }

  Future<void> cancelSosFullScreen() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(autoSosId);
    } catch (_) {}
  }

  /// If the app was cold-launched by the auto-SOS alert, returns 'shake'/'crash'.
  Future<String?> launchedFromAutoSos() async {
    if (kIsWeb) return null;
    if (!_ready) await init();
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final pl = details?.notificationResponse?.payload ?? '';
      if (details?.didNotificationLaunchApp == true &&
          pl.startsWith(kSosAutoPrefix)) {
        return pl.substring(kSosAutoPrefix.length);
      }
    } catch (_) {}
    return null;
  }

  /// If the app was cold-launched by tapping the quick-SOS notification, returns
  /// true so the caller can raise an SOS right away.
  Future<bool> launchedFromQuickSos() async {
    if (kIsWeb) return false;
    if (!_ready) await init();
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp == true &&
          details?.notificationResponse?.payload == kSosQuickPayload;
    } catch (_) {
      return false;
    }
  }

  /// Notification id reserved for the crash-detection countdown.
  static const int crashCountdownId = 8802;

  /// Shows / refreshes the road-accident countdown notification. It carries an
  /// "I'M OK — CANCEL" action button that aborts the SOS. Call it once per
  /// second with the remaining seconds so the user sees a live countdown.
  ///
  /// `fullScreenIntent: true` + the "call" category make Android POP THE APP
  /// OPEN by itself on the first alert — even over the lock screen, like an
  /// incoming call — so a driver who has just crashed sees the countdown without
  /// having to find and open the app. `ongoing` + `onlyAlertOnce` keep it pinned
  /// and stop it buzzing every single second of the countdown.
  Future<void> showCrashCountdown(int secondsRemaining) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    try {
      const android = AndroidNotificationDetails(
        'crash_alerts',
        'Crash Detection',
        channelDescription:
            'Road-accident countdown — tap Cancel if it was a false alarm',
        importance: Importance.max,
        priority: Priority.max,
        color: Color(0xFFe63946),
        icon: '@mipmap/ic_launcher',
        fullScreenIntent: true,
        onlyAlertOnce: true,
        ongoing: true,
        autoCancel: false,
        // "call" is the category Android honours most reliably for a
        // full-screen intent — it launches the app over the lock screen.
        category: AndroidNotificationCategory.call,
        actions: [
          AndroidNotificationAction(
            kCrashCancelAction,
            "I'M OK — CANCEL",
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      );
      await _plugin.show(
        crashCountdownId,
        '🚗 Possible crash detected — are you OK?',
        'Alerting your contacts & Rescue 1122 in ${secondsRemaining}s. '
            'Tap "I\'M OK — CANCEL" if this was a false alarm.',
        const NotificationDetails(android: android),
        payload: kCrashAlertPayload,
      );
    } catch (e) {
      debugPrint('[LocalNotif] crash countdown failed: $e');
    }
  }

  /// True if the app was opened by the crash notification's full-screen intent,
  /// so the caller can jump straight to the crash countdown screen.
  Future<bool> launchedFromCrashAlert() async {
    if (kIsWeb) return false;
    if (!_ready) await init();
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp == true &&
          details?.notificationResponse?.payload == kCrashAlertPayload;
    } catch (_) {
      return false;
    }
  }

  /// Removes the crash-countdown notification (after cancel or after firing).
  Future<void> cancelCrashCountdown() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(crashCountdownId);
    } catch (e) {
      debugPrint('[LocalNotif] crash countdown cancel failed: $e');
    }
  }
}
