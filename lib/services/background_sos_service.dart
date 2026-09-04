import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'local_notification_service.dart';
import 'sensor_service.dart';
import 'sim_sos_service.dart';

/// Keeps crash + shake SOS detection alive as an Android **foreground service**,
/// so an accident (or a deliberate 3× shake) can fire an SOS to the user's
/// emergency contacts EVEN WHEN THE APP IS FULLY CLOSED / SWIPED AWAY.
///
/// How it works: a persistent "protection active" notification keeps a
/// background isolate running. That isolate re-initialises Firebase, restores
/// the signed-in user (FirebaseAuth persists to disk), listens to the
/// accelerometer via [SensorService], and on a trigger calls the SAME
/// [SimSosService.triggerSos] dispatch the foreground app uses — so contacts get
/// the identical FCM push + SMS + WhatsApp, with no app UI needed.
///
/// ⚠️ REQUIRES REAL-DEVICE TESTING. Background/foreground-service behaviour
/// varies by Android version + OEM battery optimisation. Ask the user to grant
/// "Allow background activity" / disable battery optimisation for reliability.
class BackgroundSosService {
  BackgroundSosService._();

  static const _channelId = 'smartsafe_protection';
  static const _fgNotifId = 8801;

  /// Native bridge to open OEM (Xiaomi/Oppo/Vivo/Huawei) settings screens.
  static const MethodChannel _oemChannel = MethodChannel('smartsafe/oem');

  /// Opens the OEM "Autostart / background start" settings page with one tap so
  /// the user can allow SmartSafe to keep running when closed — the step MIUI &
  /// friends require for background SOS. Returns true if a screen opened (false
  /// on stock Android / unknown OEMs, where it isn't needed). Never throws.
  static Future<bool> openAutoStartSettings() async {
    try {
      final ok = await _oemChannel.invokeMethod<bool>('openAutoStart');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the app's permission editor so the user can turn on "Display pop-up
  /// windows while running in background" + "Show on lock screen" — the MIUI
  /// switches that let the crash/shake alert pop the app open by itself. Returns
  /// true if a screen opened. Never throws.
  static Future<bool> openBgPopupPermission() async {
    try {
      final ok = await _oemChannel.invokeMethod<bool>('openBgPopupPermission');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── NATIVE shake/crash detector ────────────────────────────────────────────
  // Flutter's background isolate does NOT reliably receive accelerometer events
  // once the app is closed, so detection never fired there. The real detector is
  // a native Android foreground service (SosSensorService) that holds a partial
  // wake lock and listens to the accelerometer itself. It raises a full-screen
  // notification, which brings the app up to run the actual SOS.

  /// Crash sensitivity label → m/s² threshold (High ≈ 2.2G, Medium ≈ 3G, Low 4G).
  static double _thresholdFor(String? sensitivity) {
    switch (sensitivity) {
      case 'High':
        return 22.0;
      case 'Low':
        return 40.0;
      default:
        return 30.0;
    }
  }

  /// Reads the user's toggles and starts the NATIVE detector. Returns true if it
  /// started. Fully guarded — a failure never takes the app down.
  static Future<bool> startNativeDetector() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final ok = await _oemChannel.invokeMethod<bool>('startSensorService', {
        'shake': prefs.getBool('setting_shake_to_sos') ?? true,
        'crash': prefs.getBool('setting_crash_detection') ?? true,
        'crashThreshold':
            _thresholdFor(prefs.getString('setting_crash_sensitivity')),
      });
      return ok ?? false;
    } catch (e) {
      // ignore: avoid_print
      print('[BackgroundSOS] native detector start failed: $e');
      return false;
    }
  }

  static Future<void> stopNativeDetector() async {
    try {
      await _oemChannel.invokeMethod('stopSensorService');
    } catch (_) {}
  }

  /// Pushes the current Settings toggles to the running native detector.
  static Future<void> syncNativeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await _oemChannel.invokeMethod('updateSensorSettings', {
        'shake': prefs.getBool('setting_shake_to_sos') ?? true,
        'crash': prefs.getBool('setting_crash_detection') ?? true,
        'crashThreshold':
            _thresholdFor(prefs.getString('setting_crash_sensitivity')),
      });
    } catch (_) {}
  }

  /// If the native detector cold-launched the app, returns 'shake' or 'crash'.
  static Future<String?> consumePendingSos() async {
    try {
      return await _oemChannel.invokeMethod<String>('consumePendingSos');
    } catch (_) {
      return null;
    }
  }

  /// Listen for detections that arrive while the app is already running.
  static void listenForDetections(void Function(String kind) onDetected) {
    _oemChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSosDetected') {
        final kind = call.arguments?.toString();
        if (kind != null && kind.isNotEmpty) onDetected(kind);
      }
      return null;
    });
  }

  /// Configure the service once at app startup (does NOT start it).
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // we start it explicitly after login
        // Re-arm protection automatically after a device reboot (the isolate
        // checks the user's toggle in onStart and stops itself if it's off).
        autoStartOnBoot: true,
        isForegroundMode: true,
        // "location" foreground-service type — matches the manifest. It is far
        // more compatible with aggressive OEMs than "specialUse" (which MIUI
        // rejects at startForeground(), crashing the app). The SOS genuinely
        // uses location, so this type is valid.
        foregroundServiceTypes: const [AndroidForegroundType.location],
        notificationChannelId: _channelId,
        initialNotificationTitle: 'SmartSafe protection active',
        initialNotificationContent:
            'Crash & shake SOS running so you\'re covered even when the app is closed.',
        foregroundServiceNotificationId: _fgNotifId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  /// SharedPreferences flag: have we already shown the OS battery-optimisation
  /// dialog once? Set true after the first request so we never nag on every
  /// launch (a DENY used to re-prompt endlessly).
  static const kBatteryAskedFlag = 'battery_opt_asked';

  /// Crash-recovery flag. Set right BEFORE a foreground-service start and cleared
  /// right AFTER it succeeds. If the app finds it still set on the next launch,
  /// the previous start must have crashed the process mid-way (as MIUI can do at
  /// the native startForeground layer) — so the app disables the feature and
  /// stays stable. This turns "crashes forever" into "at most one crash, then
  /// self-heals". Checked in [recoverIfPreviousStartCrashed].
  static const kStartingFlag = 'bg_service_starting';

  /// Call once at every app launch, BEFORE anything might start the service.
  /// If the last start crashed mid-way, turn the feature off so the app opens
  /// cleanly instead of crash-looping. Returns true if it had to self-heal.
  static Future<bool> recoverIfPreviousStartCrashed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (prefs.getBool(kStartingFlag) == true) {
        // The previous start never finished → it crashed. Disarm everything.
        await prefs.setBool(kStartingFlag, false);
        await prefs.setBool('setting_background_protection', false);
        await stop();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Start protection (call after the user signs in + toggles allow it).
  ///
  /// [requestBattery] controls whether the OS battery-optimisation exemption
  /// dialog is shown. It's OFF on silent auto-start (so the system dialog never
  /// pops up abruptly on the Home screen); the Home screen shows a branded
  /// explanation first and calls [requestBatteryExemption] only when the user
  /// taps "Allow". The Settings toggle passes true (explicit opt-in).
  /// Returns true if the background service is running afterwards. FULLY guarded
  /// so a failure to start the foreground service (common on aggressive OEMs
  /// like MIUI/Xiaomi) can NEVER crash the main app — the worst case is that
  /// background-while-closed detection is simply unavailable; in-app shake/crash
  /// SOS keeps working regardless.
  static Future<bool> start({bool requestBattery = false}) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // A "location" foreground service REQUIRES location permission granted, or
      // startForeground() throws. Don't even attempt to start without it.
      if (!await Permission.locationWhenInUse.isGranted &&
          !await Permission.location.isGranted) {
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          print('[BackgroundSOS] location not granted — not starting');
          return false;
        }
      }
      if (requestBattery) {
        await requestBatteryExemption();
      }
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        // Mark that a start is in progress. If the native startForeground crashes
        // the whole process (MIUI), this flag survives and the NEXT launch
        // self-heals via recoverIfPreviousStartCrashed().
        await prefs.setBool(kStartingFlag, true);
        await service.startService();
      }
      final running = await service.isRunning();
      // Reached here without crashing → clear the recovery flag.
      await prefs.setBool(kStartingFlag, false);
      return running;
    } catch (e) {
      // Never let a background-service failure take the app down.
      await prefs.setBool(kStartingFlag, false).catchError((_) => false);
      // ignore: avoid_print
      print('[BackgroundSOS] start failed (kept app safe): $e');
      return false;
    }
  }

  /// Ask the OS to exempt us from battery optimisation — the single most
  /// important step for real-world reliability (Xiaomi/Samsung/Oppo kill the
  /// background isolate otherwise). Shown at most ONCE automatically; after that
  /// it only re-appears from an explicit user action (Settings toggle / the
  /// Home "Allow" button, which pass [force] = true). Returns whether the
  /// exemption is granted afterwards.
  static Future<bool> requestBatteryExemption({bool force = false}) async {
    try {
      if (await Permission.ignoreBatteryOptimizations.isGranted) return true;
      final prefs = await SharedPreferences.getInstance();
      if (!force && (prefs.getBool(kBatteryAskedFlag) ?? false)) {
        // Already asked once and the user didn't grant — don't nag again.
        return false;
      }
      await prefs.setBool(kBatteryAskedFlag, true);
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Whether the OS battery-optimisation exemption is currently granted. Lets
  /// the UI decide whether to show the branded "Allow background" explanation.
  static Future<bool> isBatteryExemptionGranted() async {
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Stop protection (call on logout).
  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stopService');
    }
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

/// Background-isolate entry point. Runs in its OWN isolate, so it must
/// re-initialise plugins + Firebase itself.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // EVERYTHING in this isolate is wrapped: an unhandled throw here crashes the
  // background isolate, and on aggressive OEMs (MIUI/Xiaomi) that repeated
  // crash-restart is what triggers the system "app is experiencing crashes"
  // warning. Catching it means the worst case is "protection quietly stops",
  // never a crash loop.
  try {
    await _runBackgroundIsolate(service);
  } catch (e) {
    // ignore: avoid_print
    print('[BackgroundSOS] onStart failed (contained): $e');
    try {
      service.stopSelf();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<void> _runBackgroundIsolate(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Already initialised in this isolate — fine.
  }

  // Respect the user's choice across reboots: autoStartOnBoot re-launches this
  // isolate after a restart, so it must only keep running when the user has
  // EXPLICITLY enabled Background Protection. A fresh install (null) has never
  // opted in — stop, or a device reboot would silently arm the very service
  // that kills the app on aggressive OEMs.
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool('setting_background_protection') != true) {
      service.stopSelf();
      return;
    }
  } catch (_) {}

  // Apply the user's Settings toggles, and KEEP them in sync. The Settings
  // screen writes these prefs from the FOREGROUND isolate, which this isolate
  // can't see in memory — so without re-reading, turning Shake/Crash OFF would
  // never stop the background detector. We re-read every few seconds so "off"
  // really turns it off (and "on" turns it back on) within seconds.
  Future<void> applySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      SensorService.instance.shakeEnabled =
          prefs.getBool('setting_shake_to_sos') ?? true;
      SensorService.instance.crashEnabled =
          prefs.getBool('setting_crash_detection') ?? true;
      // Apply the user's chosen crash sensitivity here too — this background
      // isolate used to always run at the hardest 4G threshold regardless of
      // the app setting, so a real (or test) impact rarely tripped it.
      final sens = prefs.getString('setting_crash_sensitivity');
      if (sens != null) SensorService.instance.setCrashSensitivity(sens);
    } catch (_) {}
  }

  await applySettings();
  final settingsTimer =
      Timer.periodic(const Duration(seconds: 5), (_) => applySettings());

  // Allow the app to stop us cleanly on logout.
  service.on('stopService').listen((_) {
    settingsTimer.cancel();
    SensorService.instance.stopListening();
    service.stopSelf();
  });

  // A background isolate CANNOT place a phone call or open WhatsApp — those need
  // a foreground Activity. So on a detected shake/crash we DON'T half-dispatch
  // here; we pop the app open with a full-screen intent (like an incoming call,
  // even over the lock screen) and let it run the REAL SOS — call first, then
  // WhatsApp, then SMS/push — from the foreground where all of that works.
  var alerting = false;
  Future<void> raiseAlert(String kind) async {
    if (alerting) return;
    alerting = true;
    try {
      await LocalNotificationService.instance.showSosFullScreen(kind);
    } catch (_) {}
    // Cool-down so one event can't spam repeat alerts.
    await Future.delayed(const Duration(seconds: 20));
    alerting = false;
  }

  SensorService.instance.onShakeSOSTrigger = () => raiseAlert('shake');
  SensorService.instance.onCrashSOSTrigger = () => raiseAlert('crash');

  SensorService.instance.startListening();
}
