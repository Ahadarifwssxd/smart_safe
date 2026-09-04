// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';

LocationService? _instance;

LocationService getLocationServiceInstance() {
  _instance ??= WebLocationService();
  return _instance!;
}

class WebLocationService implements LocationService {
  final StreamController<LocationData> _controller =
      StreamController<LocationData>.broadcast();
  StreamSubscription<html.Geoposition>? _subscription;
  bool _isTracking = false;

  double _lastLat = 0.0;
  double _lastLon = 0.0;
  DateTime? _lastTime;

  static const _prefsKey = 'is_location_tracking_active';

  @override
  bool get isTracking => _isTracking;

  @override
  Stream<LocationData> get onLocationChanged => _controller.stream;

  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isTracking = prefs.getBool(_prefsKey) ?? false;
    if (_isTracking) {
      _isTracking = false; // Reset briefly so startTracking actually starts it
      startTracking();
    }
  }

  @override
  Future<String?> requestPermission() async {
    final uri = Uri.parse(html.window.location.href);
    final isSecure = uri.isScheme('https') ||
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1';
    if (!isSecure) {
      return 'Location sharing requires a secure context (HTTPS). If testing on mobile, use localhost or configure Chrome flags.';
    }

    try {
      // Use low accuracy for the permission check to prevent timeouts on devices without GPS
      final pos = await html.window.navigator.geolocation.getCurrentPosition(
        enableHighAccuracy: false,
        timeout: const Duration(seconds: 5),
      );
      if (pos.coords != null) return null;
      return 'Failed to obtain location coordinates.';
    } catch (e) {
      if (e is html.PositionError) {
        switch (e.code) {
          case 1: // PERMISSION_DENIED
            return 'GPS Permission Denied. Please click the Lock/Settings icon next to the URL in your browser address bar and set Location to "Allow".';
          case 2: // POSITION_UNAVAILABLE
          case 3: // TIMEOUT
            // The user allowed permission, but location is currently unavailable/timed out.
            // Since permission is granted, we return null (success) so the app can start tracking.
            print(
                'Geolocation allowed but status is code ${e.code}. Treating as allowed.');
            return null;
          default:
            return 'Location error code: ${e.code}';
        }
      }
      return 'Geolocation unexpected error: $e';
    }
  }

  @override
  Future<LocationData?> getCurrentLocation() async {
    try {
      final pos = await html.window.navigator.geolocation.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 8),
      );
      final coords = pos.coords;
      if (coords == null) return null;

      return LocationData(
        latitude: coords.latitude?.toDouble() ?? 0.0,
        longitude: coords.longitude?.toDouble() ?? 0.0,
        accuracy: coords.accuracy?.toDouble() ?? 0.0,
        speed: (coords.speed?.toDouble() ?? 0.0) * 3.6,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void startTracking() async {
    if (_isTracking) return;
    _isTracking = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);

    _updateSharingState(true);

    _subscription = html.window.navigator.geolocation
        .watchPosition(
      enableHighAccuracy: true,
    )
        .listen((pos) {
      final coords = pos.coords;
      if (coords == null) return;

      final lat = coords.latitude?.toDouble() ?? 0.0;
      final lon = coords.longitude?.toDouble() ?? 0.0;
      final accuracy = coords.accuracy?.toDouble() ?? 0.0;

      double speed = coords.speed?.toDouble() ?? 0.0;
      final now = DateTime.now();

      // Calculate speed if the browser returns zero/null and we have a previous coordinate
      if (speed <= 0 &&
          _lastLat != 0.0 &&
          _lastLon != 0.0 &&
          _lastTime != null) {
        final dist =
            _calculateDistance(_lastLat, _lastLon, lat, lon); // in meters
        final diffSeconds = now.difference(_lastTime!).inSeconds;
        if (diffSeconds > 0) {
          speed = (dist / diffSeconds) * 3.6; // convert m/s to km/h
        }
      } else {
        speed = speed * 3.6; // convert m/s to km/h
      }

      _lastLat = lat;
      _lastLon = lon;
      _lastTime = now;

      final locData = LocationData(
        latitude: lat,
        longitude: lon,
        accuracy: accuracy,
        speed: speed,
        timestamp: now,
      );

      _controller.add(locData);
      _saveLocationToFirestore(locData);
    }, onError: (err) {
      if (err is html.PositionError && err.code == 1) {
        // Only stop tracking if permission is explicitly denied/revoked
        print('Geolocation permission revoked during tracking.');
        _isTracking = false;
        _updateSharingState(false);
      } else {
        print('Temporary tracking error (e.g. timeout/weak GPS): $err');
      }
    });
  }

  @override
  void stopTracking() async {
    if (!_isTracking) return;
    _isTracking = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, false);

    _updateSharingState(false);
    _subscription?.cancel();
    _subscription = null;
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a)); // 2 * R; R = 6371000m
  }

  Future<void> _saveLocationToFirestore(LocationData data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'latitude': data.latitude,
        'longitude': data.longitude,
        'accuracy': data.accuracy,
        'speed': data.speed,
        'isLocationSharingActive': true,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _updateSharingState(bool active) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'isLocationSharingActive': active,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
