import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/routing_service.dart';
import '../services/sms_sender.dart';
import '../theme/colors.dart';
import '../theme/design_tokens.dart';
import 'in_app_navigation_page.dart';

/// Page-local palette for the "Plan a safe route" redesign (navy / beacon-amber
/// / guardian-teal), matching the approved mockup. Kept local so it doesn't
/// affect the rest of the app's red-accent theme.
class _R {
  // Theme-aware mapping so this safety-critical page follows the app's live
  // theme exactly (same bg, cards, accent, text, borders) in light or dark.
  static Color get navy => C.bg; // app bg
  static Color get indigo => C.bg2; // app bg2 (cards)
  static Color get indigoSoft => C.bg3; // app bg3
  static Color get beacon => C.accent; // app accent (primary / CTA / icons)
  static const guardian = Color(0xFF22C55E); // app success (safe)
  static Color get alert => C.red; // danger / high risk (kept red)
  static const caution = Color(0xFFF59E0B); // app warning (medium risk)
  static Color get fog => C.textPrimary; // app textPrimary
  static Color get slate => C.textMuted; // app textMuted
  static Color get line => C.border; // app border
}

class SafeRoutePage extends StatefulWidget {
  const SafeRoutePage({super.key});

  @override
  State<SafeRoutePage> createState() => _SafeRoutePageState();
}

class _DangerZone {
  final String name;
  final String risk; // High | Medium | Low
  final LatLng point;
  final String advice;
  final String type; // 'zone' (admin) | 'accident' | 'robbery' | ...
  final bool nightOnly; // risky only at night (e.g. robbery spots)
  final String reporter; // '' for admin zones
  final String whenStr; // formatted report date/time (full)
  final String whenShort; // compact date/time for the on-map badge
  const _DangerZone(
    this.name,
    this.risk,
    this.point,
    this.advice, {
    this.type = 'zone',
    this.nightOnly = false,
    this.reporter = '',
    this.whenStr = '',
    this.whenShort = '',
  });

  bool get isReport => type != 'zone';
}

/// One real OSRM route alternative, scored against live hazards.
class _RouteOption {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
  final int score; // 0..100 safety score (higher = safer)
  final String safety; // safe | caution | avoid
  final List<_DangerZone> hits;
  String label = ''; // Safest | Balanced | Fastest | Recommended
  _RouteOption({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    required this.score,
    required this.safety,
    required this.hits,
  });
}

class _RouteAssessment {
  final int score;
  final String safety;
  final List<_DangerZone> hits;
  const _RouteAssessment(this.score, this.safety, this.hits);
}

const Map<String, IconData> _hazardIcons = {
  'accident': Icons.car_crash_rounded,
  'robbery': Icons.local_police_rounded,
  'harassment': Icons.report_problem_rounded,
  'blocked': Icons.block_rounded,
  'other': Icons.warning_amber_rounded,
  'zone': Icons.dangerous_rounded,
};

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Professional date/time string: "Mon, 12 Jun 2026 · 9:30 PM".
String _fmtFull(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  return '${_weekdays[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]} ${t.year} · '
      '$h12:${t.minute.toString().padLeft(2, '0')} $ampm';
}

/// Compact date/time for the on-map marker badge: "Mon 12 Jun · 9:30 PM".
String _fmtShort(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  return '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} · '
      '$h12:${t.minute.toString().padLeft(2, '0')} $ampm';
}

class _SafeRoutePageState extends State<SafeRoutePage> {
  final MapController _map = MapController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  LatLng? _start;
  LatLng? _dest;
  String _destName = '';

  // ── Live location / tracking ──────────────────────────────────────────────
  StreamSubscription<Position>? _posSub;
  final List<LatLng> _trace = []; // breadcrumb of where the user actually moved
  String _startName = 'Locating…'; // live reverse-geocoded current area
  bool _followMe = true; // keep re-centering on the user until they pan/route
  DateTime? _lastStartGeocode;

  List<dynamic> _suggestions = [];
  bool _searching = false;
  bool _routing = false;

  final List<_DangerZone> _zones = [];

  // Up to three real OSRM alternatives, each scored against live hazards.
  List<_RouteOption> _options = [];
  int _selected = 0;

  _RouteOption? get _sel => (_options.isNotEmpty && _selected < _options.length)
      ? _options[_selected]
      : null;
  List<LatLng> get _route => _sel?.points ?? const [];
  double get _distanceKm => _sel?.distanceKm ?? 0;
  int get _durationMin => _sel?.durationMin ?? 0;
  String get _safety => _sel?.safety ?? 'unknown';
  List<_DangerZone> get _hits => _sel?.hits ?? const [];

  @override
  void initState() {
    super.initState();
    _loadHazards();
    _initStart();
  }

  static const _distance = Distance();

  @override
  void dispose() {
    _debounce?.cancel();
    _posSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initStart() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _start = here;
        _trace
          ..clear()
          ..add(here);
      });
      _map.move(here, 15);
      _updateStartName(here);
      // Reposition the demo example near the user now that we know location.
      _loadHazards();

      // LIVE tracking — keep the "you are here" dot moving in real time and
      // record a breadcrumb trail as the user walks/drives.
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 4,
        ),
      ).listen(_onLivePosition);
    } catch (_) {}
  }

  /// Called on every live GPS fix: moves the user dot, extends the breadcrumb
  /// trail, follows the user (until they pan / pick a destination), and keeps
  /// the "from" area name fresh.
  void _onLivePosition(Position pos) {
    if (!mounted) return;
    final p = LatLng(pos.latitude, pos.longitude);
    // Extend the trail only after real movement (avoids a jitter cluster while
    // standing still).
    if (_trace.isEmpty ||
        _distance.as(LengthUnit.Meter, _trace.last, p) > 6) {
      _trace.add(p);
      if (_trace.length > 800) _trace.removeAt(0);
    }
    setState(() => _start = p);
    if (_followMe && _dest == null) {
      try {
        _map.move(p, _map.zoom);
      } catch (_) {}
    }
    _updateStartName(p);
  }

  /// Reverse-geocodes the live start position to a readable area name, throttled
  /// so we don't hammer the geocoder while moving.
  Future<void> _updateStartName(LatLng p) async {
    final now = DateTime.now();
    if (_lastStartGeocode != null &&
        now.difference(_lastStartGeocode!).inSeconds < 20) {
      return;
    }
    _lastStartGeocode = now;
    final name = await _areaName(p.latitude, p.longitude);
    if (mounted) setState(() => _startName = name);
  }

  /// Re-centres the map on the user and re-enables live follow.
  void _recenterOnMe() {
    if (_start == null) return;
    setState(() => _followMe = true);
    try {
      _map.move(_start!, 16);
    } catch (_) {}
  }

  Future<void> _loadHazards() async {
    final loaded = <_DangerZone>[];
    // 1) Admin-defined danger zones
    try {
      final snap =
          await FirebaseFirestore.instance.collection('danger_zones').get();
      for (final d in snap.docs) {
        final m = d.data();
        final coords = (m['coordinates'] ?? '').toString().split(',');
        if (coords.length < 2) continue;
        final lat = double.tryParse(coords[0].trim());
        final lng = double.tryParse(coords[1].trim());
        if (lat == null || lng == null) continue;
        loaded.add(_DangerZone(
          m['name']?.toString() ?? 'Danger zone',
          m['riskLevel']?.toString() ?? 'Medium',
          LatLng(lat, lng),
          m['safetyAdvice']?.toString() ?? '',
        ));
      }
    } catch (_) {}

    // 2) PUBLIC community-reported hazards — visible to every user.
    try {
      final snap =
          await FirebaseFirestore.instance.collection('route_hazards').get();
      for (final d in snap.docs) {
        final m = d.data();
        final lat = (m['latitude'] as num?)?.toDouble();
        final lng = (m['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        // Prefer the incident time the reporter chose; fall back to created time.
        final inc = (m['incidentAt'] as Timestamp?)?.toDate();
        final ts = inc ?? (m['createdAt'] as Timestamp?)?.toDate();
        loaded.add(_DangerZone(
          // name holds the AREA (location) for community reports.
          m['locationName']?.toString() ?? '',
          m['riskLevel']?.toString() ?? 'High',
          LatLng(lat, lng),
          m['description']?.toString() ?? '',
          type: m['type']?.toString() ?? 'other',
          nightOnly: m['timeWindow']?.toString() == 'night',
          reporter: m['userName']?.toString() ?? 'A user',
          whenStr: ts != null ? _fmtFull(ts) : '',
          whenShort: ts != null ? _fmtShort(ts) : '',
        ));
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _zones
        ..clear()
        ..addAll(loaded);
    });
    if (_options.isNotEmpty) {
      _rescoreOptions();
      if (mounted) setState(() {});
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _suggestions = []);
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
      );
      if (res.statusCode == 200 && mounted) {
        setState(() => _suggestions = json.decode(res.body));
      }
    } catch (_) {
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
      _suggestions = [];
      _searchCtrl.text = _destName;
    });
    await _computeRoute();
  }

  Future<void> _computeRoute() async {
    if (_start == null || _dest == null) return;
    setState(() {
      _routing = true;
      _options = [];
      _selected = 0;
    });
    try {
      final raws = await RoutingService().getAlternatives(
          _start!.latitude, _start!.longitude, _dest!.latitude, _dest!.longitude);
      final opts = raws.map((r) {
        final a = _assess(r.points);
        return _RouteOption(
          points: r.points,
          distanceKm: r.distanceKm,
          durationMin: r.durationMin,
          score: a.score,
          safety: a.safety,
          hits: a.hits,
        );
      }).toList();
      final ordered = _labelAndOrder(opts);
      if (!mounted) return;
      setState(() {
        _options = ordered;
        _selected = 0;
        _routing = false;
      });
      _fitRoute();
    } catch (_) {
      if (mounted) setState(() => _routing = false);
    }
  }

  /// Re-scores existing routes when the hazard list arrives/changes after a
  /// route is already on screen (keeps the verdict in sync without re-routing).
  void _rescoreOptions() {
    if (_options.isEmpty) return;
    final rebuilt = _options.map((o) {
      final a = _assess(o.points);
      return _RouteOption(
        points: o.points,
        distanceKm: o.distanceKm,
        durationMin: o.durationMin,
        score: a.score,
        safety: a.safety,
        hits: a.hits,
      );
    }).toList();
    _options = _labelAndOrder(rebuilt);
    if (_selected >= _options.length) _selected = 0;
  }

  /// Scores a single route against live hazards (0–100, higher = safer).
  /// Closer + higher-risk hazards cost more; night-only hazards count only at
  /// night, so the verdict is time-aware.
  _RouteAssessment _assess(List<LatLng> pts) {
    const dist = Distance();
    final hour = DateTime.now().hour;
    final isNight = hour >= 19 || hour < 6;
    final hits = <_DangerZone>[];
    double penalty = 0;
    for (final z in _zones) {
      if (z.nightOnly && !isNight) continue; // not risky right now
      double min = double.infinity;
      for (final p in pts) {
        final d = dist.as(LengthUnit.Meter, p, z.point);
        if (d < min) min = d;
      }
      if (min <= 500) {
        hits.add(z);
        final risk = z.risk.toLowerCase();
        final base = risk == 'high'
            ? 34.0
            : risk == 'medium'
                ? 18.0
                : 9.0;
        final proximity = (1 - (min / 500)).clamp(0.0, 1.0); // 0..1
        penalty += base * (0.5 + 0.5 * proximity);
      }
    }
    final score = (100 - penalty).clamp(0, 100).round();
    final safety = hits.any((z) => z.risk.toLowerCase() == 'high')
        ? 'avoid'
        : hits.isNotEmpty
            ? 'caution'
            : 'safe';
    return _RouteAssessment(score, safety, hits);
  }

  /// Labels routes Safest / Balanced / Fastest and returns them in tab order.
  /// Degrades gracefully when OSRM returns fewer than 3 alternatives.
  List<_RouteOption> _labelAndOrder(List<_RouteOption> opts) {
    if (opts.isEmpty) return opts;
    if (opts.length == 1) {
      opts.first.label = 'Recommended';
      return opts;
    }
    final safest = [...opts]..sort((a, b) =>
        b.score != a.score ? b.score - a.score : a.durationMin - b.durationMin);
    final fastest = [...opts]..sort((a, b) => a.durationMin != b.durationMin
        ? a.durationMin - b.durationMin
        : b.score - a.score);
    final safestOpt = safest.first;
    var fastestOpt = fastest.first;
    if (identical(fastestOpt, safestOpt) && fastest.length > 1) {
      fastestOpt = fastest[1]; // one route shouldn't hold two roles
    }
    final result = <_RouteOption>[];
    safestOpt.label = 'Safest';
    result.add(safestOpt);
    // Balanced = best score/time blend among the routes not already taken.
    final rest = opts
        .where((o) => !identical(o, safestOpt) && !identical(o, fastestOpt))
        .toList();
    if (rest.isNotEmpty) {
      double blend(_RouteOption o) => o.score - o.durationMin * 1.2;
      rest.sort((a, b) => blend(b).compareTo(blend(a)));
      rest.first.label = 'Balanced';
      result.add(rest.first);
    }
    if (!identical(fastestOpt, safestOpt)) {
      fastestOpt.label = 'Fastest';
      result.add(fastestOpt);
    }
    return result;
  }

  void _fitRoute() {
    if (_route.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(_route);
    _map.fitBounds(bounds,
        options: const FitBoundsOptions(padding: EdgeInsets.all(50)));
  }

  Color get _safetyColor => _safety == 'avoid'
      ? _R.alert
      : _safety == 'caution'
          ? _R.caution
          : _R.guardian;

  String get _safetyLabel => _safety == 'avoid'
      ? 'High risk — avoid if possible'
      : _safety == 'caution'
          ? 'Caution — passes near a flagged area'
          : 'Route looks clear';

  /// Opens IN-APP navigation — stays inside SmartSafe instead of launching an
  /// external maps app. Follows live GPS along the route with distance + ETA.
  void _startNavigation() {
    if (_dest == null || _route.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InAppNavigationPage(
          route: _route,
          destination: _dest!,
          destinationName: _destName.isNotEmpty ? _destName : 'Destination',
          totalKm: _distanceKm,
          totalMin: _durationMin,
          routeColor: _safetyColor,
          hazards: _zones
              .map((z) => NavHazard(z.point, z.risk.toLowerCase() == 'high'))
              .toList(),
        ),
      ),
    );
  }

  /// Estimated clock arrival time ("9:42 PM") from the selected route's ETA.
  String _arriveByString() {
    if (_durationMin <= 0) return '';
    final t = DateTime.now().add(Duration(minutes: _durationMin));
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h12:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// TRIP COMPANION — lets the user share this planned trip (destination + live
  /// location + ETA) with chosen emergency contacts, so someone keeps an eye on
  /// their journey. This is the core "safe route" promise: you're never alone.
  Future<void> _shareTrip() async {
    if (_dest == null || _route.isEmpty || _start == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    List<QueryDocumentSnapshot<Map<String, dynamic>>> contacts = const [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('emergency_contacts')
          .where('userId', isEqualTo: uid)
          .get();
      contacts = snap.docs;
    } catch (_) {}

    if (!mounted) return;
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Add an emergency contact first to share your trip.'),
      ));
      return;
    }

    final selected = <String>{for (final c in contacts) c.id};
    var sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _R.indigo,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.share_location_rounded, color: _R.beacon),
                SizedBox(width: 8),
                Text('Share your trip',
                    style: TextStyle(
                        color: _R.fog,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              Text(
                  'Selected contacts get an SMS with your destination, live '
                  'location & ETA — so someone watches over your journey.',
                  style:
                      TextStyle(color: _R.slate, fontSize: 12)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: contacts.map((c) {
                      final d = c.data();
                      final name = d['name']?.toString() ?? 'Contact';
                      final phone = d['phone']?.toString() ?? '';
                      final on = selected.contains(c.id);
                      return CheckboxListTile(
                        value: on,
                        onChanged: phone.isEmpty
                            ? null
                            : (v) => setSheet(() {
                                  if (v == true) {
                                    selected.add(c.id);
                                  } else {
                                    selected.remove(c.id);
                                  }
                                }),
                        activeColor: _R.beacon,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(name,
                            style: TextStyle(
                                color: _R.fog,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            phone.isEmpty ? 'No number' : phone,
                            style: TextStyle(
                                color: _R.slate, fontSize: 12)),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: (sending || selected.isEmpty)
                    ? null
                    : () async {
                        setSheet(() => sending = true);
                        final chosen = contacts
                            .where((c) => selected.contains(c.id))
                            .toList();
                        final ok = await _sendTripShare(chosen);
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            backgroundColor:
                                ok ? _R.guardian : _R.beacon,
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                                ok
                                    ? 'Trip shared — your contacts can watch over you'
                                    : 'Could not share the trip — please try again',
                                style: TextStyle(color: Colors.white)),
                          ));
                        }
                      },
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                    sending ? 'Sharing…' : 'Share with ${selected.length} contact(s)',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _R.beacon,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sends the trip-share SMS to the chosen contacts and records the trip.
  Future<bool> _sendTripShare(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> chosen) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final senderName =
          FirebaseAuth.instance.currentUser?.displayName ?? 'A SmartSafe user';
      final link =
          'https://maps.google.com/?q=${_start!.latitude.toStringAsFixed(5)},${_start!.longitude.toStringAsFixed(5)}';
      final arrive = _arriveByString();
      final msg = '🛡️ SmartSafe — I am on my way\n\n'
          'I am heading to ${_destName.isNotEmpty ? _destName : 'my destination'}.\n'
          '📍 My live location: $link\n'
          '~${_distanceKm.toStringAsFixed(1)} km · ETA $_durationMin min'
          '${arrive.isNotEmpty ? ' (arrive by $arrive)' : ''}.\n\n'
          'Please keep an eye on my journey until I reach safely.\n'
          '— $senderName';

      final phones = chosen
          .map((c) => c.data()['phone']?.toString() ?? '')
          .where((p) => p.isNotEmpty)
          .toList();
      if (phones.isEmpty) return false;

      await sendSMS(message: msg, recipients: phones, sendDirect: true);

      // Record the trip so it can appear in history / dashboard later.
      try {
        await FirebaseFirestore.instance.collection('trips').add({
          'userId': uid,
          'destName': _destName,
          'destLat': _dest!.latitude,
          'destLng': _dest!.longitude,
          'startLat': _start!.latitude,
          'startLng': _start!.longitude,
          'distanceKm': _distanceKm,
          'durationMin': _durationMin,
          'sharedWith': chosen.map((c) => c.id).toList(),
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reverse-geocodes coordinates to a short area name. Tries the device
  /// geocoder first, then OpenStreetMap (Nominatim) so it works on any device.
  Future<String> _areaName(double lat, double lng) async {
    try {
      final pm = await placemarkFromCoordinates(lat, lng);
      if (pm.isNotEmpty) {
        final p = pm.first;
        final s = [p.subLocality, p.locality, p.administrativeArea]
            .where((e) => (e ?? '').trim().isNotEmpty)
            .join(', ');
        if (s.trim().isNotEmpty) return s;
      }
    } catch (_) {}
    try {
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&accept-language=en'),
        headers: {'User-Agent': 'SmartSafeApp/1.0'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final dn = data['display_name']?.toString() ?? '';
        if (dn.isNotEmpty) {
          return dn.split(',').take(3).join(',').trim();
        }
      }
    } catch (_) {}
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }


  void _showHazardDetail(_DangerZone z) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _R.indigo,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(_hazardIcons[z.type] ?? Icons.warning_amber_rounded,
                  color: z.risk.toLowerCase() == 'high'
                      ? _R.alert
                      : _R.caution),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  z.isReport
                      ? '${z.type[0].toUpperCase()}${z.type.substring(1)} — ${z.risk}'
                      : '${z.name} (${z.risk})',
                  style: TextStyle(
                      color: _R.fog,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ]),
            if (z.name.isNotEmpty && z.isReport) ...[
              const SizedBox(height: 6),
              Text(z.name,
                  style: TextStyle(color: _R.slate, fontSize: 12)),
            ],
            if (z.advice.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(z.advice,
                  style: TextStyle(color: _R.fog, fontSize: 13)),
            ],
            if (z.nightOnly) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.nightlight_round,
                    color: _R.beacon, size: 15),
                SizedBox(width: 6),
                Text('Mainly risky at night',
                    style:
                        TextStyle(color: _R.beacon, fontSize: 12)),
              ]),
            ],
            if (z.isReport) ...[
              const SizedBox(height: 10),
              Text(
                  'Reported by ${z.reporter}${z.whenStr.isNotEmpty ? ' · ${z.whenStr}' : ''}',
                  style: TextStyle(color: _R.slate, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Responsive map height — never squished on short devices, never dominant
    // on tall ones. The whole screen scrolls as one, so nothing overlaps.
    final double mapHeight = (MediaQuery.of(context).size.height * 0.42)
        .clamp(280.0, 460.0)
        .toDouble();
    return Scaffold(
      backgroundColor: _R.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: DesignTokens.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  20, DesignTokens.space16, 20, DesignTokens.space12),
              child: Row(
                children: [
                  if (Navigator.canPop(context)) ...[
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: _R.indigo, shape: BoxShape.circle),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            color: _R.fog, size: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DynText('safe_route', 'title', 'Plan a safe route',
                          style: TextStyle(
                              color: _R.fog,
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                      DynText('safe_route', 'subtitle',
                          'Checked against flagged danger zones',
                          style: TextStyle(color: _R.slate, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

            // From / To — one combined inputs card (mockup style).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: _R.indigo,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        // FROM (live current location)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: _R.line)),
                          ),
                          child: Row(children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _R.guardian,
                                boxShadow: [
                                  BoxShadow(
                                      color: _R.guardian
                                          .withValues(alpha: 0.6),
                                      blurRadius: 8),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 40,
                              child: Text('FROM',
                                  style: TextStyle(
                                      color: _R.slate,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5)),
                            ),
                            Expanded(
                              child: Text(
                                _start == null ? 'Locating…' : _startName,
                                style: TextStyle(
                                    color: _R.fog,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _R.guardian.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('LIVE',
                                  style: TextStyle(
                                      color: _R.guardian,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ]),
                        ),
                        // TO (destination search)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            // Amber pentagon-ish beacon dot.
                            Transform.rotate(
                              angle: 0.785398,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _R.beacon,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                        color: _R.beacon
                                            .withValues(alpha: 0.6),
                                        blurRadius: 8),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 40,
                              child: Text('TO',
                                  style: TextStyle(
                                      color: _R.slate,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5)),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: _onSearchChanged,
                                style: TextStyle(
                                    color: _R.fog,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Where are you headed?',
                                  hintStyle: TextStyle(color: _R.slate),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            if (_searching)
                              SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _R.beacon))
                            else if (_searchCtrl.text.isNotEmpty)
                              GestureDetector(
                                onTap: () => setState(() {
                                  _searchCtrl.clear();
                                  _suggestions = [];
                                }),
                                child: Icon(Icons.clear,
                                    color: _R.slate, size: 18),
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
                        color: _R.indigo,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: _suggestions.map((s) {
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.place_rounded,
                                color: _R.beacon, size: 18),
                            title: Text(
                              (s['display_name']?.toString() ?? '')
                                  .split(',')
                                  .take(2)
                                  .join(','),
                              style: TextStyle(
                                  color: _R.fog, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _pick(s),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.space16),

            // Map (responsive height — details list sits below it)
            SizedBox(
              height: mapHeight,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        center: _start ?? const LatLng(24.8607, 67.0011),
                        zoom: 13,
                        // Stop auto-following the moment the user pans the map,
                        // so live tracking never fights their manual browsing.
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture && _followMe) {
                            setState(() => _followMe = false);
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          // Dark basemap so the map blends with the navy theme.
                          urlTemplate:
                              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'smartsafe.app',
                          // Keep more tiles alive around the viewport so panning
                          // and reopening the map don't re-download everything —
                          // the map feels far quicker after the first load.
                          keepBuffer: 6,
                        ),
                        // GREEN safe-area ring around your current location.
                        if (_start != null)
                          CircleLayer(circles: [
                            CircleMarker(
                              point: _start!,
                              radius: 350,
                              useRadiusInMeter: true,
                              color: _R.guardian.withValues(alpha: 0.12),
                              borderColor:
                                  _R.guardian.withValues(alpha: 0.7),
                              borderStrokeWidth: 2,
                            ),
                          ]),
                        // Danger zones flagged by admin
                        CircleLayer(
                          circles: _zones.map((z) {
                            final isHigh = z.risk.toLowerCase() == 'high';
                            final c = isHigh
                                ? _R.alert
                                : z.risk.toLowerCase() == 'medium'
                                    ? _R.caution
                                    : _R.slate;
                            // High-risk areas are clearly RED-shaded.
                            return CircleMarker(
                              point: z.point,
                              radius: 400,
                              useRadiusInMeter: true,
                              color: c.withValues(alpha: isHigh ? 0.22 : 0.12),
                              borderColor: c.withValues(alpha: isHigh ? 0.9 : 0.6),
                              borderStrokeWidth: isHigh ? 2.5 : 1.5,
                            );
                          }).toList(),
                        ),
                        // LIVE breadcrumb trail — where the user has actually
                        // moved since opening the page (real-time tracking).
                        if (_trace.length > 1)
                          PolylineLayer(polylines: [
                            Polyline(
                              points: _trace,
                              strokeWidth: 4,
                              color:
                                  _R.guardian.withValues(alpha: 0.85),
                              isDotted: true,
                            ),
                          ]),
                        if (_options.isNotEmpty)
                          PolylineLayer(polylines: [
                            // Faint lines for the alternatives not selected…
                            for (int i = 0; i < _options.length; i++)
                              if (i != _selected)
                                Polyline(
                                  points: _options[i].points,
                                  strokeWidth: 4,
                                  color: _R.slate
                                      .withValues(alpha: 0.45),
                                ),
                            // …and the chosen route drawn bright on top.
                            Polyline(
                              points: _route,
                              strokeWidth: 6,
                              color: _safetyColor,
                              borderStrokeWidth: 2,
                              borderColor: Colors.black.withValues(alpha: 0.4),
                            ),
                          ]),
                        MarkerLayer(markers: [
                          // Hazard markers (admin zones + community reports)
                          ..._zones.map((z) {
                            final c = z.risk.toLowerCase() == 'high'
                                ? _R.alert
                                : z.risk.toLowerCase() == 'medium'
                                    ? _R.caution
                                    : _R.slate;
                            final hasWhen = z.whenShort.isNotEmpty;
                            return Marker(
                              point: z.point,
                              width: 130,
                              height: hasWhen ? 56 : 36,
                              builder: (context) => GestureDetector(
                                onTap: () => _showHazardDetail(z),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                      ),
                                      child: Icon(
                                        _hazardIcons[z.type] ??
                                            Icons.warning_amber_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                    // WHEN badge — day, date & time right on the map.
                                    if (hasWhen) ...[
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.72),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: c.withValues(alpha: 0.9),
                                              width: 1),
                                        ),
                                        child: Text(
                                          z.whenShort,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w600,
                                            height: 1.1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                          if (_start != null)
                            Marker(
                              point: _start!,
                              width: 52,
                              height: 52,
                              builder: (context) => const _LiveLocationDot(),
                            ),
                          if (_dest != null)
                            Marker(
                              point: _dest!,
                              width: 40,
                              height: 40,
                              builder: (context) => Icon(
                                  Icons.location_on,
                                  color: _R.beacon,
                                  size: 32),
                            ),
                        ]),
                        const SimpleAttributionWidget(
                            source: Text('OpenStreetMap')),
                      ],
                    ),
                  ),
                  // Legend: what the colours mean.
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _R.indigo.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _R.line),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _legend(_R.guardian, 'Safe'),
                        const SizedBox(width: 10),
                        _legend(_R.caution, 'Caution'),
                        const SizedBox(width: 10),
                        _legend(_R.alert, 'Danger'),
                      ]),
                    ),
                  ),
                  // Recenter + resume live-follow. Highlighted while following.
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: _recenterOnMe,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _R.indigo.withValues(alpha: 0.95),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _followMe ? _R.beacon : _R.line),
                        ),
                        child: Icon(
                          _followMe
                              ? Icons.my_location
                              : Icons.location_searching,
                          color: _followMe ? _R.beacon : _R.slate,
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _R.indigo,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _R.line),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _R.beacon)),
                              SizedBox(width: 8),
                              Text('Finding safest route…',
                                  style: TextStyle(
                                      color: _R.fog, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Below the map: the planned route's safety card, or a clean
            // routing prompt before a destination is chosen (danger-zone
            // reporting lives on the separate Danger Zones page).
            const SizedBox(height: DesignTokens.space16),
            _route.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.space32,
                          horizontal: DesignTokens.space24),
                      decoration: BoxDecoration(
                        color: _R.indigo,
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radius16),
                        border: Border.all(color: _R.line),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.route_rounded,
                              color: _R.beacon, size: 40),
                          const SizedBox(height: DesignTokens.space12),
                          Text('Where do you want to go?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: _R.fog,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: DesignTokens.space8),
                          Text(
                              'Search a destination above to get the safest '
                              'route, scored against nearby danger zones.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _R.slate, fontSize: 12)),
                        ],
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(DesignTokens.space16),
                      decoration: BoxDecoration(
                        color: _R.indigo,
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radius16),
                        border: Border.all(
                            color: _safetyColor.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Route option tabs — Safest / Balanced / Fastest.
                          if (_options.length > 1)
                            Row(
                              children: [
                                for (int i = 0; i < _options.length; i++)
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                          right: i == _options.length - 1
                                              ? 0
                                              : DesignTokens.space8),
                                      child: _routeTab(_options[i], i),
                                    ),
                                  ),
                              ],
                            ),
                          if (_options.length > 1)
                            const SizedBox(height: DesignTokens.space16),
                          // Safety score ring + route name + verdict banner.
                          Row(
                            children: [
                              _scoreRing(_sel?.score ?? 0, _safetyColor),
                              const SizedBox(width: DesignTokens.space12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (_sel?.label.isNotEmpty ?? false)
                                          ? '${_sel!.label} route'
                                          : 'Route',
                                      style: TextStyle(
                                          color: _R.fog,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Icon(
                                            _safety == 'safe'
                                                ? Icons.verified_user_rounded
                                                : Icons
                                                    .warning_amber_rounded,
                                            color: _safetyColor,
                                            size: 15),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(_safetyLabel,
                                              style: TextStyle(
                                                  color: _safetyColor,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  fontSize: 12),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: DesignTokens.space16),
                          // Stat chips — a Wrap so km / min / near never
                          // overflow on narrow devices.
                          Wrap(
                            spacing: DesignTokens.space8,
                            runSpacing: DesignTokens.space8,
                            children: [
                              _stat(Icons.straighten_rounded,
                                  '${_distanceKm.toStringAsFixed(1)} km'),
                              _stat(Icons.timer_outlined,
                                  '$_durationMin min'),
                              _stat(
                                  Icons.report_problem_rounded,
                                  _hits.isEmpty
                                      ? 'Clear'
                                      : '${_hits.length} near',
                                  danger: _hits.isNotEmpty),
                            ],
                          ),
                          if (_durationMin > 0) ...[
                            const SizedBox(height: DesignTokens.space8),
                            Row(children: [
                              Icon(Icons.schedule_rounded,
                                  color: _R.slate, size: 13),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                    'Arrive by ${_arriveByString()}',
                                    style: TextStyle(
                                        color: _R.slate,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                          ],
                          // Flagged danger points along the route.
                          if (_hits.isNotEmpty) ...[
                            const SizedBox(height: DesignTokens.space8),
                            ..._hits.take(3).map(_dangerCard),
                          ],
                          const SizedBox(height: DesignTokens.space16),
                          // Buddy share — tap to share destination + live
                          // location with an emergency contact until arrival.
                          GestureDetector(
                            onTap: _shareTrip,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: _R.indigoSoft,
                                borderRadius: BorderRadius.circular(
                                    DesignTokens.radius14),
                                border: Border.all(
                                    color: _R.guardian
                                        .withValues(alpha: 0.25)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(colors: [
                                      _R.guardian,
                                      Color(0xFF2A8F88),
                                    ]),
                                  ),
                                  child: Icon(Icons.person_rounded,
                                      color: _R.navy, size: 18),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Share live with a buddy',
                                          style: TextStyle(
                                              color: _R.fog,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      SizedBox(height: 2),
                                      Text(
                                          "They'll see your route until you arrive",
                                          style: TextStyle(
                                              color: _R.slate, fontSize: 11),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.share_location_rounded,
                                    color: _R.guardian, size: 20),
                              ]),
                            ),
                          ),
                          const SizedBox(height: DesignTokens.space16),
                          // Full-width primary CTA.
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _startNavigation,
                              icon: const Icon(Icons.navigation_rounded,
                                  size: 18, color: Colors.white),
                              label: const Text('Start safe navigation',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _R.beacon,
                                minimumSize: const Size(0, 54),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        DesignTokens.radius16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _legend(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              color: _R.fog,
              fontSize: 10,
              fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _stat(IconData icon, String value, {bool danger = false}) {
    final Color c = danger ? _R.caution : _R.beacon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: danger ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: danger ? 0.40 : 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 14),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  color: danger ? _R.caution : _R.fog,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Theme colour for a hazard severity (High → red, Medium → amber, else muted).
  Color _severityColor(String risk) {
    final r = risk.toLowerCase();
    return r == 'high'
        ? _R.alert
        : r == 'medium'
            ? _R.caution
            : _R.slate;
  }

  /// Small readable severity pill (High / Medium / Low) in the right theme tone.
  Widget _severityChip(String risk) {
    final c = _severityColor(risk);
    final label = risk.isEmpty
        ? 'Low'
        : '${risk[0].toUpperCase()}${risk.substring(1).toLowerCase()}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: c,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2)),
    );
  }

  /// One flagged danger point along the route: severity-tinted icon, a readable
  /// title (truncated), a severity pill, and the reason with maxLines+ellipsis.
  Widget _dangerCard(_DangerZone z) {
    final c = _severityColor(z.risk);
    final title = z.name.isNotEmpty
        ? z.name
        : (z.isReport && z.type.isNotEmpty
            ? '${z.type[0].toUpperCase()}${z.type.substring(1)} report'
            : 'Danger zone');
    return GestureDetector(
      onTap: () => _showHazardDetail(z),
      child: Container(
        margin: const EdgeInsets.only(top: DesignTokens.space8),
        padding: const EdgeInsets.all(DesignTokens.space12),
        decoration: BoxDecoration(
          color: _R.indigoSoft,
          borderRadius: BorderRadius.circular(DesignTokens.radius12),
          border: Border.all(color: c.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_hazardIcons[z.type] ?? Icons.warning_amber_rounded,
                  color: c, size: 16),
            ),
            const SizedBox(width: DesignTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(title,
                            style: TextStyle(
                                color: _R.fog,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      _severityChip(z.risk),
                    ],
                  ),
                  if (z.advice.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(z.advice,
                        style: TextStyle(
                            color: _R.slate, fontSize: 11, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One selectable route tab showing its role + safety score.
  Widget _routeTab(_RouteOption o, int index) {
    final selected = index == _selected;
    return GestureDetector(
      onTap: () {
        setState(() => _selected = index);
        _fitRoute();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? _R.beacon : _R.indigoSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              o.label.isNotEmpty ? o.label : 'Route',
              style: TextStyle(
                color: selected ? Colors.white : _R.slate,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${o.score} · ${o.durationMin}m',
              style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.75)
                      : _R.slate.withValues(alpha: 0.7),
                  fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  /// Circular safety-score gauge (0–100) coloured by the route's verdict.
  Widget _scoreRing(int score, Color color) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              strokeWidth: 5,
              backgroundColor: _R.fog.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              color: _R.fog,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated "you are here" marker — a solid dot with a soft pulsing ring so the
/// user's LIVE position reads clearly as real-time on the map.
class _LiveLocationDot extends StatefulWidget {
  const _LiveLocationDot();

  @override
  State<_LiveLocationDot> createState() => _LiveLocationDotState();
}

class _LiveLocationDotState extends State<_LiveLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1
        return Stack(
          alignment: Alignment.center,
          children: [
            // Expanding, fading pulse ring.
            Container(
              width: 20 + 32 * t,
              height: 20 + 32 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _R.beacon.withValues(alpha: (1 - t) * 0.35),
              ),
            ),
            // Solid core with a white border + glow.
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _R.beacon,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: _R.beacon.withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ));
  }
}

/// Small pill button used for the date / time pickers in the report form.
class _PickerBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _R.navy,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _R.line),
        ),
        child: Row(children: [
          Icon(icon, color: _R.beacon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(color: _R.fog, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }
}
