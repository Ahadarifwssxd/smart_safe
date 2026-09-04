import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'location_service.dart';
import 'push_sender.dart';
import '../utils/phone_utils.dart';

/// Radius (km) within which community helpers are considered "nearby".
const double kNearbyRadiusKm = 10.0;

/// Great-circle distance in km between two lat/lng points (Haversine).
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const earthR = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return earthR * 2 * atan2(sqrt(a), sqrt(1 - a));
}

class LiveTrackingData {
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isHelper;
  final String? status; // 'arriving', 'arrived', 'helping'

  LiveTrackingData({
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isHelper = false,
    this.status,
  });
}

class RoutePoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
}

class HelperInfo {
  final String userId;
  final String name;
  final double latitude;
  final double longitude;
  final String address;
  final String status; // 'arriving', 'arrived', 'helping'
  final DateTime timestamp;
  final List<RoutePoint> route;

  HelperInfo({
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address = '',
    required this.status,
    required this.timestamp,
    this.route = const [],
  });
}

class LiveTrackingService {
  static final LiveTrackingService _instance = LiveTrackingService._internal();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Streams
  final _liveTrackingController =
      StreamController<List<LiveTrackingData>>.broadcast();
  final _sosHelpersController = StreamController<List<HelperInfo>>.broadcast();
  final _helperCountController = StreamController<int>.broadcast();

  bool _isTracking = false;
  bool _isSosActive = false;
  StreamSubscription<LocationData>? _locationSub;
  DocumentReference? _userLocationRef;
  // Event-driven nearby-users feed (replaces the old 3-second polling timer
  // that re-queried Firestore twice per tick for as long as tracking ran).
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _nearbySub;
  String? _activeHelpingUserId;
  String _helperStatus = 'arriving';
  String? _lastKnownAddress;

  // Minimum gap between live_tracking doc writes. The tracking AND presence
  // subscriptions can both fire on the same position update (double write),
  // and fast GPS bursts fire several updates in a row — a 5s throttle keeps
  // the map fresh at a fraction of the write volume.
  DateTime? _lastLocationWrite;
  static const _locationWriteInterval = Duration(seconds: 5);

  // Presence (so a user can be FOUND as "nearby" for community SOS even when
  // they aren't actively tracking/helping).
  StreamSubscription<LocationData>? _presenceSub;
  Timer? _presenceTimer;
  bool _presenceOn = false;

  LiveTrackingService._internal();

  factory LiveTrackingService() => _instance;

  Stream<List<LiveTrackingData>> get liveTracking =>
      _liveTrackingController.stream;
  Stream<List<HelperInfo>> get sosHelpers => _sosHelpersController.stream;
  Stream<int> get helperCount => _helperCountController.stream;

  bool get isTracking => _isTracking;
  bool get isSosActive => _isSosActive;

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

    // Start listening to location changes
    _locationSub?.cancel();
    _locationSub =
        LocationService.instance.onLocationChanged.listen((location) {
      _updateLocationInFirebase(location);
    });

    // Nearby users: one Firestore LISTENER instead of a query every 3
    // seconds. Firestore pushes only document deltas after the initial sync,
    // so the map stays live at a fraction of the reads/writes.
    _nearbySub?.cancel();
    _nearbySub = _firestore
        .collection('live_tracking')
        .snapshots()
        .listen((snap) => _processNearbyUsers(snap),
            onError: (e) => print('Error listening to nearby users: $e'));
  }

  Future<void> stopLiveTracking() async {
    _isTracking = false;
    _locationSub?.cancel();
    _nearbySub?.cancel();
    _activeHelpingUserId = null;
    // Keep presence alive if it's running so the user stays discoverable; only
    // remove the doc entirely when neither tracking nor presence is active.
    if (!_presenceOn) {
      await _userLocationRef?.delete().catchError((_) {});
    }
  }

  /// Lightweight PRESENCE: keeps the signed-in user's location in
  /// `live_tracking` so they can be found as a nearby person when someone raises
  /// a Community SOS — even if they're just using the app normally. Call once
  /// after login. Without this, broadcasts find nobody (the "0 help" problem).
  Future<void> startPresence() async {
    final user = _auth.currentUser;
    if (user == null || _presenceOn) return;
    _presenceOn = true;
    _userLocationRef ??=
        _firestore.collection('live_tracking').doc(user.uid);

    if (!LocationService.instance.isTracking) {
      await LocationService.instance.requestPermission();
      LocationService.instance.startTracking();
    }

    // Write an immediate fix so the user shows up right away.
    final loc = await LocationService.instance.getCurrentLocation();
    if (loc != null) await _updateLocationInFirebase(loc);

    // Update on movement.
    _presenceSub?.cancel();
    _presenceSub =
        LocationService.instance.onLocationChanged.listen((location) {
      _updateLocationInFirebase(location);
    });

    // Refresh periodically so the timestamp stays fresh.
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      final l = await LocationService.instance.getCurrentLocation();
      if (l != null) await _updateLocationInFirebase(l);
    });
  }

  /// Stops presence broadcasting and removes the user's location doc (logout).
  Future<void> stopPresence() async {
    _presenceOn = false;
    _presenceSub?.cancel();
    _presenceTimer?.cancel();
    if (!_isTracking) {
      await _userLocationRef?.delete().catchError((_) {});
    }
  }

  Future<void> _updateLocationInFirebase(LocationData location) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Throttle: skip writes that arrive within a few seconds of the last one.
    final now = DateTime.now();
    if (_lastLocationWrite != null &&
        now.difference(_lastLocationWrite!) < _locationWriteInterval) {
      return;
    }
    _lastLocationWrite = now;

    try {
      final isHelper = _activeHelpingUserId != null;
      await _userLocationRef?.set(
        {
          'userId': user.uid,
          'userName':
              user.displayName ?? user.email?.split('@').first ?? 'User',
          'latitude': location.latitude,
          'longitude': location.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'accuracy': location.accuracy,
          'speed': location.speed,
          'address': _lastKnownAddress,
          'isHelper': isHelper,
          if (isHelper) 'helpingUserId': _activeHelpingUserId,
          if (isHelper) 'status': _helperStatus,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      print('Error updating location: $e');
    }
  }

  /// Maps a `live_tracking` snapshot to the nearby-users list. The user's own
  /// doc comes from the SAME snapshot (no extra read), other users are filtered
  /// by true great-circle distance in memory.
  void _processNearbyUsers(QuerySnapshot<Map<String, dynamic>> snap) {
    final user = _auth.currentUser;
    if (user == null || !_isTracking) return;

    Map<String, dynamic>? myData;
    for (final doc in snap.docs) {
      if (doc.id == user.uid) {
        myData = doc.data();
        break;
      }
    }
    // Null-safe: an address-first doc (updateCurrentAddress) may have no
    // lat/lng yet — skip until a real fix lands.
    final userLat = (myData?['latitude'] as num?)?.toDouble();
    final userLon = (myData?['longitude'] as num?)?.toDouble();
    if (userLat == null || userLon == null) return;

    final trackingList = snap.docs
        .where((doc) => doc.id != user.uid)
        .map((doc) {
          final d = doc.data();
          return LiveTrackingData(
            userId: d['userId'] ?? '',
            userName: d['userName'] ?? 'Unknown',
            latitude: (d['latitude'] ?? 0.0).toDouble(),
            longitude: (d['longitude'] ?? 0.0).toDouble(),
            timestamp:
                (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            isHelper: d['isHelper'] ?? false,
            status: d['status'],
          );
        })
        .where((t) =>
            distanceKm(userLat, userLon, t.latitude, t.longitude) <=
            kNearbyRadiusKm)
        .toList();

    _liveTrackingController.add(trackingList);
  }

  // ────────────────────────────────────────────────────────────
  // COMMUNITY SOS
  // ────────────────────────────────────────────────────────────

  Future<void> activateSOS() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _isSosActive = true;

    try {
      final location = await _getFreshLocation();
      if (location == null) return;

      // Create SOS alert
      await _firestore.collection('sos_alerts').add({
        'userId': user.uid,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
        'helpers': [],
      });

      // Start broadcasting SOS
      await startLiveTracking();
      _broadcastSOSAlert(location);
    } catch (e) {
      print('Error activating SOS: $e');
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
  }

  Future<void> updateCurrentAddress(String address) async {
    _lastKnownAddress = address;
    final user = _auth.currentUser;
    if (user == null || address.trim().isEmpty) return;

    await _firestore.collection('live_tracking').doc(user.uid).set(
      {
        'address': address.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _broadcastSOSAlert(LocationData location) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final senderName =
          user.displayName ?? user.email?.split('@').first ?? 'A SmartSafe user';

      // Professional, ready-to-read community alert (the public sees this).
      final mapsLink =
          'https://maps.google.com/?q=${location.latitude},${location.longitude}';
      final message = '🆘 SMARTSAFE — COMMUNITY SOS 🆘\n'
          'SOMEONE NEEDS HELP\n\n'
          '$senderName is in danger and has asked the community for help.\n'
          '($senderName khatre mein hai — madad maang rahe hain.)\n\n'
          '📍 Their LIVE location:\n'
          '$mapsLink\n'
          'Tap to see exactly where they are.\n\n'
          'If you can help RIGHT NOW:\n'
          '• Open the app and tap "I\'m coming to help", or\n'
          '• Go to their location, or\n'
          '• Call Police 15 / Rescue 1122.\n\n'
          'Even one person responding can save a life — please don\'t ignore this.\n'
          '— SmartSafe Community Alert 🛡️';

      // Community SOS → everyone within kNearbyRadiusKm (10 km). Firestore can
      // range-filter only ONE field, so we bound latitude (~0.11° ≈ 12 km band)
      // in the query and filter the true great-circle distance in memory.
      final nearby = await _firestore
          .collection('live_tracking')
          .where('latitude', isGreaterThan: location.latitude - 0.11)
          .where('latitude', isLessThan: location.latitude + 0.11)
          .get();

      final batch = _firestore.batch();
      final pushTargets = <String>[];
      var notified = 0;
      for (final doc in nearby.docs) {
        if (doc.id == user.uid) continue;
        final d = doc.data();
        final lat = (d['latitude'] as num?)?.toDouble() ?? 0.0;
        final lon = (d['longitude'] as num?)?.toDouble() ?? 0.0;
        if (distanceKm(location.latitude, location.longitude, lat, lon) >
            kNearbyRadiusKm) {
          continue;
        }
        pushTargets.add(doc.id);
        final ref = _firestore.collection('notifications').doc();
        batch.set(ref, {
          'targetUserId': doc.id,
          'type': 'sos_alert',
          'sosUserId': user.uid,
          'senderName': senderName,
          'message': message,
          'latitude': location.latitude,
          'longitude': location.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
          // Ride-hailing style claim: first responder claims it; everyone else
          // is then told help is on the way.
          'claimed': false,
          'responderName': '',
        });
        notified++;
      }
      if (notified > 0) await batch.commit();
      print('Broadcast SOS to $notified user(s) within ${kNearbyRadiusKm}km');

      // Push to those nearby helpers even when their app is closed.
      if (pushTargets.isNotEmpty) {
        await PushSender.instance.pushSos(
          targetUserIds: pushTargets,
          type: 'sos_alert',
          senderName: senderName,
          sosUserId: user.uid,
          latitude: location.latitude.toString(),
          longitude: location.longitude.toString(),
        );
      }

      // Also inform the user's OWN emergency contacts that they raised an SOS,
      // so family/friends are looped in alongside the nearby community.
      await _notifyEmergencyContacts(user.uid, senderName, message, mapsLink);
    } catch (e) {
      print('Error broadcasting SOS: $e');
    }
  }

  /// Writes an in-app SOS notification to each of the user's emergency contacts
  /// who use SmartSafe (matched by phone), so they're informed help is needed.
  /// The Cloud Function then pushes it even when their app is closed.
  Future<void> _notifyEmergencyContacts(
      String uid, String senderName, String message, String locationLink) async {
    try {
      final contacts = await _firestore
          .collection('emergency_contacts')
          .where('userId', isEqualTo: uid)
          .get();
      if (contacts.docs.isEmpty) return;
      final batch = _firestore.batch();
      final pushTargets = <String>[];
      var count = 0;
      for (final c in contacts.docs) {
        final phone = c.data()['phone']?.toString() ?? '';
        final norm = normalizePhone(phone);
        if (norm.isEmpty) continue;
        final us = await _firestore
            .collection('users')
            .where('phoneNormalized', isEqualTo: norm)
            .limit(1)
            .get();
        if (us.docs.isEmpty) continue; // contact isn't a SmartSafe user
        pushTargets.add(us.docs.first.id);
        final ref = _firestore.collection('notifications').doc();
        batch.set(ref, {
          'targetUserId': us.docs.first.id,
          'type': 'sos_personal',
          'sosUserId': uid,
          'senderName': senderName,
          'message': message,
          'locationLink': locationLink,
          'read': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
        count++;
      }
      if (count > 0) await batch.commit();
      print('Community SOS also informed $count emergency contact(s)');

      // Push to those contacts even when their app is closed.
      if (pushTargets.isNotEmpty) {
        await PushSender.instance.pushSos(
          targetUserIds: pushTargets,
          type: 'sos_personal',
          senderName: senderName,
          sosUserId: uid,
        );
      }
    } catch (e) {
      print('Error notifying emergency contacts: $e');
    }
  }

  // ────────────────────────────────────────────────────────────
  // HELPER MANAGEMENT
  // ────────────────────────────────────────────────────────────

  Future<void> respondToSOS(String sosUserId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      _activeHelpingUserId = sosUserId;
      _helperStatus = 'arriving';
      final responderName =
          user.displayName ?? user.email?.split('@').first ?? 'A helper';
      final location = await _getFreshLocation();
      if (location == null) return;

      // Add self as helper AND claim the SOS (first responder wins). Note:
      // FieldValue.serverTimestamp() is NOT allowed inside an array element,
      // so we use Timestamp.now() for the helper entry.
      bool iClaimed = false;
      final snap = await _firestore
          .collection('sos_alerts')
          .where('userId', isEqualTo: sosUserId)
          .where('status', isEqualTo: 'active')
          .get();
      for (final doc in snap.docs) {
        await _firestore.runTransaction((tx) async {
          final fresh = await tx.get(doc.reference);
          final data = fresh.data() ?? {};
          final helpers = List<dynamic>.from(data['helpers'] ?? []);
          helpers.add({
            'helperId': user.uid,
            'respondedAt': Timestamp.now(),
            'status': 'arriving',
          });
          final updates = <String, dynamic>{'helpers': helpers};
          // Claim only if nobody has claimed yet.
          if ((data['claimedBy'] ?? '').toString().isEmpty) {
            updates['claimedBy'] = user.uid;
            updates['responderName'] = responderName;
            updates['responderStatus'] = 'arriving';
            updates['claimedAt'] = Timestamp.now();
            iClaimed = true;
          }
          tx.update(doc.reference, updates);
        });
      }

      // Suppress the prompt for ME and tell every OTHER notified person that
      // help is on the way (ride-hailing style). IMPORTANT: use a SINGLE-field
      // query (sosUserId only) and filter type in memory — the old two-field
      // query (sosUserId + type) needed a composite index that was never
      // created, so it threw and the claim never propagated. That's why the
      // "I'm coming" prompt kept reappearing for everyone.
      try {
        final notifs = await _firestore
            .collection('notifications')
            .where('sosUserId', isEqualTo: sosUserId)
            .get();
        final batch = _firestore.batch();
        for (final n in notifs.docs) {
          final d = n.data();
          if (d['type'] != 'sos_alert') continue;
          if (d['targetUserId'] == user.uid) {
            // My own alert → mark read so it never prompts me again.
            batch.update(n.reference, {'read': true});
          } else if (iClaimed) {
            // Everyone else → "help is on the way", stop their prompt.
            batch.update(n.reference,
                {'claimed': true, 'responderName': responderName});
          }
        }
        await batch.commit();
      } catch (e) {
        print('Error propagating SOS claim: $e');
      }

      // Start live tracking as helper
      await _firestore.collection('live_tracking').doc(user.uid).set({
        'userId': user.uid,
        'userName':
            user.displayName ?? user.email?.split('@').first ?? 'Helper',
        'helpingUserId': sosUserId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'isHelper': true,
        'status': _helperStatus,
        'address': _lastKnownAddress,
      });

      if (!_isTracking) {
        await startLiveTracking();
      }
    } catch (e) {
      print('Error responding to SOS: $e');
    }
  }

  Future<void> updateHelperStatus(String status) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      _helperStatus = status;
      await _firestore
          .collection('live_tracking')
          .doc(user.uid)
          .update({'status': status});
    } catch (e) {
      print('Error updating helper status: $e');
    }
  }

  Future<LocationData?> _getFreshLocation() async {
    if (!LocationService.instance.isTracking) {
      await LocationService.instance.requestPermission();
      LocationService.instance.startTracking();
    }

    final current = await LocationService.instance.getCurrentLocation();
    if (current != null) return current;

    try {
      return await LocationService.instance.onLocationChanged.first.timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      return null;
    }
  }

  /// Streams the helpers responding to the user's ACTIVE community SOS.
  ///
  /// EVENT-DRIVEN (replaces the old `while(true)` loop that queried Firestore
  /// every 2 seconds + N single-doc reads per tick, forever): Firestore pushes
  /// updates when the alert doc changes (a helper joins/claims) AND when each
  /// helper's live-tracking doc changes (they move). Cancelling the returned
  /// subscription cancels every underlying listener.
  Stream<List<HelperInfo>> getHelpersForSOS(String sosUserId) {
    late final StreamController<List<HelperInfo>> controller;
    final helperSubs = <
        String,
        StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final helperDocs = <String, Map<String, dynamic>>{};
    List<Map<String, dynamic>> latestHelpers = const [];
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? alertsSub;
    var closed = false;

    void emit() {
      if (closed) return;
      final list = <HelperInfo>[];
      for (final helper in latestHelpers) {
        // Skip malformed/legacy helper entries instead of letting one bad cast
        // throw and kill the whole helper-tracking stream.
        final helperId = helper['helperId'] as String?;
        // Skip malformed entries AND the SOS raiser themselves — the person who
        // raised the alert must never appear as their own "helper".
        if (helperId == null || helperId.isEmpty || helperId == sosUserId) {
          continue;
        }
        final data = helperDocs[helperId];
        if (data == null) continue;
        final rawName = data['userName']?.toString().trim() ?? '';
        list.add(
          HelperInfo(
            userId: helperId,
            name: rawName.isNotEmpty ? rawName : 'Helper',
            latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
            address: data['address']?.toString() ?? '',
            status: data['status']?.toString() ?? 'arriving',
            timestamp: (data['timestamp'] as Timestamp?)?.toDate() ??
                DateTime.now(),
          ),
        );
      }
      _helperCountController.add(list.length);
      _sosHelpersController.add(list);
      controller.add(list);
    }

    void syncHelperSubscriptions() {
      final ids = latestHelpers
          .map((h) => h['helperId'] as String?)
          .whereType<String>()
          .where((id) => id.isNotEmpty && id != sosUserId)
          .toSet();
      // Stop listening to helpers that are no longer on the alert.
      helperSubs.removeWhere((id, sub) {
        if (!ids.contains(id)) {
          sub.cancel();
          helperDocs.remove(id);
          return true;
        }
        return false;
      });
      // Listen to each helper's live location — each snapshot fires immediately
      // with the current doc and again whenever the helper moves.
      for (final id in ids) {
        helperSubs.putIfAbsent(id, () {
          return _firestore
              .collection('live_tracking')
              .doc(id)
              .snapshots()
              .listen((snap) {
            final data = snap.data();
            if (snap.exists && data != null) {
              helperDocs[id] = data;
            } else {
              helperDocs.remove(id);
            }
            emit();
          }, onError: (e) => print('Helper location listener error: $e'));
        });
      }
    }

    controller = StreamController<List<HelperInfo>>.broadcast(
      onListen: () {
        alertsSub = _firestore
            .collection('sos_alerts')
            .where('userId', isEqualTo: sosUserId)
            .where('status', isEqualTo: 'active')
            .snapshots()
            .listen((snap) {
          if (snap.docs.isEmpty) {
            latestHelpers = const [];
            for (final sub in helperSubs.values) {
              sub.cancel();
            }
            helperSubs.clear();
            helperDocs.clear();
            emit();
            return;
          }
          final doc = snap.docs.first;
          latestHelpers =
              (doc['helpers'] as List? ?? []).cast<Map<String, dynamic>>().toList();
          syncHelperSubscriptions();
          emit();
        }, onError: (e) => print('getHelpersForSOS error: $e'));
      },
      onCancel: () {
        closed = true;
        alertsSub?.cancel();
        for (final sub in helperSubs.values) {
          sub.cancel();
        }
        helperSubs.clear();
      },
    );
    return controller.stream;
  }

  void dispose() {
    _locationSub?.cancel();
    _nearbySub?.cancel();
    _liveTrackingController.close();
    _sosHelpersController.close();
    _helperCountController.close();
  }
}
