import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../services/location_service.dart';
import '14_nearest_hospitals_page.dart';
import '17_safety_feed_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

/// A danger zone or community hazard drawn on the live map.
class _MapZone {
  final LatLng point;
  final String name;
  final String risk;
  const _MapZone(this.point, this.name, this.risk);
}

/// A nearby SmartSafe user currently sharing their location.
class _MapUser {
  final LatLng point;
  final String name;
  const _MapUser(this.point, this.name);
}

class _MapPageState extends State<MapPage> {
  final MapController _mapCtrl = MapController();

  double _lat = 0.0;
  double _lon = 0.0;
  double _accuracy = 3.0;
  double _speed = 0.0;
  bool _isSharing = false;
  String _placeName = '';
  DateTime? _lastGeocodeTime;
  StreamSubscription<LocationData>? _locationSub;

  // Live path trail (most recent points the user has moved through).
  final List<LatLng> _path = [];

  // Overlays: danger zones, nearby users, nearest hospital.
  final List<_MapZone> _zones = [];
  final List<_MapUser> _users = [];
  double? _nearestKm;
  LatLng? _nearestPt;
  String _nearestName = '';
  LatLng? _lastHospitalFix; // refetch hospital only after moving enough
  DateTime? _lastHospitalFetchTime;

  // Nearby users: ONE Firestore listener covering a ±~5.5 km latitude band
  // around the user (re-created only when they move ~2 km out of it), instead
  // of re-querying the whole collection every 20 seconds. Firestore pushes
  // doc deltas after the initial sync, so the overlay stays live at a
  // fraction of the reads.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _nearbySub;
  LatLng? _nearbyCenter;
  static const _hospitalFetchInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _isSharing = LocationService.instance.isTracking;
    _loadZones();
    if (_isSharing) {
      _startListening();
      LocationService.instance.getCurrentLocation().then((loc) {
        if (loc != null && mounted) {
          setState(() {
            _lat = loc.latitude;
            _lon = loc.longitude;
          });
          _onNewFix(loc.latitude, loc.longitude);
        }
      });
    }
  }

  void _startListening() {
    _locationSub?.cancel();
    _locationSub = LocationService.instance.onLocationChanged.listen((data) {
      if (!mounted) return;
      setState(() {
        _lat = data.latitude;
        _lon = data.longitude;
        _accuracy = data.accuracy;
        _speed = data.speed;
      });
      _onNewFix(data.latitude, data.longitude);
    });
  }

  /// Called on every fresh GPS fix — grows the trail, follows the map, and
  /// refreshes the place name / nearest hospital / nearby overlays.
  void _onNewFix(double lat, double lon) {
    final pt = LatLng(lat, lon);
    // Append to the trail only when we've actually moved (>5 m) to avoid jitter.
    if (_path.isEmpty || _distKm(_path.last.latitude, _path.last.longitude, lat, lon) * 1000 > 5) {
      _path.add(pt);
      if (_path.length > 300) _path.removeAt(0);
    }
    try {
      _mapCtrl.move(pt, _mapCtrl.zoom);
    } catch (_) {}

    _fetchPlaceName(lat, lon);

    // Refetch the nearest hospital after the user moves ~400 m (or first fix),
    // but at most once a minute — Overpass is a free public API and at road
    // speed 400 m passes in seconds.
    final now = DateTime.now();
    final hospitalDue = _lastHospitalFix == null ||
        _distKm(_lastHospitalFix!.latitude, _lastHospitalFix!.longitude,
                    lat, lon) *
                1000 >
            400;
    final hospitalRateOk = _lastHospitalFetchTime == null ||
        now.difference(_lastHospitalFetchTime!) >= _hospitalFetchInterval;
    if (hospitalDue && hospitalRateOk) {
      _lastHospitalFix = pt;
      _lastHospitalFetchTime = now;
      _fetchNearestHospital(lat, lon);
    }

    _ensureNearbyListener(lat, lon);
  }

  double _distKm(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0;
    final dLa = (la2 - la1) * pi / 180;
    final dLo = (lo2 - lo1) * pi / 180;
    final a = sin(dLa / 2) * sin(dLa / 2) +
        cos(la1 * pi / 180) * cos(la2 * pi / 180) * sin(dLo / 2) * sin(dLo / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
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
        String placeName = data['display_name'] ?? '';
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final parts = [
            address['house_number'],
            address['road'],
            address['suburb'] ?? address['neighbourhood'],
            address['city'] ?? address['town'] ?? address['village'],
            address['state'],
          ].whereType<String>().toList();
          if (parts.isNotEmpty) placeName = parts.join(', ');
        }
        if (placeName.isNotEmpty && mounted) {
          setState(() => _placeName = placeName);
        }
      }
    } catch (_) {}
  }

  /// REAL nearest hospital via OpenStreetMap Overpass — works anywhere, not a
  /// hardcoded number. Picks the closest hospital within 8 km.
  Future<void> _fetchNearestHospital(double lat, double lon) async {
    try {
      final query =
          '[out:json][timeout:10];node["amenity"="hospital"](around:8000,$lat,$lon);out;';
      final url = Uri.parse(
          'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}');
      final res = await http
          .get(url, headers: {'User-Agent': 'SmartSafeApp/1.0'}).timeout(
              const Duration(seconds: 12));
      if (res.statusCode != 200) return;
      final data = json.decode(res.body);
      final elements = (data['elements'] as List?) ?? [];
      double? bestKm;
      LatLng? bestPt;
      String bestName = 'Hospital';
      for (final e in elements) {
        final hlat = (e['lat'] as num?)?.toDouble();
        final hlon = (e['lon'] as num?)?.toDouble();
        if (hlat == null || hlon == null) continue;
        final d = _distKm(lat, lon, hlat, hlon);
        if (bestKm == null || d < bestKm) {
          bestKm = d;
          bestPt = LatLng(hlat, hlon);
          bestName = (e['tags']?['name'] ?? 'Hospital').toString();
        }
      }
      if (bestKm != null && mounted) {
        setState(() {
          _nearestKm = bestKm;
          _nearestPt = bestPt;
          _nearestName = bestName;
        });
      }
    } catch (_) {}
  }

  /// Admin danger zones + community hazards — shown as red markers/circles.
  Future<void> _loadZones() async {
    final loaded = <_MapZone>[];
    try {
      final snap =
          await FirebaseFirestore.instance.collection('danger_zones').get();
      for (final d in snap.docs) {
        final m = d.data();
        final coords = (m['coordinates'] ?? '').toString().split(',');
        if (coords.length < 2) continue;
        final la = double.tryParse(coords[0].trim());
        final lo = double.tryParse(coords[1].trim());
        if (la == null || lo == null) continue;
        loaded.add(_MapZone(LatLng(la, lo), m['name']?.toString() ?? 'Danger zone',
            m['riskLevel']?.toString() ?? 'Medium'));
      }
    } catch (_) {}
    try {
      final snap =
          await FirebaseFirestore.instance.collection('route_hazards').get();
      for (final d in snap.docs) {
        final m = d.data();
        final la = (m['latitude'] as num?)?.toDouble();
        final lo = (m['longitude'] as num?)?.toDouble();
        if (la == null || lo == null) continue;
        loaded.add(_MapZone(LatLng(la, lo), m['locationName']?.toString() ?? 'Hazard',
            m['riskLevel']?.toString() ?? 'High'));
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _zones
          ..clear()
          ..addAll(loaded);
      });
    }
  }

  /// Keeps one live listener on `live_tracking` around the user. It is
  /// re-created only when the user moves ~2 km from the band center so the
  /// query window follows them without churning subscriptions.
  void _ensureNearbyListener(double lat, double lon) {
    final center = _nearbyCenter;
    if (_nearbySub != null &&
        center != null &&
        _distKm(center.latitude, center.longitude, lat, lon) <= 2.0) {
      return;
    }
    _nearbyCenter = LatLng(lat, lon);
    _nearbySub?.cancel();
    _nearbySub = FirebaseFirestore.instance
        .collection('live_tracking')
        .where('latitude', isGreaterThan: lat - 0.05)
        .where('latitude', isLessThan: lat + 0.05)
        .limit(100)
        .snapshots()
        .listen((snap) => _onNearbyUsers(snap), onError: (_) {});
  }

  /// Maps a nearby-users snapshot to overlay markers. Freshness + true
  /// distance are filtered in memory exactly like the old polling version.
  void _onNearbyUsers(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted || !_isSharing) return;
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (_lat == 0.0 && _lon == 0.0) return;
    final list = <_MapUser>[];
    for (final d in snap.docs) {
      if (d.id == me) continue;
      final m = d.data();
      final ula = (m['latitude'] as num?)?.toDouble();
      final ulo = (m['longitude'] as num?)?.toDouble();
      if (ula == null || ulo == null) continue;
      // Only count a fresh fix (updated within the last 5 minutes) so a doc
      // left behind by a crash doesn't inflate the count.
      final ts = m['updatedAt'] ?? m['timestamp'];
      if (ts is Timestamp &&
          DateTime.now().difference(ts.toDate()).inMinutes > 5) {
        continue;
      }
      if (_distKm(_lat, _lon, ula, ulo) > 5.0) continue;
      list.add(_MapUser(
          LatLng(ula, ulo),
          m['name']?.toString() ??
              m['userName']?.toString() ??
              'User'));
    }
    setState(() {
      _users
        ..clear()
        ..addAll(list);
    });
  }

  void _toggleTracking() async {
    if (_isSharing) {
      LocationService.instance.stopTracking();
      _locationSub?.cancel();
      _locationSub = null;
      _nearbySub?.cancel();
      _nearbySub = null;
      _nearbyCenter = null;
      setState(() {
        _isSharing = false;
        _lat = 0.0;
        _lon = 0.0;
        _placeName = '';
        _users.clear();
        _path.clear();
      });
    } else {
      final errorMsg = await LocationService.instance.requestPermission();
      if (errorMsg == null) {
        LocationService.instance.startTracking();
        _startListening();
        setState(() => _isSharing = true);
        final loc = await LocationService.instance.getCurrentLocation();
        if (loc != null && mounted) {
          setState(() {
            _lat = loc.latitude;
            _lon = loc.longitude;
          });
          _onNewFix(loc.latitude, loc.longitude);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppColors.accent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Text(errorMsg, style: TextStyle(color: Colors.white)),
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _nearbySub?.cancel();
    super.dispose();
  }

  Color _riskColor(String risk) => risk.toLowerCase() == 'high'
      ? C.red
      : risk.toLowerCase() == 'medium'
          ? AppColors.warning
          : AppColors.textMuted;

  @override
  Widget build(BuildContext context) {
    final hasFix = _isSharing && _lat != 0.0;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: SlideUpFade(
                    child: Row(
                      children: [
                        if (Navigator.canPop(context)) ...[
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Icon(Icons.arrow_back_ios_new_rounded,
                                color: C.textPrimary, size: 18),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text('Live Map',
                            style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_isSharing ? AppColors.success : AppColors.accent)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: (_isSharing ? AppColors.success : AppColors.accent)
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              BlinkDot(
                                  color: _isSharing ? AppColors.success : AppColors.accent,
                                  size: 8),
                              const SizedBox(width: 6),
                              Text(_isSharing ? 'BROADCASTING' : 'OFFLINE',
                                  style: TextStyle(
                                    color: _isSharing ? AppColors.success : AppColors.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Map
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SlideUpFade(
                      delay: const Duration(milliseconds: 100),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.bg3,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: hasFix
                                    ? FlutterMap(
                                        mapController: _mapCtrl,
                                        options: MapOptions(
                                          center: LatLng(_lat, _lon),
                                          zoom: 16,
                                          minZoom: 3,
                                          interactiveFlags: InteractiveFlag.all,
                                        ),
                                        children: [
                                          TileLayer(
                                            urlTemplate:
                                                'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                                            subdomains: const ['a', 'b', 'c', 'd'],
                                            userAgentPackageName: 'smartsafe.app',
                                            keepBuffer: 6,
                                          ),
                                          // Danger zone circles
                                          CircleLayer(
                                            circles: _zones.map((z) {
                                              final c = _riskColor(z.risk);
                                              return CircleMarker(
                                                point: z.point,
                                                radius: 300,
                                                useRadiusInMeter: true,
                                                color: c.withValues(alpha: 0.15),
                                                borderColor: c.withValues(alpha: 0.7),
                                                borderStrokeWidth: 1.5,
                                              );
                                            }).toList(),
                                          ),
                                          // Live path trail
                                          if (_path.length > 1)
                                            PolylineLayer(polylines: [
                                              Polyline(
                                                points: _path,
                                                strokeWidth: 4,
                                                color: AppColors.accentLight,
                                                borderStrokeWidth: 1,
                                                borderColor: Colors.black
                                                    .withValues(alpha: 0.3),
                                              ),
                                            ]),
                                          MarkerLayer(markers: [
                                            // Danger zone markers
                                            ..._zones.map((z) => Marker(
                                                  point: z.point,
                                                  width: 30,
                                                  height: 30,
                                                  builder: (_) => Icon(
                                                      Icons.warning_amber_rounded,
                                                      color: _riskColor(z.risk),
                                                      size: 26),
                                                )),
                                            // Nearby users
                                            ..._users.map((u) => Marker(
                                                  point: u.point,
                                                  width: 28,
                                                  height: 28,
                                                  builder: (_) => Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: AppColors.accent,
                                                      border: Border.all(
                                                          color: Colors.white,
                                                          width: 2),
                                                    ),
                                                    child: const Icon(Icons.person,
                                                        color: Colors.white,
                                                        size: 15),
                                                  ),
                                                )),
                                            // Nearest hospital
                                            if (_nearestPt != null)
                                              Marker(
                                                point: _nearestPt!,
                                                width: 30,
                                                height: 30,
                                                builder: (_) => Container(
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: AppColors.success,
                                                    border: Border.all(
                                                        color: Colors.white,
                                                        width: 2),
                                                  ),
                                                  child: const Icon(
                                                      Icons.local_hospital_rounded,
                                                      color: Colors.white,
                                                      size: 16),
                                                ),
                                              ),
                                            // Me (current location)
                                            Marker(
                                              point: LatLng(_lat, _lon),
                                              width: 40,
                                              height: 40,
                                              builder: (_) => const _LocationPin(),
                                            ),
                                          ]),
                                        ],
                                      )
                                    : CustomPaint(painter: GPSMapPainter()),
                              ),
                              if (!hasFix)
                                Center(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      PulseRing(
                                          color: AppColors.accent,
                                          size: 60,
                                          ringCount: 2),
                                      const _LocationPin(),
                                    ],
                                  ),
                                ),
                              // Live place bar
                              Positioned(
                                top: 12,
                                left: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.bg.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: (_isSharing
                                                ? AppColors.success
                                                : AppColors.accent)
                                            .withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.location_on_rounded,
                                          color: _isSharing
                                              ? AppColors.success
                                              : AppColors.accent,
                                          size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          hasFix
                                              ? (_placeName.isNotEmpty
                                                  ? _placeName
                                                  : '${_lat.toStringAsFixed(5)}, ${_lon.toStringAsFixed(5)}')
                                              : 'Live Location Sharing Offline',
                                          style: TextStyle(
                                              color: C.textPrimary,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_isSharing) ...[
                                        const SizedBox(width: 8),
                                        WaveBars(color: AppColors.success, height: 18),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              // Recenter + Safety Feed
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: Row(
                                  children: [
                                    if (hasFix)
                                      GestureDetector(
                                        onTap: () => _mapCtrl.move(
                                            LatLng(_lat, _lon), 16),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.bg.withValues(alpha: 0.9),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppColors.border),
                                          ),
                                          child: Icon(Icons.my_location_rounded,
                                              color: AppColors.accent, size: 18),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => const SafetyFeedPage()),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.accent
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.rss_feed_rounded,
                                                color: Colors.white, size: 14),
                                            SizedBox(width: 6),
                                            Text('Safety Feed',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Stats row
                SlideUpFade(
                  delay: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.people_rounded,
                            label: 'Nearby',
                            value: hasFix ? '${_users.length}' : '—',
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const NearestHospitalsPage()),
                            ),
                            child: _StatCard(
                              icon: Icons.local_hospital_rounded,
                              label: _nearestName.isNotEmpty &&
                                      _nearestName != 'Hospital'
                                  ? 'Hospital'
                                  : 'Nearest',
                              value: _nearestKm != null
                                  ? '${_nearestKm!.toStringAsFixed(1)} km'
                                  : '—',
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.speed_rounded,
                            label: 'Speed',
                            // Geolocator reports speed in m/s — convert to km/h.
                            value: hasFix
                                ? '${(_speed < 0 ? 0 : _speed * 3.6).toStringAsFixed(1)} km/h'
                                : '—',
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Toggle tracker card
                SlideUpFade(
                  delay: const Duration(milliseconds: 280),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _toggleTracking,
                        borderRadius: BorderRadius.circular(16),
                        child: DCard(
                          borderColor: C.border,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: C.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _isSharing
                                        ? Icons.radar_rounded
                                        : Icons.location_disabled_rounded,
                                    color: C.accent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isSharing
                                            ? 'Location Tracker Active'
                                            : 'Location Tracker Offline',
                                        style: TextStyle(
                                            color: C.textPrimary,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13),
                                      ),
                                      Text(
                                        _isSharing
                                            ? 'Tap to disable live GPS sharing'
                                            : 'Tap to start live location sharing',
                                        style: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _isSharing,
                                  onChanged: (_) => _toggleTracking(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationPin extends StatelessWidget {
  const _LocationPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.5),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 16),
        ),
        Container(width: 2, height: 8, color: AppColors.accent),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: C.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(color: C.textMuted, fontSize: 9)),
        ],
      ),
    );
  }
}

class GPSMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final scanPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 120, scanPaint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 70, scanPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
