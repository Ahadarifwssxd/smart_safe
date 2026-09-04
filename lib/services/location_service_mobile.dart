import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';

LocationService? _instance;

LocationService getLocationServiceInstance() {
  _instance ??= MobileLocationService();
  return _instance!;
}

class MobileLocationService implements LocationService {
  final StreamController<LocationData> _controller =
      StreamController<LocationData>.broadcast();
  StreamSubscription<Position>? _subscription;
  bool _isTracking = false;

  double _lastLat = 0.0;
  double _lastLon = 0.0;
  DateTime? _lastTime;

  // Last position emitted by the tracking stream. `getCurrentLocation()` used
  // to force a brand-new high-accuracy GPS fix on every call — and callers
  // (presence heartbeat, SOS dispatch) poll it every 25 seconds, keeping the
  // GPS radio permanently hot. A recent cached fix is returned instead.
  LocationData? _lastPosition;
  static const _cachedFixMaxAge = Duration(seconds: 15);

  // The `users/{uid}` doc used to be written on EVERY position update (every
  // ~10 m of movement) on top of the live_tracking write — doubling Firestore
  // write volume while driving. Once a minute is plenty for the dashboard.
  DateTime? _lastUsersDocWrite;
  static const _usersDocWriteInterval = Duration(minutes: 1);

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
      _isTracking = false;
      startTracking();
    }
  }

  @override
  Future<String?> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. Please enable GPS in your device settings.';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission denied. Please allow location access in app settings.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return 'Location permission is permanently denied. Please enable it in Settings > SmartSafe > Location.';
    }

    return null;
  }

  @override
  Future<LocationData?> getCurrentLocation() async {
    // Reuse a fresh fix from the active tracking stream — no GPS wake-up.
    final cached = _lastPosition;
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cachedFixMaxAge) {
      return cached;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
      return _toLocationData(position);
    } catch (_) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return _toLocationData(lastKnown);
        }
      } catch (_) {}
      // Fall back to an older cached fix rather than nothing.
      return _lastPosition;
    }
  }

  @override
  void startTracking() async {
    if (_isTracking) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _isTracking = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    _updateSharingState(true);

    // distanceFilter 0 emits an update on EVERY tiny movement, which hammers
    // Google Play Services non-stop (a big cause of "Play services isn't
    // responding" + battery drain on throttled devices like MIUI). Only update
    // after ~10 m of real movement — still precise enough for live SOS tracking.
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_emitPosition, onError: (err) {
      print('Mobile location tracking error: $err');
    });

    try {
      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
      _emitPosition(current);
    } catch (err) {
      print('Initial location fetch error: $err');
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _emitPosition(lastKnown);
        }
      } catch (_) {}
    }
  }

  @override
  void stopTracking() async {
    if (!_isTracking) return;
    _isTracking = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, false);

    _updateSharingState(false);
    await _subscription?.cancel();
    _subscription = null;
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a));
  }

  void _emitPosition(Position position) {
    final locData = _toLocationData(position);
    _lastPosition = locData;
    _controller.add(locData);
    _maybeSaveLocationToFirestore(locData);
  }

  LocationData _toLocationData(Position position) {
    final now = DateTime.now();
    double speed = position.speed * 3.6;

    if (speed <= 0 && _lastLat != 0.0 && _lastLon != 0.0 && _lastTime != null) {
      final dist = _calculateDistance(
          _lastLat, _lastLon, position.latitude, position.longitude);
      final diffSeconds = now.difference(_lastTime!).inSeconds;
      if (diffSeconds > 0) {
        speed = (dist / diffSeconds) * 3.6;
      }
    }

    _lastLat = position.latitude;
    _lastLon = position.longitude;
    _lastTime = now;

    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: speed,
      timestamp: now,
    );
  }

  /// Throttled mirror of the position into the `users` doc (dashboard reads it
  /// for the user list). Writes at most once a minute — the real-time feed
  /// lives in `live_tracking`.
  Future<void> _maybeSaveLocationToFirestore(LocationData data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now();
    if (_lastUsersDocWrite != null &&
        now.difference(_lastUsersDocWrite!) < _usersDocWriteInterval) {
      return;
    }
    _lastUsersDocWrite = now;
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
