import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'evidence_service.dart';
import 'location_service.dart';

/// Records a short audio clip the moment an SOS fires — automatic evidence of
/// what's happening around the user. Used by the Shake-SOS flow: after the call
/// is placed and the app returns to the foreground, we quietly capture 30s and
/// upload it as evidence (visible in the Evidence page + admin dashboard).
///
/// Best-effort by design: if the mic permission is denied or the upload fails,
/// it never throws into the SOS flow — the SOS itself must always come first.
class SosRecordingService {
  SosRecordingService._();
  static final SosRecordingService instance = SosRecordingService._();

  final AudioRecorder _recorder = AudioRecorder();
  bool _busy = false;
  Timer? _stopTimer;

  /// Currently recording an SOS clip?
  bool get isRecording => _busy;

  /// Seconds remaining in the active recording (0 when idle).
  final ValueNotifier<int> secondsLeft = ValueNotifier<int>(0);

  /// Start a [seconds]-long recording, then auto-stop and upload as evidence.
  /// Returns immediately; the recording continues in the background.
  Future<void> startEmergencyRecording({
    int seconds = 30,
    String note = 'Auto SOS recording',
  }) async {
    if (_busy) return; // one SOS recording at a time
    _busy = true;
    secondsLeft.value = seconds;

    String? path;
    try {
      if (!await _recorder.hasPermission()) {
        debugPrint('[SosRec] microphone permission not granted — skipping');
        _reset();
        return;
      }
      final dir = await getTemporaryDirectory();
      path =
          '${dir.path}/sos_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      debugPrint('[SosRec] recording started → $path');

      // Live countdown for any UI that wants to show it.
      _stopTimer?.cancel();
      _stopTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (secondsLeft.value <= 1) {
          t.cancel();
          _finish(note: note);
        } else {
          secondsLeft.value -= 1;
        }
      });
    } catch (e) {
      debugPrint('[SosRec] failed to start: $e');
      _reset();
    }
  }

  /// Stop early (e.g. the user cancelled the SOS) and still upload what we have.
  Future<void> stopAndUpload({String note = 'Auto SOS recording'}) async {
    if (!_busy) return;
    _stopTimer?.cancel();
    await _finish(note: note);
  }

  Future<void> _finish({required String note}) async {
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      debugPrint('[SosRec] stop failed: $e');
    }
    secondsLeft.value = 0;
    _busy = false;

    if (path == null) return;
    // Upload as evidence in the background — never block or throw into the SOS.
    unawaited(_upload(path, note));
  }

  Future<void> _upload(String path, String note) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final size = await file.length();
      final sizeKB = (size / 1024).toStringAsFixed(0);

      double lat = 0, lng = 0;
      String address = 'Location unavailable';
      try {
        final loc = await LocationService.instance
            .getCurrentLocation()
            .timeout(const Duration(seconds: 6));
        if (loc != null) {
          lat = loc.latitude;
          lng = loc.longitude;
          address =
              '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        }
      } catch (_) {}

      await EvidenceService.instance.uploadEvidence(
        file: file,
        type: 'audio',
        note: note,
        locationString: address,
        lat: lat,
        lng: lng,
        fileSizeStr: '$sizeKB KB',
      );
      debugPrint('[SosRec] evidence uploaded ($sizeKB KB)');
    } catch (e) {
      debugPrint('[SosRec] upload failed: $e');
    }
  }

  void _reset() {
    _busy = false;
    secondsLeft.value = 0;
    _stopTimer?.cancel();
  }
}
