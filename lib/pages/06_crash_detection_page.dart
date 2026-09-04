import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../services/sensor_service.dart';
import '../services/app_firestore_service.dart';
import '02_alert_page.dart';
import '../navigation/dark_route.dart';

class CrashDetectionPage extends StatefulWidget {
  /// When true (opened because a crash was detected), the cancel countdown
  /// starts immediately.
  final bool autoStart;
  const CrashDetectionPage({super.key, this.autoStart = false});

  @override
  State<CrashDetectionPage> createState() => _CrashDetectionPageState();
}

class _CrashDetectionPageState extends State<CrashDetectionPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _accelCtrl;
  StreamSubscription<double>? _sensorSub;
  final ValueNotifier<double> _accelValueNotifier = ValueNotifier<double>(0.05);
  late String _sensitivity = SensorService.instance.crashSensitivity;
  bool _crashTriggered = false;
  int _countdown = 10;
  Timer? _crashTimer;
  VoidCallback? _prevCrashCb;

  // Loud alarm + vibration while the cancel countdown runs, so an injured or
  // unaware user (phone in pocket / face-down) still notices the alert.
  final AudioPlayer _alarmPlayer = AudioPlayer();
  Timer? _vibrateTimer;
  bool _dispatched = false; // guards against double-dispatch (button + timeout)

  @override
  void initState() {
    super.initState();
    _accelCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
          ..repeat(reverse: true);

    // Listen to real accelerometer magnitude stream
    _sensorSub = SensorService.instance.accelMagnitudeStream.listen((mag) {
      if (mounted) {
        _accelValueNotifier.value = (mag / 25.0).clamp(0.05, 1.0);
      }
    });

    // Override the crash trigger callback to start countdown if already on this
    // page. Remember the previous (global) handler so we can RESTORE it on
    // dispose — otherwise automatic crash detection breaks app-wide after the
    // user visits this page once.
    _prevCrashCb = SensorService.instance.onCrashSOSTrigger;
    SensorService.instance.onCrashSOSTrigger = () {
      if (mounted && !_crashTriggered) {
        _triggerCrash();
      }
    };

    // Opened because a real crash was detected → start the countdown now.
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerCrash();
      });
    }
  }

  @override
  void dispose() {
    // Restore the global crash handler so app-wide auto-detection keeps working.
    SensorService.instance.onCrashSOSTrigger = _prevCrashCb;
    _accelCtrl.dispose();
    _sensorSub?.cancel();
    _crashTimer?.cancel();
    _stopAlarm();
    _alarmPlayer.dispose();
    _accelValueNotifier.dispose();
    super.dispose();
  }

  /// Loud siren (routed through the ALARM stream so it plays over silent/vibrate
  /// and media volume) plus a repeating strong buzz while the countdown runs.
  Future<void> _startAlarm() async {
    try {
      final loudCtx = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
      );
      await _alarmPlayer.setAudioContext(loudCtx);
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.setVolume(1.0);
      await _alarmPlayer.play(AssetSource('sounds/siren1.wav'));
    } catch (e) {
      debugPrint('[Crash] alarm play error: $e');
    }
    HapticFeedback.heavyImpact();
    _vibrateTimer?.cancel();
    _vibrateTimer =
        Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.heavyImpact();
    });
  }

  Future<void> _stopAlarm() async {
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
    try {
      await _alarmPlayer.stop();
    } catch (_) {}
  }

  void _triggerCrash() {
    _dispatched = false;
    setState(() {
      _crashTriggered = true;
      _countdown = 10;
    });
    _startAlarm();
    _crashTimer?.cancel();
    _crashTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          t.cancel();
          _dispatchNow();
        }
      });
    });
  }

  /// Fire the SOS now — stops the alarm, records the press and opens the alert
  /// screen which dials Rescue 1122. Used by BOTH the 10s timeout AND the
  /// "Emergency Call Now" button. Guarded so it only runs once.
  void _dispatchNow() {
    if (_dispatched) return;
    _dispatched = true;
    _crashTimer?.cancel();
    _stopAlarm();
    setState(() => _crashTriggered = false);
    AppFirestoreService.instance.recordSosPress(
      source: 'crash_sensor',
      location: 'GPS acquiring…',
    );
    Navigator.push(
      context,
      darkRoute(const AlertPage(emergencyNumber: '1122')),
    );
  }

  void _cancelCrash() {
    _crashTimer?.cancel();
    _stopAlarm();
    setState(() => _crashTriggered = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  SlideUpFade(
                    child: Row(
                      children: [
                        if (Navigator.canPop(context)) ...[
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
                          ),
                          const SizedBox(width: 12),
                        ],
                        DynText('crash_detection', 'title', 'Crash Detection', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  SlideUpFade(
                    delay: const Duration(milliseconds: 50),
                    child: Text(
                        'Monitors accelerometer for sudden impacts',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ),
                  const SizedBox(height: 24),

                  // Status circle
                  SlideUpFade(
                    delay: const Duration(milliseconds: 100),
                    child: Center(
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.warning.withValues(alpha: 0.08),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3),
                              width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.car_crash_rounded,
                                color: AppColors.warning, size: 38),
                            const SizedBox(height: 8),
                            Text('MONITORING',
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Accelerometer bar
                  SlideUpFade(
                    delay: const Duration(milliseconds: 150),
                    child: DCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.sensors_rounded,
                                  color: AppColors.red, size: 18),
                              const SizedBox(width: 8),
                              Text('Live Accelerometer',
                                  style: TextStyle(
                                      color: C.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<double>(
                            valueListenable: _accelValueNotifier,
                            builder: (context, accelVal, child) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RepaintBoundary(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: accelVal,
                                        minHeight: 12,
                                        backgroundColor: AppColors.border,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          accelVal > 0.7
                                              ? AppColors.red
                                              : accelVal > 0.4
                                                  ? AppColors.warning
                                                  : C.success,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                          '${(accelVal * 25.0).toStringAsFixed(2)} m/s²',
                                          style: TextStyle(
                                              color: AppColors.red, fontSize: 12)),
                                      const Spacer(),
                                      Text('Live Sensor Data',
                                          style: TextStyle(
                                              color: AppColors.textMuted, fontSize: 11)),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sensitivity
                  SlideUpFade(
                    delay: const Duration(milliseconds: 200),
                    child: DCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text('Sensitivity Level', style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 12),
                          Row(
                            children: ['Low', 'Medium', 'High']
                                .map((s) => Expanded(
                                       child: GestureDetector(
                                         onTap: () async {
                                           setState(() => _sensitivity = s);
                                           SensorService.instance
                                               .setCrashSensitivity(s);
                                           // Persist it so it survives a restart
                                           // AND so the background crash detector
                                           // (a separate isolate) uses the same
                                           // sensitivity — previously it always
                                           // ran at the hardest 4G threshold.
                                           final prefs =
                                               await SharedPreferences
                                                   .getInstance();
                                           await prefs.setString(
                                               'setting_crash_sensitivity', s);
                                         },
                                         child: Container(
                                           margin: const EdgeInsets.only(
                                               right: 8),
                                           padding: const EdgeInsets.symmetric(
                                               vertical: 10),
                                           decoration: BoxDecoration(
                                             color: _sensitivity == s
                                                 ? AppColors.warning
                                                     .withValues(alpha: 0.15)
                                                 : AppColors.bg3,
                                             borderRadius:
                                                 BorderRadius.circular(8),
                                             border: Border.all(
                                               color: _sensitivity == s
                                                   ? AppColors.warning
                                                       .withValues(alpha: 0.4)
                                                   : AppColors.border,
                                             ),
                                           ),
                                           child: Center(
                                             child: Text(s,
                                                 style: TextStyle(
                                                   color: _sensitivity == s
                                                       ? AppColors.warning
                                                       : AppColors.textMuted,
                                                   fontWeight: FontWeight.w600,
                                                   fontSize: 12,
                                                 )),
                                           ),
                                         ),
                                       ),
                                     ))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Flow
                  SlideUpFade(
                    delay: const Duration(milliseconds: 250),
                    child: DCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text('Detection Flow', style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 16),
                          ...[
                            _FlowStep(1, 'Impact Detected', Icons.sensors_rounded,
                                AppColors.warning),
                            _FlowStep(2, '10s Cancel Window',
                                Icons.timer_outlined, AppColors.red),
                            _FlowStep(3, 'SOS Alert Sent',
                                Icons.warning_rounded, AppColors.red),
                            _FlowStep(4, 'Emergency Contacted',
                                Icons.phone_rounded, AppColors.success),
                          ].map((s) => s),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Crash triggered overlay
                  if (_crashTriggered)
                    SlideUpFade(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.red.withValues(alpha: 0.5),
                              width: 1.5),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: AppColors.red, size: 36),
                            const SizedBox(height: 8),
                            Text('CRASH DETECTED!',
                                style: TextStyle(
                                  color: AppColors.red,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                )),
                            const SizedBox(height: 6),
                            Text(
                              'Calling Rescue 1122 in $_countdown seconds...',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                // Cancel — false alarm (e.g. phone just dropped).
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _cancelCrash,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: const Text(
                                        "I'm OK — Cancel",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Skip the countdown and get help NOW.
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _dispatchNow,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: const Text(
                                        'Emergency Call Now',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Test button
                  if (!_crashTriggered)
                    SlideUpFade(
                      delay: const Duration(milliseconds: 350),
                      child: GestureDetector(
                        onTap: _triggerCrash,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.warning.withValues(alpha: 0.3)),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.science_rounded,
                                    color: AppColors.warning, size: 20),
                                const SizedBox(width: 8),
                                Text('Test Crash Detection',
                                    style: TextStyle(
                                      color: AppColors.warning,
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

class _FlowStep extends StatelessWidget {
  final int step;
  final String label;
  final IconData icon;
  final Color color;

  const _FlowStep(this.step, this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text('$step',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}
