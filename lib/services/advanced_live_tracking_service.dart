import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'location_service.dart';

// ─────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────

class LiveTrackingData {
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isHelper;
  final String status; // 'arriving', 'arrived', 'helping'
  final bool isOnline; // Location service ON/OFF
  final double accuracy;
  final double speed;
  final List<RoutePoint> routeHistory;

  LiveTrackingData({
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isHelper = false,
    this.status = 'active',
    this.isOnline = true,
    this.accuracy = 0,
    this.speed = 0,
    this.routeHistory = const [],
  });

  factory LiveTrackingData.fromFirestore(Map<String, dynamic> data) {
    return LiveTrackingData(
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'User',
      latitude: data['latitude'] ?? 0.0,
      longitude: data['longitude'] ?? 0.0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isHelper: data['isHelper'] ?? false,
      status: data['status'] ?? 'active',
      isOnline: data['isOnline'] ?? true,
      accuracy: data['accuracy'] ?? 0.0,
      speed: data['speed'] ?? 0.0,
      routeHistory: (data['routeHistory'] as List?)
              ?.map((r) => RoutePoint.fromMap(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userName': userName,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'isHelper': isHelper,
        'status': status,
        'isOnline': isOnline,
        'accuracy': accuracy,
        'speed': speed,
      };
}

class RoutePoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double speed;
  final double accuracy;

  RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speed = 0,
    this.accuracy = 0,
  });

  factory RoutePoint.fromMap(Map<String, dynamic> map) {
    return RoutePoint(
      latitude: map['latitude'] ?? 0.0,
      longitude: map['longitude'] ?? 0.0,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      speed: map['speed'] ?? 0.0,
      accuracy: map['accuracy'] ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() => {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'speed': speed,
        'accuracy': accuracy,
      };
}

class HelperInfo {
  final String userId;
  final String name;
  final double latitude;
  final double longitude;
  final String status; // 'arriving', 'arrived', 'helping'
  final DateTime timestamp;
  final List<RoutePoint> route;
  final double distanceToUser;
  final int etaSeconds;
  final bool isOnline;

  HelperInfo({
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.timestamp,
    this.route = const [],
    this.distanceToUser = 0,
    this.etaSeconds = 0,
    this.isOnline = true,
  });
}

class SOSAlert {
  final String alertId;
  final String userId;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String status; // 'active', 'resolved'
  final List<String> helperIds;
  final List<RoutePoint> userRoute;
  final String placeName;

  SOSAlert({
    required this.alertId,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.status = 'active',
    this.helperIds = const [],
    this.userRoute = const [],
    this.placeName = '',
  });
}

// ─────────────────────────────────────────────────────────────
// LIVE TRACKING SERVICE (Advanced)
// ─────────────────────────────────────────────────────────────

class AdvancedLiveTrackingService {
  static final AdvancedLiveTrackingService _instance =
      AdvancedLiveTrackingService._internal();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _connectivity = Connectivity();

  // Streams
  final _liveTrackingController =
      StreamController<Map<String, LiveTrackingData>>.broadcast();
  final _sosHelpersController = StreamController<List<HelperInfo>>.broadcast();
  final _helperCountController = StreamController<int>.broadcast();
  final _connectivityController = StreamController<bool>.broadcast();
  final _commandCenterLogController = StreamController<CommandLog>.broadcast();
  final _routeHistoryController =
      StreamController<List<RoutePoint>>.broadcast();

  bool _isTracking = false;
  bool _isSosActive = false;
  bool _isConnected = true;
  StreamSubscription<LocationData>? _locationSub;
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  DocumentReference? _userLocationRef;
  Timer? _updateTimer;
  Timer? _routeHistoryTimer;
  final List<RoutePoint> _routeHistory = [];
  final List<CommandLog> _commandLogs = [];

  AdvancedLiveTrackingService._internal();

  factory AdvancedLiveTrackingService() => _instance;

  // Getters
  Stream<Map<String, LiveTrackingData>> get liveTracking =>
      _liveTrackingController.stream;
  Stream<List<HelperInfo>> get sosHelpers => _sosHelpersController.stream;
  Stream<int> get helperCount => _helperCountController.stream;
  Stream<bool> get connectivity => _connectivityController.stream;
  Stream<CommandLog> get commandCenterLogs =>
      _commandCenterLogController.stream;
  Stream<List<RoutePoint>> get routeHistory => _routeHistoryController.stream;

  bool get isTracking => _isTracking;
  bool get isSosActive => _isSosActive;
  bool get isConnected => _isConnected;
  FirebaseAuth get auth => _auth;

  // ────────────────────────────────────────────────────────────
  // INITIALIZATION
  // ────────────────────────────────────────────────────────────

  Future<void> init() async {
    // Monitor connectivity
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((result) {
      final isConnected = result != ConnectivityResult.none;
      _isConnected = isConnected;
      _connectivityController.add(isConnected);

      _addLog(
        type: 'connectivity',
        message: isConnected
            ? '✓ Internet Connected'
            : '✗ Internet Disconnected (Offline)',
        icon: isConnected ? '📡' : '📵',
      );
    });

    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isConnected = result != ConnectivityResult.none;
  }

  // ────────────────────────────────────────────────────────────
  // LIVE TRACKING
  // ────────────────────────────────────────────────────────────

  Future<void> startLiveTracking() async {
    if (_isTracking) return;
    _isTracking = true;

    final user = _auth.currentUser;
    if (user == null) return;

    _userLocationRef = _firestore.collection('live_tracking').doc(user.uid);

    // Initialize location service
    if (!LocationService.instance.isTracking) {
      await LocationService.instance.requestPermission();
      LocationService.instance.startTracking();
    }

    _addLog(
      type: 'tracking_start',
      message: 'Live Tracking Started',
      icon: '📍',
    );

    // Start listening to location changes
    _locationSub?.cancel();
    _locationSub =
        LocationService.instance.onLocationChanged.listen((location) {
      _updateLocationInFirebase(location);
      _addRoutePoint(location);
    });

    // Refresh nearby users every 5s (was 2s). Half the Firestore/Play-Services
    // load with no real loss for live tracking, so the app stays responsive.
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _listenToNearbyUsers();
    });

    // Store route history every 5 seconds
    _routeHistoryTimer?.cancel();
    _routeHistoryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _routeHistoryController.add(List.from(_routeHistory));
    });
  }

  Future<void> stopLiveTracking() async {
    _isTracking = false;
    _locationSub?.cancel();
    _updateTimer?.cancel();
    _routeHistoryTimer?.cancel();

    final user = _auth.currentUser;
    if (user != null) {
      await _userLocationRef?.delete().catchError((_) {});
    }

    _addLog(
      type: 'tracking_stop',
      message: 'Live Tracking Stopped',
      icon: '⏹️',
    );
  }

  Future<void> _updateLocationInFirebase(LocationData location) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Check if we have internet connection
      final locationData = LiveTrackingData(
        userId: user.uid,
        userName: user.displayName ?? 'User',
        latitude: location.latitude,
        longitude: location.longitude,
        timestamp: DateTime.now(),
        isOnline: _isConnected,
        accuracy: location.accuracy,
        speed: location.speed,
      );

      // Try to sync with Firebase if connected
      if (_isConnected) {
        await _userLocationRef?.set(
          locationData.toFirestore(),
          SetOptions(merge: true),
        );
      } else {
        // Store locally for later sync
        _addLog(
          type: 'offline_store',
          message: 'Storing location locally (no internet)',
          icon: '💾',
        );
      }
    } catch (e) {
      _addLog(
        type: 'error',
        message: 'Location update failed: ${e.toString()}',
        icon: '❌',
      );
    }
  }

  void _addRoutePoint(LocationData location) {
    _routeHistory.add(
      RoutePoint(
        latitude: location.latitude,
        longitude: location.longitude,
        timestamp: DateTime.now(),
        speed: location.speed,
        accuracy: location.accuracy,
      ),
    );

    // Keep only last 100 points in memory
    if (_routeHistory.length > 100) {
      _routeHistory.removeAt(0);
    }
  }

  Future<void> _listenToNearbyUsers() async {
    final user = _auth.currentUser;
    if (user == null || !_isTracking) return;

    try {
      final userLocationSnap = await _userLocationRef?.get();
      if (userLocationSnap?.data() == null) return;

      final data = userLocationSnap!.data() as Map<String, dynamic>;
      final userLat = data['latitude'] as double;
      final userLon = data['longitude'] as double;

      // Query nearby users (within 5km)
      final nearby = await _firestore
          .collection('live_tracking')
          .where('latitude', isGreaterThan: userLat - 0.05)
          .where('latitude', isLessThan: userLat + 0.05)
          .get();

      final trackingMap = <String, LiveTrackingData>{};
      for (var doc in nearby.docs) {
        if (doc.id != user.uid) {
          trackingMap[doc.id] = LiveTrackingData.fromFirestore(doc.data());
        }
      }

      _liveTrackingController.add(trackingMap);
    } catch (e) {
      debugPrint('Error listening to nearby users: $e');
    }
  }

  // ────────────────────────────────────────────────────────────
  // COMMUNITY SOS
  // ────────────────────────────────────────────────────────────

  Future<SOSAlert?> activateSOS() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    _isSosActive = true;

    try {
      final location = await LocationService.instance.onLocationChanged.first;

      // Get place name
      String placeName = 'Unknown Location';
      try {
        final url = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?lat=${location.latitude}&lon=${location.longitude}&format=json');
        final response = await http.get(
          url,
          headers: {'User-Agent': 'SmartSafeApp/1.0'},
        ).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          placeName = data['display_name'] ?? 'Unknown Location';
        }
      } catch (_) {}

      // Create SOS alert
      final sosRef = await _firestore.collection('sos_alerts').add({
        'userId': user.uid,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'helpers': [],
        'placeName': placeName,
      });

      _addLog(
        type: 'sos_activated',
        message: 'SOS Activated at $placeName',
        icon: '🆘',
      );

      // Start broadcasting SOS
      await startLiveTracking();
      _broadcastSOSAlert(location, placeName);

      return SOSAlert(
        alertId: sosRef.id,
        userId: user.uid,
        latitude: location.latitude,
        longitude: location.longitude,
        createdAt: DateTime.now(),
        placeName: placeName,
      );
    } catch (e) {
      _addLog(
        type: 'error',
        message: 'SOS Activation Error: ${e.toString()}',
        icon: '❌',
      );
      return null;
    }
  }

  Future<void> deactivateSOS() async {
    _isSosActive = false;
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final snap = await _firestore
            .collection('sos_alerts')
            .where('userId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'active')
            .get();
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.update(doc.reference, {'status': 'resolved'});
        }
        await batch.commit();
      } catch (e) {
        print('Error updating sos_alerts on deactivate: $e');
      }

      try {
        final notifs = await _firestore
            .collection('notifications')
            .where('sosUserId', isEqualTo: user.uid)
            .get();
        final batch = _firestore.batch();
        for (final n in notifs.docs) {
          batch.update(n.reference, {
            'read': true,
            'status': 'resolved',
          });
        }
        await batch.commit();
      } catch (e) {
        print('Error updating notifications on deactivate: $e');
      }
    }
    await stopLiveTracking();

    _addLog(
      type: 'sos_deactivated',
      message: 'SOS Deactivated - Help No Longer Needed',
      icon: '✓',
    );
  }

  Future<void> _broadcastSOSAlert(
      LocationData location, String placeName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Notify nearby users
      final nearby = await _firestore
          .collection('live_tracking')
          .where('latitude', isGreaterThan: location.latitude - 0.05)
          .where('latitude', isLessThan: location.latitude + 0.05)
          .get();

      int notifiedCount = 0;
      for (var doc in nearby.docs) {
        if (doc.id != user.uid) {
          await _firestore.collection('notifications').add({
            'targetUserId': doc.id,
            'type': 'sos_alert',
            'sosUserId': user.uid,
            'latitude': location.latitude,
            'longitude': location.longitude,
            'placeName': placeName,
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
          });
          notifiedCount++;
        }
      }

      _addLog(
        type: 'notifications_sent',
        message: 'Notifying $notifiedCount contacts nearby',
        icon: '📢',
      );
    } catch (e) {
      debugPrint('Error broadcasting SOS: $e');
    }
  }

  // ────────────────────────────────────────────────────────────
  // HELPER MANAGEMENT
  // ────────────────────────────────────────────────────────────

  Future<void> respondToSOS(String sosUserId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final location = await LocationService.instance.onLocationChanged.first;

      // Find and update the SOS alert
      final sosSnapshots = await _firestore
          .collection('sos_alerts')
          .where('userId', isEqualTo: sosUserId)
          .where('status', isEqualTo: 'active')
          .get();

      for (var doc in sosSnapshots.docs) {
        await doc.reference.update({
          'helpers': FieldValue.arrayUnion([
            {
              'helperId': user.uid,
              'respondedAt': FieldValue.serverTimestamp(),
              'status': 'arriving',
            }
          ]),
        });
      }

      // Start helper tracking
      await _firestore
          .collection('live_tracking')
          .doc('${user.uid}_helper')
          .set({
        'userId': user.uid,
        'helpingUserId': sosUserId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'isHelper': true,
        'status': 'arriving',
        'isOnline': _isConnected,
      });

      if (!_isTracking) {
        await startLiveTracking();
      }

      _addLog(
        type: 'help_offered',
        message: 'Responded to help (Status: Arriving)',
        icon: '🚗',
      );
    } catch (e) {
      _addLog(
        type: 'error',
        message: 'Error responding to SOS: ${e.toString()}',
        icon: '❌',
      );
    }
  }

  Future<void> updateHelperStatus(String status) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('live_tracking').doc(user.uid).update({
        'status': status,
        'timestamp': FieldValue.serverTimestamp(),
      });

      final statusText = status == 'arrived'
          ? 'Arrived at location'
          : status == 'helping'
              ? 'Providing assistance'
              : 'On the way';

      _addLog(
        type: 'status_update',
        message: 'Status Updated: $statusText',
        icon: '📍',
      );
    } catch (e) {
      debugPrint('Error updating helper status: $e');
    }
  }

  Stream<List<HelperInfo>> getHelpersForSOS(String sosUserId) {
    return _firestore
        .collection('sos_alerts')
        .where('userId', isEqualTo: sosUserId)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return [];

      final doc = snap.docs.first;
      final helpers =
          (doc['helpers'] as List? ?? []).cast<Map<String, dynamic>>();

      final helperInfoList = <HelperInfo>[];
      double userLat = 0, userLon = 0;

      // Get user location
      final userSnap =
          await _firestore.collection('live_tracking').doc(sosUserId).get();
      if (userSnap.exists) {
        userLat = userSnap['latitude'] ?? 0.0;
        userLon = userSnap['longitude'] ?? 0.0;
      }

      for (var helper in helpers) {
        final helperId = helper['helperId'] as String;
        final helperLocationSnap =
            await _firestore.collection('live_tracking').doc(helperId).get();

        if (helperLocationSnap.exists) {
          final data = helperLocationSnap.data()!;
          final helperLat = data['latitude'] ?? 0.0;
          final helperLon = data['longitude'] ?? 0.0;

          final distance =
              _calculateDistance(userLat, userLon, helperLat, helperLon);
          final eta = _calculateETA(distance);

          helperInfoList.add(
            HelperInfo(
              userId: helperId,
              name: data['userName'] ?? 'Helper',
              latitude: helperLat,
              longitude: helperLon,
              status: data['status'] ?? 'arriving',
              timestamp:
                  (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
              distanceToUser: distance,
              etaSeconds: eta,
              isOnline: data['isOnline'] ?? true,
            ),
          );
        }
      }

      _helperCountController.add(helperInfoList.length);
      _sosHelpersController.add(helperInfoList);
      return helperInfoList;
    });
  }

  // ────────────────────────────────────────────────────────────
  // UTILITIES
  // ────────────────────────────────────────────────────────────

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = (lat2 - lat1) * 3.14159 / 180;
    final dLon = (lon2 - lon1) * 3.14159 / 180;
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * 3.14159 / 180) *
            cos(lat2 * 3.14159 / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  int _calculateETA(double distanceKm) {
    // Assuming average speed of 30 km/h in city
    return ((distanceKm * 60) / 30).toInt() * 60; // Return in seconds
  }

  void _addLog({
    required String type,
    required String message,
    required String icon,
  }) {
    final log = CommandLog(
      type: type,
      message: message,
      icon: icon,
      timestamp: DateTime.now(),
    );
    _commandLogs.add(log);
    _commandCenterLogController.add(log);

    // Keep only last 50 logs
    if (_commandLogs.length > 50) {
      _commandLogs.removeAt(0);
    }
  }

  List<CommandLog> getCommandLogs() => List.from(_commandLogs);

  void dispose() {
    _locationSub?.cancel();
    _connectivitySub?.cancel();
    _updateTimer?.cancel();
    _routeHistoryTimer?.cancel();
    _liveTrackingController.close();
    _sosHelpersController.close();
    _helperCountController.close();
    _connectivityController.close();
    _commandCenterLogController.close();
    _routeHistoryController.close();
  }
}

// ─────────────────────────────────────────────────────────────
// COMMAND LOG
// ─────────────────────────────────────────────────────────────

class CommandLog {
  final String type; // 'tracking_start', 'sos_activated', 'help_offered', etc.
  final String message;
  final String icon;
  final DateTime timestamp;

  CommandLog({
    required this.type,
    required this.message,
    required this.icon,
    required this.timestamp,
  });
}
