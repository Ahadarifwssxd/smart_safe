import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../navigation/dark_route.dart';
import '../services/app_firestore_service.dart';
import '../services/live_tracking_service.dart';
import '../services/location_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class CommunitySosPage extends StatefulWidget {
  final VoidCallback? onCancel;

  const CommunitySosPage({super.key, this.onCancel});

  /// Opens Community SOS with standard app transition.
  static void open(BuildContext context, {VoidCallback? onCancel}) {
    Navigator.push(
      context,
      darkRoute(CommunitySosPage(onCancel: onCancel)),
    );
  }

  @override
  State<CommunitySosPage> createState() => _CommunitySosPageState();
}

class _CommunitySosPageState extends State<CommunitySosPage>
    with TickerProviderStateMixin {
  // ── Animations ───────────────────────────────────────────────
  late List<AnimationController> _rings; // 3 expanding pulse rings
  late AnimationController _sosScale; // SOS button pulse
  late AnimationController _mapPinPulse; // map pin glow
  late List<AnimationController> _waveBars; // wave bars in status

  // ── State ─────────────────────────────────────────────────────
  bool _sosActive = false;
  int _alertCount = 0;
  int _respondCount = 0;
  String _statusText = 'Press SOS to alert nearby people';
  String _nearestDist = 'N/A';
  final List<_NearbyPerson> _notified = [];

  final List<Offset> _mapDots = [
    const Offset(.35, .28),
    const Offset(.65, .60),
    const Offset(.72, .40),
    const Offset(.28, .70),
  ];

  final List<Timer> _timers = [];

  // Real responder tracking (helpers who accepted) + continuous live location.
  final _tracking = LiveTrackingService();
  StreamSubscription<List<HelperInfo>>? _helpersSub;
  List<HelperInfo> _responders = [];

  // Location and Nearby Users State
  StreamSubscription<LocationData>? _locationSub;
  StreamSubscription<QuerySnapshot>? _usersSub;
  double _myLat = 24.8607; // Saddar, Karachi lat
  double _myLon = 67.0011; // Saddar, Karachi lon
  String _myPlaceName = 'Saddar, Karachi';
  DateTime? _lastGeocodeTime;
  List<_NearbyPerson> _realNearbyUsers = [];

  // Only REAL nearby SmartSafe users — no demo/simulated people.
  List<_NearbyPerson> get _displayUsers => _realNearbyUsers.take(8).toList();

  @override
  void initState() {
    super.initState();

    // Rings
    _rings = List.generate(3, (i) {
      final c = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1800));
      Future.delayed(Duration(milliseconds: i * 600), () {
        if (mounted) c.repeat();
      });
      return c;
    });

    // SOS scale
    _sosScale = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);

    // Map pin
    _mapPinPulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);

    // Wave bars
    _waveBars = List.generate(5, (i) {
      final c = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 600));
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });

    _initLocation();
    _listenToNearbyUsers();
  }

  void _initLocation() async {
    if (!LocationService.instance.isTracking) {
      final err = await LocationService.instance.requestPermission();
      if (err == null) {
        LocationService.instance.startTracking();
      }
    }
    _startListening();
  }

  void _startListening() {
    _locationSub?.cancel();
    _locationSub = LocationService.instance.onLocationChanged.listen((data) {
      if (mounted) {
        setState(() {
          _myLat = data.latitude;
          _myLon = data.longitude;
        });
        _fetchPlaceName(data.latitude, data.longitude);
      }
    });
  }

  Future<void> _fetchPlaceName(double lat, double lon) async {
    final now = DateTime.now();
    if (_lastGeocodeTime != null &&
        now.difference(_lastGeocodeTime!).inSeconds < 10) {
      return;
    }
    _lastGeocodeTime = now;

    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json&accept-language=en');
      final response =
          await http.get(url, headers: {'User-Agent': 'SmartSafeApp/1.0'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'];
        if (displayName != null && mounted) {
          final parts = displayName.toString().split(',');
          final shortName = parts.take(3).join(',').trim();
          setState(() {
            _myPlaceName = shortName.isNotEmpty ? shortName : displayName;
          });
        }
      }
    } catch (_) {}
  }

  void _listenToNearbyUsers() {
    _usersSub?.cancel();
    _usersSub = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .listen((snap) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final List<_NearbyPerson> list = [];
      for (final doc in snap.docs) {
        if (doc.id == currentUid) continue;
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        if (data['isLocationSharingActive'] == true &&
            data['latitude'] != null &&
            data['longitude'] != null) {
          final name = data['name']?.toString() ??
              data['email']?.toString().split('@').first ??
              'SmartSafe User';
          final double lat = (data['latitude'] as num).toDouble();
          final double lon = (data['longitude'] as num).toDouble();
          final dist = _calculateDistance(_myLat, _myLon, lat, lon);

          if (dist <= kNearbyRadiusKm) {
            list.add(_NearbyPerson(
              name: name,
              role: data['role']?.toString() ?? 'SmartSafe User',
              dist: '${dist.toStringAsFixed(1)} km',
              color: _getRandomColor(name),
              init: name.isNotEmpty ? name[0].toUpperCase() : 'U',
              latitude: lat,
              longitude: lon,
              distanceKm: dist,
              uid: doc.id,
            ));
          }
        }
      }

      list.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

      if (mounted) {
        setState(() {
          _realNearbyUsers = list;
          // Nearest-help distance is always real (closest online user).
          _nearestDist =
              _realNearbyUsers.isNotEmpty ? _realNearbyUsers.first.dist : 'N/A';
        });
      }
    });
  }

  Color _getRandomColor(String name) {
    final colors = [C.accent, C.accent, C.warning, C.success, C.accent, C.accent];
    final index =
        name.codeUnits.fold<int>(0, (prev, element) => prev + element) %
            colors.length;
    return colors[index];
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Offset _getMapOffset(double otherLat, double otherLon, double width) {
    if (_myLat == 0.0 || _myLon == 0.0) {
      return const Offset(0.5, 0.5);
    }
    final dLat = otherLat - _myLat;
    final dLon = otherLon - _myLon;
    const p = 0.017453292519943295;
    final dyMeters = dLat * 111139.0;
    final dxMeters = dLon * 111139.0 * cos(_myLat * p);
    const maxRadius = 5000.0; // 5 km — matches kNearbyRadiusKm
    final dxFraction = (dxMeters / maxRadius).clamp(-0.9, 0.9);
    final dyFraction = (dyMeters / maxRadius).clamp(-0.9, 0.9);
    return Offset(0.5 + (dxFraction * 0.5), 0.5 - (dyFraction * 0.5));
  }

  void _triggerSOS() async {
    if (_sosActive) return;
    AppFirestoreService.instance.recordSosPress(
      source: 'community_sos',
      location: 'Community SOS — nearby alerts',
      alertType: 'Community SOS',
    );
    setState(() {
      _sosActive = true;
      _statusText = 'Broadcasting your live location to nearby people…';
      _notified.clear();
      _alertCount = 0;
      _respondCount = 0;
    });

    // REAL broadcast: write a push for every nearby SmartSafe user. The Cloud
    // Function `pushCommunitySosAlert` delivers each as an FCM notification.
    final usersToNotify = await _broadcastToNearby();

    if (!mounted) return;
    if (usersToNotify.isEmpty) {
      setState(() => _statusText =
          'No SmartSafe users nearby right now. Your SOS is LIVE — it will '
          'reach anyone who comes within range.');
      return;
    }

    // Stagger the reveal of the REAL people we just alerted.
    for (int i = 0; i < usersToNotify.length; i++) {
      final user = usersToNotify[i];
      final t = Timer(Duration(milliseconds: 400 + i * 500), () {
        if (!mounted) return;
        setState(() {
          _notified.add(user);
          _statusText = '${user.name} was alerted (${user.dist} away).';
          _nearestDist = usersToNotify.first.dist;
        });
      });
      _timers.add(t);
    }

    final finalT = Timer(
        Duration(milliseconds: 400 + usersToNotify.length * 500 + 400), () {
      if (!mounted) return;
      setState(() => _statusText =
          '${usersToNotify.length} nearby people alerted. Help is on the way.');
    });
    _timers.add(finalT);
  }

  /// Sends a REAL community SOS: gets a fresh location, then writes one
  /// `notifications` doc per nearby user so the Cloud Function pushes each an
  /// FCM alert. Returns the list of users actually alerted.
  Future<List<_NearbyPerson>> _broadcastToNearby() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    // Fresh GPS fix so the broadcast carries the exact current location.
    try {
      final loc = await LocationService.instance
          .getCurrentLocation()
          .timeout(const Duration(seconds: 6));
      if (loc != null) {
        _myLat = loc.latitude;
        _myLon = loc.longitude;
      }
    } catch (_) {}

    // Sender name from profile (falls back to auth display name).
    String senderName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'Someone nearby';
    try {
      final me =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final n = me.data()?['name']?.toString();
      if (n != null && n.trim().isNotEmpty) senderName = n.trim();
    } catch (_) {}

    final targets = List<_NearbyPerson>.from(_realNearbyUsers)
      ..removeWhere((p) => p.uid.isEmpty);

    if (targets.isNotEmpty) {
      try {
        final batch = FirebaseFirestore.instance.batch();
        final col = FirebaseFirestore.instance.collection('notifications');
        for (final p in targets) {
          batch.set(col.doc(), {
            'type': 'sos_alert',
            'targetUserId': p.uid,
            'sosUserId': uid,
            'senderName': senderName,
            'latitude': _myLat,
            'longitude': _myLon,
            'address': _myPlaceName,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      } catch (e) {
        debugPrint('[CommunitySOS] broadcast failed: $e');
      }
    }

    // Create the SOS record that helpers attach to when they respond.
    try {
      await FirebaseFirestore.instance.collection('sos_alerts').add({
        'userId': uid,
        'senderName': senderName,
        'latitude': _myLat,
        'longitude': _myLon,
        'address': _myPlaceName,
        'status': 'active',
        'helpers': [],
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CommunitySOS] sos_alert create failed: $e');
    }

    // Stream our location CONTINUOUSLY so responders track us in real time.
    await _tracking.startLiveTracking();
    _tracking.updateCurrentAddress(_myPlaceName);

    // Listen for REAL responders (helpers who accepted) — live count + names.
    _helpersSub?.cancel();
    _helpersSub = _tracking.getHelpersForSOS(uid).listen((helpers) {
      if (!mounted) return;
      setState(() {
        _responders = helpers;
        _respondCount = helpers.length;
        if (helpers.isNotEmpty) {
          final n = helpers.length;
          _statusText =
              '$n ${n == 1 ? 'person is' : 'people are'} responding — help is on the way.';
        }
      });
    });

    if (mounted) setState(() => _alertCount = targets.length);
    return targets;
  }

  void _cancel() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _helpersSub?.cancel();
    _helpersSub = null;

    // Stop streaming our location and mark the SOS resolved so helpers stop.
    _tracking.stopLiveTracking();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final q = await FirebaseFirestore.instance
            .collection('sos_alerts')
            .where('userId', isEqualTo: uid)
            .where('status', isEqualTo: 'active')
            .get();
        for (final d in q.docs) {
          d.reference.update({'status': 'cancelled'});
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _sosActive = false;
      _alertCount = 0;
      _respondCount = 0;
      _responders = [];
      _nearestDist =
          _displayUsers.isNotEmpty ? _displayUsers.first.dist : 'N/A';
      _notified.clear();
      _statusText = 'Press SOS to alert nearby people';
    });
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _usersSub?.cancel();
    _helpersSub?.cancel();
    for (final c in _rings) {
      c.dispose();
    }
    for (final c in _waveBars) {
      c.dispose();
    }
    for (final t in _timers) {
      t.cancel();
    }
    _sosScale.dispose();
    _mapPinPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: Stack(
          children: [
            const DotGrid(),
            SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header ────────────────────────────────────────────
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: _goBack,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: AppTheme.cardGradient,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: C.border),
                                ),
                                child: Icon(Icons.arrow_back_ios_new_rounded,
                                    color: C.textPrimary, size: 16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  const BrandTitle('Community SOS', size: 20),
                                  Text('Alert nearby people immediately',
                                      style: AppTheme.bodyFont.copyWith(
                                          color: C.textMuted, fontSize: 12)),
                                ])),
                            if (_sosActive)
                              Row(children: [
                                BlinkDot(color: C.accent, size: 8),
                                const SizedBox(width: 6),
                                Text('LIVE',
                                    style: TextStyle(
                                        color: C.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ]),
                          ]),

                      const SizedBox(height: 24),

                      // ── SOS Button with rings ─────────────────────────────
                      Center(
                          child: SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(alignment: Alignment.center, children: [
                          // 3 expanding rings
                          ...List.generate(
                              3,
                              (i) => AnimatedBuilder(
                                  animation: _rings[i],
                                  builder: (_, __) {
                                    final scale =
                                        Tween<double>(begin: .7, end: 1.4)
                                            .animate(CurvedAnimation(
                                                parent: _rings[i],
                                                curve: Curves.easeOut))
                                            .value;
                                    final opacity =
                                        Tween<double>(begin: .7, end: 0)
                                            .animate(CurvedAnimation(
                                                parent: _rings[i],
                                                curve: Curves.easeOut))
                                            .value;
                                    return Transform.scale(
                                        scale: scale,
                                        child: Opacity(
                                            opacity: opacity,
                                            child: Container(
                                                width: 110,
                                                height: 110,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: C.accent
                                                            .withOpacity(.5),
                                                        width: 2)))));
                                  })),

                          // SOS button
                          AnimatedBuilder(
                            animation: _sosScale,
                            builder: (_, child) => Transform.scale(
                                scale: _sosActive
                                    ? Tween<double>(begin: 1.0, end: 1.06)
                                        .animate(CurvedAnimation(
                                            parent: _sosScale,
                                            curve: Curves.easeInOut))
                                        .value
                                    : 1.0,
                                child: child),
                            child: GestureDetector(
                              onTap: _triggerSOS,
                              child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: AppTheme.sosGradient,
                                    border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.2),
                                        width: 2),
                                    boxShadow: AppTheme.glowShadow(C.accent,
                                        blur: _sosActive ? 30 : 18),
                                  ),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Text('SOS',
                                            style: TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                letterSpacing: 2)),
                                        Text(_sosActive ? 'ACTIVE' : 'PRESS',
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.white70,
                                                letterSpacing: 1.2)),
                                      ])),
                            ),
                          ),
                        ]),
                      )),

                      const SizedBox(height: 8),

                      // ── Status bar ────────────────────────────────────────
                      DCard(
                        borderColor: _sosActive ? C.accent : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(children: [
                          BlinkDot(color: _sosActive ? C.accent : C.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_statusText,
                                  style:
                                      TextStyle(color: C.textMuted, fontSize: 11))),
                          if (_sosActive)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(
                                  5,
                                  (i) => AnimatedBuilder(
                                      animation: _waveBars[i],
                                      builder: (_, __) => Container(
                                          width: 3,
                                          height: 5 + _waveBars[i].value * 10,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 1.5),
                                          decoration: BoxDecoration(
                                              color: C.accent,
                                              borderRadius:
                                                  BorderRadius.circular(2))))),
                            ),
                        ]),
                      ),

                      const SizedBox(height: 16),

                      // ── Stats row ─────────────────────────────────────────
                      Row(children: [
                        _Stat(
                            value: '$_alertCount',
                            label: 'Alerts sent',
                            color: C.accent),
                        const SizedBox(width: 8),
                        _Stat(
                            value: '$_respondCount',
                            label: 'Responding',
                            color: C.accent),
                        const SizedBox(width: 8),
                        _Stat(
                            value: _nearestDist,
                            label: 'Nearest help',
                            color: C.success),
                      ]),

                      const SizedBox(height: 16),

                      // ── Mini map ──────────────────────────────────────────
                      const SecHeader('📍 Live Location Broadcast'),
                      Container(
                          height: 160,
                          decoration: BoxDecoration(
                              color: const Color(0xFF081413),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: C.accent.withOpacity(.35), width: 1.5)),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Stack(children: [
                                // Grid
                                CustomPaint(
                                    painter: GridPainter(),
                                    size: const Size(double.infinity, 160)),

                                LayoutBuilder(
                                    builder: (ctx, bc) => Stack(children: [
                                          ...List.generate(
                                              _sosActive
                                                  ? _notified.length
                                                  : _displayUsers.length, (i) {
                                            final person = _sosActive
                                                ? _notified[i]
                                                : _displayUsers[i];
                                            Offset offset;
                                            if (person.latitude != 0.0 &&
                                                person.longitude != 0.0) {
                                              offset = _getMapOffset(
                                                  person.latitude,
                                                  person.longitude,
                                                  bc.maxWidth);
                                            } else {
                                              if (i < _mapDots.length) {
                                                offset = _mapDots[i];
                                              } else {
                                                offset = const Offset(0.5, 0.5);
                                              }
                                            }
                                            return Positioned(
                                                left:
                                                    offset.dx * bc.maxWidth - 6,
                                                top: offset.dy * 160 - 6,
                                                child: SlideUpFade(
                                                    child: Container(
                                                        width: 12,
                                                        height: 12,
                                                        decoration: BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            color: person.color,
                                                            border: Border.all(
                                                                color: Colors
                                                                    .white,
                                                                width: 1.5)))));
                                          }),
                                        ])),

                                // You pin
                                AnimatedBuilder(
                                  animation: _mapPinPulse,
                                  builder: (_, __) => Center(
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                        Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: C.accent,
                                                boxShadow: [
                                                  BoxShadow(
                                                      color: C.accent.withOpacity(
                                                          .3 +
                                                              _mapPinPulse
                                                                      .value *
                                                                  .3),
                                                      blurRadius: 8 +
                                                          _mapPinPulse.value *
                                                              6,
                                                      spreadRadius: 2)
                                                ])),
                                        const SizedBox(height: 2),
                                        Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: C.accent,
                                                borderRadius:
                                                    BorderRadius.circular(4)),
                                            child: const Text('You',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 8,
                                                    fontWeight:
                                                        FontWeight.w700))),
                                      ])),
                                ),

                                // Bottom label
                                Positioned(
                                    bottom: 8,
                                    left: 12,
                                    child: Row(children: [
                                      const WaveBars(),
                                      const SizedBox(width: 8),
                                      Text(
                                        LocationService.instance.isTracking
                                            ? '$_myPlaceName — GPS Active'
                                            : 'Location Sharing Inactive',
                                        style: TextStyle(
                                            color: C.accent,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ])),
                              ]))),

                      const SizedBox(height: 16),

                      // ── Notified people ───────────────────────────────────
                      if (_notified.isNotEmpty) ...[
                        SecHeader(
                            'Nearby people - Notified (${_notified.length})'),
                        ..._notified.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SlideUpFade(
                                delay: Duration(milliseconds: e.key * 60),
                                child: _PersonCard(person: e.value)))),
                        const SizedBox(height: 8),
                      ] else if (!_sosActive &&
                          _realNearbyUsers.isNotEmpty) ...[
                        SecHeader(
                            'Nearby people - Online (${_realNearbyUsers.length})'),
                        ..._realNearbyUsers.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SlideUpFade(
                                delay: Duration(milliseconds: e.key * 60),
                                child: _PersonCard(person: e.value)))),
                        const SizedBox(height: 8),
                      ],

                      // ── Real responders (helpers who accepted) ────────────
                      if (_responders.isNotEmpty) ...[
                        SecHeader(
                            '🚶 Responders on the way (${_responders.length})'),
                        ..._responders.map((h) {
                          final d = _calculateDistance(
                              _myLat, _myLon, h.latitude, h.longitude);
                          final arrived = h.status == 'arrived';
                          final col = arrived ? C.success : C.accent;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: C.bg2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: col.withValues(alpha: .4)),
                              ),
                              child: Row(children: [
                                CircleAvatar(
                                    radius: 18,
                                    backgroundColor: col,
                                    child: Text(
                                        h.name.isNotEmpty
                                            ? h.name[0].toUpperCase()
                                            : 'H',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700))),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(h.name,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700)),
                                        Text(
                                            arrived
                                                ? 'Arrived'
                                                : 'On the way · ${d.toStringAsFixed(1)} km away',
                                            style: TextStyle(
                                                color: C.textMuted,
                                                fontSize: 11)),
                                      ]),
                                ),
                                Column(children: [
                                  Icon(
                                      arrived
                                          ? Icons.check_circle_rounded
                                          : Icons.directions_run_rounded,
                                      color: col,
                                      size: 18),
                                  const SizedBox(height: 2),
                                  Text(arrived ? 'Here' : 'Coming',
                                      style: TextStyle(
                                          color: col,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600)),
                                ]),
                              ]),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],

                      // ── How it works (before SOS) ─────────────────────────
                      if (!_sosActive) ...[
                        const SecHeader('How it works'),
                        _HowRow(
                            step: '1',
                            text: 'Press the SOS button',
                            color: C.accent),
                        const SizedBox(height: 6),
                        _HowRow(
                            step: '2',
                            text:
                                'Your live GPS location is shared within a 5 km radius',
                            color: C.warning),
                        const SizedBox(height: 6),
                        _HowRow(
                            step: '3',
                            text:
                                'Nearby SmartSafe users and contacts receive an instant alert',
                            color: C.accent),
                        const SizedBox(height: 6),
                        _HowRow(
                            step: '4',
                            text:
                                'You can see each responder name and distance',
                            color: C.accent),
                        const SizedBox(height: 6),
                        _HowRow(
                            step: '5',
                            text: 'Tap "I am safe" once help arrives',
                            color: C.success),
                        const SizedBox(height: 16),
                      ],

                      // ── Cancel ────────────────────────────────────────────
                      GestureDetector(
                          onTap: _cancel,
                          child: DCard(
                              borderColor: _sosActive ? C.success : null,
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        color: _sosActive ? C.success : C.textMuted,
                                        size: 18),
                                    const SizedBox(width: 8),
                                    Text('I am safe - Cancel alert',
                                        style: TextStyle(
                                            color:
                                                _sosActive ? C.success : C.textMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ]))),

                      const SizedBox(height: 24),
                    ]),
              ),
            ),
          ],
        ),
      );
}

// ── Helper widgets ────────────────────────────────────────────
class _NearbyPerson {
  final String name, role, dist, init;
  final Color color;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String uid; // real SmartSafe user id (for sending the actual push)

  const _NearbyPerson({
    required this.name,
    required this.role,
    required this.dist,
    required this.init,
    required this.color,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.distanceKm = 0.0,
    this.uid = '',
  });
}

class _PersonCard extends StatelessWidget {
  final _NearbyPerson person;
  const _PersonCard({required this.person});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: person.color.withOpacity(.35))),
      child: Row(children: [
        CircleAvatar(
            radius: 18,
            backgroundColor: person.color,
            child: Text(person.init,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(person.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          Text('${person.role} - ${person.dist} away',
              style: TextStyle(color: C.textMuted, fontSize: 11)),
        ])),
        Column(children: [
          BlinkDot(color: person.color),
          const SizedBox(height: 3),
          Text('Notified',
              style: TextStyle(
                  color: person.color,
                  fontSize: 9,
                  fontWeight: FontWeight.w600)),
        ]),
      ]));
}

class _Stat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: C.bg2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(.3))),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label,
                style: TextStyle(color: C.textMuted, fontSize: 9),
                textAlign: TextAlign.center),
          ])));
}

class _HowRow extends StatelessWidget {
  final String step, text;
  final Color color;
  const _HowRow({required this.step, required this.text, required this.color});
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Center(
                child: Text(step,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)))),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(color: C.textMuted, fontSize: 12, height: 1.4))),
      ]);
}
