
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  static final SensorService instance = SensorService._internal();
  SensorService._internal();

  StreamSubscription<AccelerometerEvent>? _subscription;

  // The accelerometer fires ~50–60×/sec, but shake detection works on a
  // 400ms debounce and crash detection holds a 15s cooldown — neither needs
  // anywhere near that resolution. Sampling at ~30Hz cuts the always-on
  // listener CPU cost roughly in half with zero detection fidelity loss
  // (a real 3G+ impact lasts 100ms+, i.e. 3+ samples at 30Hz).
  DateTime? _lastSampleAt;
  static const Duration _sampleInterval = Duration(milliseconds: 33);

  // Stream controller to broadcast raw magnitude to the Crash Detection page UI
  final _accelController = StreamController<double>.broadcast();
  Stream<double> get accelMagnitudeStream => _accelController.stream;
  double _lastMagnitude = 0.0;
  double get currentMagnitude => _lastMagnitude;

  // Callbacks
  VoidCallback? onShakeSOSTrigger;
  VoidCallback? onCrashSOSTrigger;

  // Feature switches — controlled by the Settings toggles. When false, the
  // gesture is detected but NO SOS is fired (so turning it off really works).
  bool shakeEnabled = true;
  bool crashEnabled = true;

  // Shake detection state
  final List<DateTime> _shakeTimestamps = [];
  static const double _shakeThreshold = 18.0; // Acceleration magnitude threshold for a shake
  static const Duration _shakeWindow = Duration(seconds: 2); // Timeframe to complete 3 shakes
  DateTime? _lastShakeTime;

  // Crash detection state — threshold is adjustable via sensitivity level.
  // Default is ~3G (Medium): sensitive enough that a real impact — or a hard
  // shake used to TEST it — actually trips detection, while the 15-second
  // "I'M OK" cancel window means an occasional false alarm harms nobody. (The
  // old 4G default was so high it was almost impossible to trigger by hand,
  // which made crash detection look broken.)
  double _crashThreshold = 30.0;
  bool _crashAlertActive = false;

  /// Current crash sensitivity as a label ('Low' | 'Medium' | 'High').
  String get crashSensitivity => _crashThreshold <= 24.0
      ? 'High'
      : _crashThreshold >= 38.0
          ? 'Low'
          : 'Medium';

  /// Lower threshold = MORE sensitive (triggers on smaller impacts).
  /// High → 22 (≈2.2G), Medium → 30 (≈3G), Low → 40 (≈4G).
  void setCrashSensitivity(String level) {
    switch (level) {
      case 'High':
        _crashThreshold = 22.0;
        break;
      case 'Low':
        _crashThreshold = 40.0;
        break;
      default:
        _crashThreshold = 30.0;
    }
    debugPrint('[Sensor] Crash sensitivity = $level (threshold $_crashThreshold)');
  }

  void startListening() {
    if (_subscription != null) return;

    _subscription = accelerometerEventStream(
      samplingPeriod: _sampleInterval,
    ).listen((event) {
      // Throttle to ~30Hz before doing ANY work (see _lastSampleAt docs).
      final sampledAt = DateTime.now();
      if (_lastSampleAt != null &&
          sampledAt.difference(_lastSampleAt!) < _sampleInterval) {
        return;
      }
      _lastSampleAt = sampledAt;

      final double x = event.x;
      final double y = event.y;
      final double z = event.z;

      // Compute total acceleration magnitude
      final double magnitude = sqrt(x * x + y * y + z * z);
      _lastMagnitude = magnitude;
      // Only push to the broadcast stream when a UI page is actually listening
      // (the accelerometer fires ~60×/sec — broadcasting with zero listeners
      // was pure allocation churn).
      if (_accelController.hasListener) {
        _accelController.add(magnitude);
      }

      final now = sampledAt;

      // 1. Shake Detection (requires 3 rapid shakes in 2 seconds)
      if (magnitude > _shakeThreshold) {
        if (_lastShakeTime == null || now.difference(_lastShakeTime!) > const Duration(milliseconds: 400)) {
          _lastShakeTime = now;
          _shakeTimestamps.add(now);
          debugPrint('Shake detected at $now. Magnitude: $magnitude. Total count in window: ${_shakeTimestamps.length}');

          // Remove shakes outside our sliding window
          _shakeTimestamps.removeWhere((time) => now.difference(time) > _shakeWindow);

          if (_shakeTimestamps.length >= 3) {
            _shakeTimestamps.clear();
            // Respect the Settings toggle — only fire if Shake to SOS is ON.
            if (shakeEnabled && onShakeSOSTrigger != null) {
              debugPrint('SOS Triggered by 3x Shake!');
              onShakeSOSTrigger!();
            }
          }
        }
      }

      // 2. Crash Detection (high-G impact) — but NOT while the user is
      // deliberately shaking for an SOS (recent shake events present).
      if (crashEnabled &&
          magnitude > _crashThreshold &&
          _shakeTimestamps.length < 2) {
        if (!_crashAlertActive) {
          _crashAlertActive = true;
          debugPrint('Crash impact detected! Magnitude: $magnitude');
          if (onCrashSOSTrigger != null) {
            onCrashSOSTrigger!();
          }
          // Cool down period before allowing another crash trigger
          Future.delayed(const Duration(seconds: 15), () {
            _crashAlertActive = false;
          });
        }
      }
    }, onError: (e) {
      debugPrint('SensorService error: $e');
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}
