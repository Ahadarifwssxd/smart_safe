import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../theme/colors.dart';
import '../theme/design_tokens.dart';
import '../services/routing_service.dart';
// distanceKm() (Haversine) is reused from the live-tracking service so the
// whole app measures great-circle distance the same way.
import '../services/live_tracking_service.dart' show distanceKm;
import '../services/push_sender.dart';
import '../utils/phone_utils.dart';

/// ── Tween that glides the user marker between GPS fixes ─────────────────────
class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}

/// A flagged danger zone (admin `danger_zones` collection).
class _Zone {
  final String name;
  final String risk; // High | Medium | Low
  final LatLng point;
  final String advice;
  const _Zone(this.name, this.risk, this.point, this.advice);
  bool get isHigh => risk.toLowerCase() == 'high';
}

/// One real OSRM driving alternative, scored against live danger zones.
class _RouteOpt {
  final List<LatLng> points;
  final double km;
  final int min;
  int zoneHits;
  String tier; // 'safe' (green) | 'medium' (amber) | 'risky' (red)
  _RouteOpt({
    required this.points,
    required this.km,
    required this.min,
    this.zoneHits = 0,
    this.tier = 'safe',
  });
}

/// One turn-by-turn maneuver parsed from the OSRM `steps` array.
class _NavStep {
  final String instruction;
  final LatLng at;
  final double meters;
  const _NavStep(this.instruction, this.at, this.meters);
}

/// Plan-a-route: real GPS + Nominatim search + OSRM alternatives, scored against
/// live Firestore danger zones, with in-app turn-by-turn navigation and live
/// journey sharing to the user's emergency contacts.
class PlanARoutePage extends StatefulWidget {
  const PlanARoutePage({super.key});

  @override
  State<PlanARoutePage> createState() => _PlanARoutePageState();
}

class _PlanARoutePageState extends State<PlanARoutePage> {
  final MapController _map = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  static const Distance _geo = Distance();
  static const double _zoneRadiusM = 300; // "near a route" threshold

  // Location / tracking
  StreamSubscription<Position>? _gpsSub;
  LatLng? _start;
  String _startName = 'Locating…';
  LatLng? _me; // latest raw fix
  LatLng? _renderPos; // last settled marker position (animation)
  LatLng? _targetPos; // animation target
  double _bearing = 0;
  bool _followMe = true;
  DateTime? _lastGeocode;

  // Destination search
  Timer? _debounce;
  List<dynamic> _suggestions = [];
  bool _searching = false;
  LatLng? _dest;
  String _destName = '';

  // Routing
  bool _routing = false;
  List<_RouteOpt> _options = [];
  int _selected = 0;

  // Danger zones (live)
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _zonesSub;
  List<_Zone> _zones = [];

  // Navigation
  bool _navigating = false;
  List<_NavStep> _steps = [];
  int _stepIndex = 0;

  // Live journey sharing
  bool _sharing = false;
  Timer? _shareTimer;

  bool get _isNight {
    final h = DateTime.now().hour;
    return h >= 22 || h < 6;
  }

  _RouteOpt? get _sel =>
      (_options.isNotEmpty && _selected < _options.length) ? _options[_selected] : null;

  @override
  void initState() {
    super.initState();
    _listenZones();
    _initLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gpsSub?.cancel();
    _zonesSub?.cancel();
    _shareTimer?.cancel();
    _searchCtrl.dispose();
    // Best-effort: stop sharing the live doc if the user leaves mid-journey.
    if (_sharing) {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        _fs.collection('live_tracking').doc(uid).delete().catchError((_) {});
      }
    }
    super.dispose();
  }

  // ── Danger zones ──────────────────────────────────────────────────────────
  void _listenZones() {
    try {
      _zonesSub =
          _fs.collection('danger_zones').snapshots().listen((snap) {
        final loaded = <_Zone>[];
        for (final d in snap.docs) {
          final z = _parseZone(d.data());
          if (z != null) loaded.add(z);
        }
        if (!mounted) return;
        setState(() => _zones = loaded);
        if (_options.isNotEmpty) _scoreOptions();
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Accepts both the admin model (`coordinates: "lat,lng"`) and a plain
  /// `latitude`/`longitude` numeric model, so it works whatever the dashboard writes.
  _Zone? _parseZone(Map<String, dynamic> m) {
    double? lat = (m['latitude'] as num?)?.toDouble();
    double? lng = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      final coords = (m['coordinates'] ?? '').toString().split(',');
      if (coords.length >= 2) {
        lat = double.tryParse(coords[0].trim());
        lng = double.tryParse(coords[1].trim());
      }
    }
    if (lat == null || lng == null) return null;
    return _Zone(
      (m['name'] ?? 'Danger zone').toString(),
      (m['riskLevel'] ?? m['risk'] ?? 'Medium').toString(),
      LatLng(lat, lng),
      (m['safetyAdvice'] ?? m['description'] ?? '').toString(),
    );
  }

  // ── Current location ──────────────────────────────────────────────────────
  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _promptPermission('Location services are off. Please enable GPS.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _promptPermission(
            'SmartSafe needs your location to plan a safe route and share your journey.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _start = here;
        _me = here;
        _renderPos = here;
        _targetPos = here;
      });
      try {
        _map.move(here, 15);
      } catch (_) {}
      _reverseGeocode(here);

      _gpsSub?.cancel();
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 10,
        ),
      ).listen(_onGps, onError: (_) {});
    } catch (e) {
      _snack('Could not get your location. Please try again.');
    }
  }

  void _onGps(Position pos) {
    if (!mounted) return;
    final me = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _me = me;
      _targetPos = me;
      if (pos.heading >= 0) _bearing = pos.heading;
      if (_dest == null) _start = me;
    });
    if (_followMe) {
      try {
        _map.move(me, _navigating ? 16.5 : _safeZoom());
      } catch (_) {}
    }
    if (_dest == null) _reverseGeocode(me);
    if (_navigating) _advanceStep(me);
  }

  double _safeZoom() {
    try {
      return _map.zoom;
    } catch (_) {
      return 15;
    }
  }

  LatLng? _lastGeocodedPoint;
  Future<void> _reverseGeocode(LatLng p) async {
    final now = DateTime.now();
    // The first GPS fix is often a coarse cell/network one that then refines, so
    // don't hold a wrong address for long: re-geocode after a short cooldown OR
    // whenever the position has moved a meaningful distance (>60 m).
    final movedFar = _lastGeocodedPoint == null ||
        distanceKm(_lastGeocodedPoint!.latitude, _lastGeocodedPoint!.longitude,
                p.latitude, p.longitude) >
            0.06;
    if (!movedFar &&
        _lastGeocode != null &&
        now.difference(_lastGeocode!).inSeconds < 6) {
      return;
    }
    _lastGeocode = now;
    _lastGeocodedPoint = p;
    final name = await _areaName(p);
    if (mounted && name.isNotEmpty) setState(() => _startName = name);
  }

  /// Native geocoder first (fast, no rate limit), then Nominatim reverse.
  Future<String> _areaName(LatLng p) async {
    try {
      final marks = await placemarkFromCoordinates(p.latitude, p.longitude)
          .timeout(const Duration(seconds: 3));
      if (marks.isNotEmpty) {
        final m = marks.first;
        final s = [m.subLocality, m.locality, m.administrativeArea]
            .where((e) => (e ?? '').trim().isNotEmpty)
            .join(', ');
        if (s.trim().isNotEmpty) return s;
      }
    } catch (_) {}
    try {
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?lat=${p.latitude}&lon=${p.longitude}&format=json&accept-language=en'),
        headers: {'User-Agent': 'SmartSafeApp/1.0'},
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final dn = (json.decode(res.body)['display_name'] ?? '').toString();
        if (dn.isNotEmpty) return dn.split(',').take(3).join(',').trim();
      }
    } catch (_) {}
    return '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';
  }

  void _promptPermission(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Row(children: [
          Icon(Icons.location_off_rounded, color: C.accent, size: 20),
          const SizedBox(width: 8),
          Text('Location needed',
              style: TextStyle(color: C.textPrimary, fontSize: 16)),
        ]),
        content: Text(message, style: TextStyle(color: C.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Not now', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Geolocator.openAppSettings();
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  // ── Destination search (Nominatim, Pakistan) ──────────────────────────────
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(q)}&format=json&limit=5&addressdetails=1&countrycodes=pk'),
        headers: {'User-Agent': 'SmartSafeApp/1.0'},
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        setState(() => _suggestions = json.decode(res.body) as List);
      }
    } catch (_) {
      _snack('Search failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pick(dynamic s) async {
    final lat = double.tryParse(s['lat']?.toString() ?? '');
    final lon = double.tryParse(s['lon']?.toString() ?? '');
    if (lat == null || lon == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _dest = LatLng(lat, lon);
      _destName = (s['display_name']?.toString() ?? 'Destination')
          .split(',')
          .take(2)
          .join(',');
      _searchCtrl.text = _destName;
      _suggestions = [];
      _followMe = false;
    });
    await _computeRoutes();
  }

  // ── OSRM alternatives (reuses RoutingService) ─────────────────────────────
  Future<void> _computeRoutes() async {
    if (_start == null || _dest == null) return;
    setState(() {
      _routing = true;
      _options = [];
      _selected = 0;
    });
    try {
      final raws = await RoutingService().getAlternatives(
        _start!.latitude,
        _start!.longitude,
        _dest!.latitude,
        _dest!.longitude,
      );
      final opts = raws
          .map((r) => _RouteOpt(points: r.points, km: r.distanceKm, min: r.durationMin))
          .toList();
      if (!mounted) return;
      setState(() {
        _options = opts;
        _routing = false;
      });
      _scoreOptions();
      _fitRoute();
      // Night safety: automatically prefer the safest (first-ranked) route.
      if (_isNight && mounted) setState(() => _selected = 0);
    } catch (_) {
      if (mounted) {
        setState(() => _routing = false);
        _snack('Could not calculate a route. Please try again.');
      }
    }
  }

  /// Counts danger zones within [_zoneRadiusM] of each route, ranks safest→
  /// riskiest, and colours them green / amber / red.
  void _scoreOptions() {
    for (final o in _options) {
      int hits = 0;
      for (final z in _zones) {
        if (_nearRoute(o.points, z.point)) hits++;
      }
      o.zoneHits = hits;
    }
    _options.sort((a, b) =>
        a.zoneHits != b.zoneHits ? a.zoneHits - b.zoneHits : a.min - b.min);
    for (var i = 0; i < _options.length; i++) {
      _options[i].tier = i == 0 ? 'safe' : (i == 1 ? 'medium' : 'risky');
      // A route that passes no danger zones is always "safe" regardless of rank.
      if (_options[i].zoneHits == 0) _options[i].tier = 'safe';
    }
    if (_selected >= _options.length) _selected = 0;
    if (mounted) setState(() {});
  }

  bool _nearRoute(List<LatLng> pts, LatLng z) {
    for (final p in pts) {
      if (distanceKm(p.latitude, p.longitude, z.latitude, z.longitude) * 1000 <=
          _zoneRadiusM) {
        return true;
      }
    }
    return false;
  }

  /// Danger zones within range of the SELECTED route (drawn as warning circles).
  List<_Zone> get _zonesOnRoute {
    final sel = _sel;
    if (sel == null) return const [];
    return _zones.where((z) => _nearRoute(sel.points, z.point)).toList();
  }

  void _fitRoute() {
    final sel = _sel;
    if (sel == null || sel.points.isEmpty) return;
    try {
      _map.fitBounds(
        LatLngBounds.fromPoints(sel.points),
        options: const FitBoundsOptions(padding: EdgeInsets.all(50)),
      );
    } catch (_) {}
  }

  Color _tierColor(String t) =>
      t == 'safe' ? C.success : (t == 'medium' ? C.warning : C.accent);
  String _tierLabel(String t) =>
      t == 'safe' ? 'Safest' : (t == 'medium' ? 'Caution' : 'High risk');

  // ── Turn-by-turn navigation ───────────────────────────────────────────────
  Future<void> _startNavigation() async {
    final sel = _sel;
    if (_dest == null || sel == null || _start == null) return;
    setState(() => _routing = true);
    final steps = await _fetchSteps(_start!, _dest!);
    if (!mounted) return;
    setState(() {
      _steps = steps;
      _stepIndex = 0;
      _navigating = true;
      _followMe = true;
      _routing = false;
    });
    if (_me != null) {
      try {
        _map.move(_me!, 16.5);
      } catch (_) {}
    }
    _startLiveJourney();
  }

  /// Fetches OSRM steps for the selected origin/destination.
  Future<List<_NavStep>> _fetchSteps(LatLng a, LatLng b) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
        '?alternatives=true&overview=full&geometries=geojson&steps=true',
      );
      final res = await http
          .get(url, headers: {'User-Agent': 'SmartSafeApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['code'] == 'Ok' &&
            data['routes'] is List &&
            (data['routes'] as List).isNotEmpty) {
          final legs = data['routes'][0]['legs'] as List? ?? [];
          final out = <_NavStep>[];
          for (final leg in legs) {
            for (final step in (leg['steps'] as List? ?? [])) {
              final man = step['maneuver'] ?? {};
              final loc = man['location'] as List?;
              if (loc == null || loc.length < 2) continue;
              out.add(_NavStep(
                _instruction(step),
                LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
                (step['distance'] as num?)?.toDouble() ?? 0,
              ));
            }
          }
          if (out.isNotEmpty) return out;
        }
      }
    } catch (_) {}
    // Fallback: a single instruction so navigation still works.
    return [_NavStep('Head to your destination', b, (_sel?.km ?? 0) * 1000)];
  }

  String _instruction(Map step) {
    final m = step['maneuver'] ?? {};
    final type = (m['type'] ?? '').toString();
    final mod = (m['modifier'] ?? '').toString();
    final road = (step['name'] ?? '').toString();
    final onto = road.isNotEmpty ? ' onto $road' : '';
    switch (type) {
      case 'depart':
        return road.isNotEmpty ? 'Head out on $road' : 'Start your journey';
      case 'arrive':
        return 'You have arrived at your destination';
      case 'turn':
      case 'end of road':
        return 'Turn ${mod.isNotEmpty ? mod : 'ahead'}$onto';
      case 'continue':
      case 'new name':
        return road.isNotEmpty ? 'Continue onto $road' : 'Continue straight';
      case 'merge':
        return 'Merge${mod.isNotEmpty ? ' $mod' : ''}$onto';
      case 'roundabout':
      case 'rotary':
        return 'Take the roundabout$onto';
      case 'fork':
        return 'Keep ${mod.isNotEmpty ? mod : 'ahead'} at the fork';
      case 'on ramp':
      case 'ramp':
        return 'Take the ramp$onto';
      case 'off ramp':
        return 'Take the exit$onto';
      default:
        return mod.isNotEmpty
            ? 'Turn $mod$onto'
            : (road.isNotEmpty ? 'Continue onto $road' : 'Proceed');
    }
  }

  void _advanceStep(LatLng me) {
    if (_steps.isEmpty) return;
    // Arrival.
    if (_dest != null &&
        _geo.as(LengthUnit.Meter, me, _dest!) <= 35 &&
        _stepIndex < _steps.length - 1) {
      setState(() => _stepIndex = _steps.length - 1);
      return;
    }
    if (_stepIndex >= _steps.length - 1) return;
    final cur = _steps[_stepIndex];
    if (_geo.as(LengthUnit.Meter, me, cur.at) <= 30) {
      setState(() => _stepIndex++);
    }
  }

  Future<void> _endNavigation() async {
    await _stopLiveJourney(arrived: true);
    if (!mounted) return;
    setState(() {
      _navigating = false;
      _steps = [];
      _stepIndex = 0;
    });
  }

  // ── Live journey sharing ──────────────────────────────────────────────────
  Future<void> _startLiveJourney() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _snack('Sign in to share your live journey.');
      return;
    }
    _sharing = true;
    await _writeLiveDoc();
    // Push the live doc every ~5s regardless of GPS cadence.
    _shareTimer?.cancel();
    _shareTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _writeLiveDoc());
    await _notifyContacts(started: true);
  }

  Future<void> _writeLiveDoc() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _me == null || !_sharing) return;
    final u = _auth.currentUser;
    try {
      await _fs.collection('live_tracking').doc(uid).set({
        'userId': uid,
        'userName': u?.displayName ?? u?.email?.split('@').first ?? 'User',
        'latitude': _me!.latitude,
        'longitude': _me!.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'journeyActive': true,
        'journeyTo': _destName,
        'status': 'journey',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _stopLiveJourney({required bool arrived}) async {
    _shareTimer?.cancel();
    if (!_sharing) return;
    _sharing = false;
    if (arrived) await _notifyContacts(started: false);
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _fs.collection('live_tracking').doc(uid).delete();
      } catch (_) {}
    }
  }

  /// Notifies the user's emergency contacts (in-app notification + FCM push via
  /// PushSender) that the journey started or that they arrived safely. Reuses
  /// the app's `emergency_contacts` → phone → uid resolution pattern.
  Future<void> _notifyContacts({required bool started}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final u = _auth.currentUser;
    final name = u?.displayName ?? u?.email?.split('@').first ?? 'A SmartSafe user';
    final dest = _destName.isNotEmpty ? _destName : 'their destination';
    final message = started
        ? '🛡️ $name started a journey to $dest. Follow their live location until they arrive safely.'
        : '✅ $name has safely arrived at $dest.';

    try {
      final contacts = await _fs
          .collection('emergency_contacts')
          .where('userId', isEqualTo: uid)
          .get();
      if (contacts.docs.isEmpty) {
        if (started) {
          _snack('Add an emergency contact to share your journey.');
        }
        return;
      }

      final batch = _fs.batch();
      final pushTargets = <String>[];
      for (final c in contacts.docs) {
        final phone = c.data()['phone']?.toString() ?? '';
        final norm = normalizePhone(phone);
        if (norm.isEmpty) continue;
        final match = await _fs
            .collection('users')
            .where('phoneNormalized', isEqualTo: norm)
            .limit(1)
            .get();
        if (match.docs.isEmpty) continue; // contact isn't a SmartSafe user
        final targetUid = match.docs.first.id;
        pushTargets.add(targetUid);
        final ref = _fs.collection('notifications').doc();
        batch.set(ref, {
          'targetUserId': targetUid,
          'type': started ? 'journey_start' : 'journey_end',
          'senderName': name,
          'sosUserId': uid,
          'message': message,
          if (_me != null) 'latitude': _me!.latitude,
          if (_me != null) 'longitude': _me!.longitude,
          'read': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (pushTargets.isNotEmpty) {
        await PushSender.instance.pushSos(
          targetUserIds: pushTargets,
          type: started ? 'journey_start' : 'journey_end',
          senderName: name,
          sosUserId: uid,
          latitude: _me?.latitude.toString() ?? '',
          longitude: _me?.longitude.toString() ?? '',
        );
      }
      if (started) {
        _snack('Shared your journey with ${pushTargets.length} contact(s).');
      }
    } catch (_) {
      if (started) _snack('Could not share your journey. Please try again.');
    }
  }

  // ── ETA helpers ───────────────────────────────────────────────────────────
  double get _remainingKm {
    final sel = _sel;
    if (sel == null || sel.points.isEmpty) return 0;
    if (_me == null) return sel.km;
    int nearest = 0;
    double best = double.infinity;
    for (var i = 0; i < sel.points.length; i++) {
      final d = _geo.as(LengthUnit.Meter, _me!, sel.points[i]);
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    double m = best;
    for (var i = nearest; i < sel.points.length - 1; i++) {
      m += _geo.as(LengthUnit.Meter, sel.points[i], sel.points[i + 1]);
    }
    return m / 1000;
  }

  int get _etaMin {
    final sel = _sel;
    if (sel == null || sel.km <= 0) return sel?.min ?? 0;
    final ratio = (_remainingKm / sel.km).clamp(0.0, 1.0);
    return (sel.min * ratio).round();
  }

  String _arriveBy() {
    final t = DateTime.now().add(Duration(minutes: _etaMin));
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h12:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _header(),
                if (_isNight) _nightBanner(),
                _inputs(),
                Expanded(child: _mapAndRoutes()),
              ],
            ),
            if (_navigating) _navSheet(),
            if (_navigating) _etaBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, DesignTokens.space16, 20, DesignTokens.space12),
      child: Row(
        children: [
          if (Navigator.canPop(context)) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: C.bg2, shape: BoxShape.circle),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: C.textPrimary, size: 16),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan a Route',
                    style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                Text('Safest path, checked against danger zones',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: C.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nightBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, DesignTokens.space8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: C.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radius12),
        border: Border.all(color: C.accent.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.nightlight_round, color: C.accent, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "It's night time — the safest route is selected by default. Stay alert.",
            style: TextStyle(
                color: C.accent, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  Widget _inputs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: C.bg2,
              borderRadius: BorderRadius.circular(DesignTokens.radius16),
              border: Border.all(color: C.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // FROM
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: C.border)),
                  ),
                  child: Row(children: [
                    _dot(C.success),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 40,
                      child: Text('FROM',
                          style: TextStyle(
                              color: C.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ),
                    Expanded(
                      child: Text(
                        _start == null ? 'Locating…' : _startName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: C.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('LIVE',
                          style: TextStyle(
                              color: C.success,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
                // TO
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    _dot(C.accent),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 40,
                      child: Text('TO',
                          style: TextStyle(
                              color: C.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Where are you headed?',
                          hintStyle: TextStyle(color: C.textMuted),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    if (_searching)
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: C.accent))
                    else if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() {
                          _searchCtrl.clear();
                          _suggestions = [];
                        }),
                        child: Icon(Icons.clear, color: C.textMuted, size: 18),
                      ),
                  ]),
                ),
              ],
            ),
          ),
          if (_suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: C.bg2,
                borderRadius: BorderRadius.circular(DesignTokens.radius14),
                border: Border.all(color: C.border),
              ),
              child: Column(
                children: _suggestions.map((s) {
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.place_rounded, color: C.accent, size: 18),
                    title: Text(
                      (s['display_name']?.toString() ?? '')
                          .split(',')
                          .take(2)
                          .join(','),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: C.textPrimary, fontSize: 13),
                    ),
                    onTap: () => _pick(s),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
        ),
      );

  Widget _mapAndRoutes() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: DesignTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: DesignTokens.space16),
          SizedBox(
            height: (MediaQuery.of(context).size.height * 0.42)
                .clamp(280.0, 460.0)
                .toDouble(),
            child: _mapView(),
          ),
          const SizedBox(height: DesignTokens.space16),
          _routePanel(),
        ],
      ),
    );
  }

  Widget _mapView() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            center: _start ?? const LatLng(24.8607, 67.0011),
            zoom: 13,
            maxZoom: 18,
            minZoom: 5,
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture && _followMe) setState(() => _followMe = false);
            },
          ),
          children: [
            TileLayer(
              // Light "voyager" basemap — clear white streets (was dark_all).
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'smartsafe.app',
              keepBuffer: 6,
            ),
            // Warning circles for danger zones near the selected route.
            CircleLayer(
              circles: _zonesOnRoute.map((z) {
                final col = z.isHigh ? C.accent : C.warning;
                return CircleMarker(
                  point: z.point,
                  radius: _zoneRadiusM,
                  useRadiusInMeter: true,
                  color: col.withValues(alpha: z.isHigh ? 0.16 : 0.10),
                  borderColor: col.withValues(alpha: z.isHigh ? 0.9 : 0.6),
                  borderStrokeWidth: z.isHigh ? 2.5 : 1.5,
                );
              }).toList(),
            ),
            // All alternatives (green safest / amber medium / red riskiest).
            if (_options.isNotEmpty)
              PolylineLayer(polylines: [
                for (int i = 0; i < _options.length; i++)
                  if (i != _selected)
                    Polyline(
                      points: _options[i].points,
                      strokeWidth: 4,
                      color: _tierColor(_options[i].tier).withValues(alpha: 0.45),
                    ),
                Polyline(
                  points: _sel!.points,
                  strokeWidth: 6,
                  color: _tierColor(_sel!.tier),
                  borderStrokeWidth: 2,
                  borderColor: Colors.black.withValues(alpha: 0.4),
                ),
              ]),
            // Destination marker.
            if (_dest != null)
              MarkerLayer(markers: [
                Marker(
                  point: _dest!,
                  width: 40,
                  height: 40,
                  builder: (_) =>
                      Icon(Icons.location_on, color: C.accent, size: 34),
                ),
              ]),
            // Smoothly-animated user marker (glides between GPS fixes).
            if (_renderPos != null)
              TweenAnimationBuilder<LatLng>(
                tween: _LatLngTween(begin: _renderPos!, end: _targetPos ?? _renderPos!),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOut,
                onEnd: () => _renderPos = _targetPos,
                builder: (context, pos, _) => MarkerLayer(markers: [
                  Marker(
                    point: pos,
                    width: 46,
                    height: 46,
                    builder: (_) => Transform.rotate(
                      angle: _bearing * math.pi / 180,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: C.accentLight,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6),
                          ],
                        ),
                        child: Icon(
                            _navigating
                                ? Icons.navigation_rounded
                                : Icons.my_location_rounded,
                            color: Colors.white,
                            size: 22),
                      ),
                    ),
                  ),
                ]),
              ),
            const SimpleAttributionWidget(source: Text('OpenStreetMap')),
          ],
        ),
        // Legend.
        Positioned(
          bottom: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: C.bg2.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: C.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _legend(C.success, 'Safe'),
              const SizedBox(width: 10),
              _legend(C.warning, 'Medium'),
              const SizedBox(width: 10),
              _legend(C.accent, 'Risky'),
            ]),
          ),
        ),
        // Recenter.
        Positioned(
          bottom: 10,
          right: 10,
          child: GestureDetector(
            onTap: () {
              setState(() => _followMe = true);
              if (_me != null) {
                try {
                  _map.move(_me!, 16);
                } catch (_) {}
              }
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: C.bg2.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(color: _followMe ? C.accent : C.border),
              ),
              child: Icon(
                _followMe ? Icons.my_location : Icons.location_searching,
                color: _followMe ? C.accent : C.textMuted,
                size: 20,
              ),
            ),
          ),
        ),
        if (_routing)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: C.bg2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: C.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: C.accent)),
                  const SizedBox(width: 8),
                  Text('Finding safest route…',
                      style: TextStyle(color: C.textPrimary, fontSize: 12)),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      );

  Widget _routePanel() {
    if (_options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.space32, horizontal: DesignTokens.space24),
          decoration: BoxDecoration(
            color: C.bg2,
            borderRadius: BorderRadius.circular(DesignTokens.radius16),
            border: Border.all(color: C.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_rounded, color: C.accent, size: 40),
              const SizedBox(height: DesignTokens.space12),
              Text('Where do you want to go?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: C.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: DesignTokens.space8),
              Text(
                  'Search a destination to see up to 3 routes, scored against nearby danger zones.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.textMuted, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _options.length; i++) _routeCard(_options[i], i),
          const SizedBox(height: DesignTokens.space8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _navigating ? null : _startNavigation,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: Text(_navigating ? 'Navigating…' : 'Start Navigation',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radius16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeCard(_RouteOpt o, int i) {
    final selected = i == _selected;
    final col = _tierColor(o.tier);
    return GestureDetector(
      onTap: () {
        setState(() => _selected = i);
        _fitRoute();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: DesignTokens.space12),
        padding: const EdgeInsets.all(DesignTokens.space16),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(DesignTokens.radius16),
          border: Border.all(
            color: selected ? col.withValues(alpha: 0.7) : C.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: col.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                    o.tier == 'safe'
                        ? Icons.verified_user_rounded
                        : Icons.warning_amber_rounded,
                    color: col,
                    size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i == 0 ? 'Route ${i + 1} · Recommended' : 'Route ${i + 1}',
                      style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      o.zoneHits == 0
                          ? 'No danger zones on this route'
                          : '${o.zoneHits} danger zone${o.zoneHits == 1 ? '' : 's'} nearby',
                      style: TextStyle(color: C.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: col.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: col.withValues(alpha: 0.35)),
                ),
                child: Text(_tierLabel(o.tier),
                    style: TextStyle(
                        color: col, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: DesignTokens.space12),
            Row(children: [
              _stat(Icons.straighten_rounded, '${o.km.toStringAsFixed(1)} km'),
              const SizedBox(width: DesignTokens.space8),
              _stat(Icons.timer_outlined, '${o.min} min'),
              const SizedBox(width: DesignTokens.space8),
              _stat(Icons.report_problem_rounded,
                  o.zoneHits == 0 ? 'Clear' : '${o.zoneHits} near',
                  danger: o.zoneHits > 0),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, {bool danger = false}) {
    final c = danger ? C.warning : C.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: danger ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: danger ? 0.4 : 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: c, size: 14),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(
                color: C.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // Persistent turn-by-turn panel styled like a bottom sheet.
  Widget _navSheet() {
    final step = (_stepIndex < _steps.length) ? _steps[_stepIndex] : null;
    final next = (_stepIndex + 1 < _steps.length) ? _steps[_stepIndex + 1] : null;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 72 + MediaQuery.of(context).padding.bottom,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: C.bg2,
            borderRadius: BorderRadius.circular(DesignTokens.radius24),
            border: Border.all(color: C.border),
            boxShadow: AppTheme.cardShadow(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: C.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: C.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.turn_right_rounded, color: C.accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step?.instruction ?? 'Proceed to your destination',
                        style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text('Step ${_stepIndex + 1} of ${_steps.length}',
                          style: TextStyle(color: C.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ]),
              if (next != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      color: C.textMuted, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Then: ${next.instruction}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: C.textMuted, fontSize: 12)),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _etaBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: C.nav,
          border: Border(top: BorderSide(color: C.border)),
        ),
        child: Row(children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_remainingKm.toStringAsFixed(1)} km · $_etaMin min',
                  style: TextStyle(
                      color: C.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              Text('Arrive by ${_arriveBy()}',
                  style: TextStyle(color: C.textMuted, fontSize: 11)),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _endNavigation,
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('End', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radius14)),
            ),
          ),
        ]),
      ),
    );
  }
}
