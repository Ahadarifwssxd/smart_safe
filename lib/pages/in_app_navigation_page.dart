import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/colors.dart';

/// A danger zone passed into the navigation view (kept simple/public so it can
/// be built from the Safe Route page's private hazard list).
class NavHazard {
  final LatLng point;
  final bool high;
  const NavHazard(this.point, this.high);
}

/// Full-screen IN-APP turn-by-turn style navigation. Instead of launching an
/// external maps app, this keeps the user inside SmartSafe: it follows their
/// live GPS along the planned route, shows remaining distance + ETA, keeps the
/// danger zones visible, and recenters on them as they move.
class InAppNavigationPage extends StatefulWidget {
  final List<LatLng> route;
  final LatLng destination;
  final String destinationName;
  final double totalKm;
  final int totalMin;
  final Color routeColor;
  final List<NavHazard> hazards;

  const InAppNavigationPage({
    super.key,
    required this.route,
    required this.destination,
    required this.destinationName,
    required this.totalKm,
    required this.totalMin,
    required this.routeColor,
    this.hazards = const [],
  });

  @override
  State<InAppNavigationPage> createState() => _InAppNavigationPageState();
}

class _InAppNavigationPageState extends State<InAppNavigationPage> {
  final MapController _map = MapController();
  StreamSubscription<Position>? _posSub;
  LatLng? _me;
  double _bearing = 0;
  bool _follow = true;
  bool _arrived = false;

  static const _dist = Distance();

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      // Seed with one quick fix so the arrow shows immediately.
      final first = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _onPosition(first);

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 4,
        ),
      ).listen(_onPosition);
    } catch (_) {}
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    final me = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _me = me;
      if (pos.heading >= 0) _bearing = pos.heading;
      if (_dist.as(LengthUnit.Meter, me, widget.destination) <= 35) {
        _arrived = true;
      }
    });
    if (_follow) {
      _map.move(me, 16.5);
    }
  }

  /// Remaining distance (km) along the route from the user's nearest point.
  double get _remainingKm {
    final route = widget.route;
    if (_me == null || route.isEmpty) return widget.totalKm;
    int nearest = 0;
    double best = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final d = _dist.as(LengthUnit.Meter, _me!, route[i]);
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    double meters = _dist.as(LengthUnit.Meter, _me!, route[nearest]);
    for (var i = nearest; i < route.length - 1; i++) {
      meters += _dist.as(LengthUnit.Meter, route[i], route[i + 1]);
    }
    return meters / 1000;
  }

  int get _etaMin {
    if (widget.totalKm <= 0) return widget.totalMin;
    final ratio = (_remainingKm / widget.totalKm).clamp(0.0, 1.0);
    return (widget.totalMin * ratio).round();
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${widget.destination.latitude},${widget.destination.longitude}&travelmode=driving');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _me ??
        (widget.route.isNotEmpty ? widget.route.first : widget.destination);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              center: center,
              zoom: 16,
              maxZoom: 18,
              minZoom: 10,
              onPositionChanged: (pos, hasGesture) {
                // The user dragged the map → stop auto-following until they
                // tap "recenter".
                if (hasGesture && _follow) setState(() => _follow = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'smartsafe.app',
                keepBuffer: 6,
              ),
              // Danger zones stay visible while navigating, but with light
              // translucent fills so overlapping zones never stack into a dark
              // mass that hides the map — the ring is the primary indicator.
              CircleLayer(
                circles: widget.hazards
                    .map((h) => CircleMarker(
                          point: h.point,
                          radius: h.high ? 260 : 220,
                          useRadiusInMeter: true,
                          color: (h.high ? AppColors.accent : AppColors.warning)
                              .withValues(alpha: h.high ? 0.10 : 0.06),
                          borderColor:
                              (h.high ? AppColors.accent : AppColors.warning)
                                  .withValues(alpha: h.high ? 0.85 : 0.55),
                          borderStrokeWidth: h.high ? 2 : 1.5,
                        ))
                    .toList(),
              ),
              if (widget.route.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: widget.route,
                    strokeWidth: 7,
                    color: widget.routeColor,
                    borderStrokeWidth: 2,
                    borderColor: Colors.black.withValues(alpha: 0.4),
                  ),
                ]),
              MarkerLayer(markers: [
                Marker(
                  point: widget.destination,
                  width: 40,
                  height: 40,
                  builder: (_) =>
                      Icon(Icons.location_on, color: AppColors.accent, size: 34),
                ),
                if (_me != null)
                  Marker(
                    point: _me!,
                    width: 46,
                    height: 46,
                    builder: (_) => Transform.rotate(
                      angle: _bearing * math.pi / 180,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accentLight,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6)
                          ],
                        ),
                        child: const Icon(Icons.navigation_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
              ]),
            ],
          ),

          // Top banner: destination + remaining distance + ETA.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.bg2.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppTheme.cardShadow(),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: C.textPrimary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _arrived ? 'You have arrived' : 'Navigating to',
                            style: TextStyle(
                                color: _arrived
                                    ? AppColors.success
                                    : AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            widget.destinationName,
                            style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${_remainingKm.toStringAsFixed(1)} km',
                            style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        Text('$_etaMin min',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Recenter button (appears when the user has panned away).
          if (!_follow)
            Positioned(
              right: 16,
              bottom: 120 + MediaQuery.of(context).padding.bottom,
              child: FloatingActionButton(
                heroTag: 'recenter',
                mini: true,
                backgroundColor: AppColors.bg2,
                onPressed: () {
                  setState(() => _follow = true);
                  if (_me != null) _map.move(_me!, 16.5);
                },
                child: Icon(Icons.my_location_rounded, color: AppColors.accent),
              ),
            ),

          // Bottom controls + map attribution stacked so the OpenStreetMap
          // credit is never hidden behind the action buttons.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Attribution pill sits above the action bar.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.bg.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '© OpenStreetMap',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(_arrived
                                ? Icons.check_circle_rounded
                                : Icons.close_rounded),
                            label: Text(_arrived ? 'Done' : 'End',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _arrived
                                  ? AppColors.success
                                  : AppColors.accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 50),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Optional: hand off to Google Maps if the user prefers.
                        Flexible(
                          child: OutlinedButton.icon(
                            onPressed: _openExternal,
                            icon: const Icon(Icons.map_rounded, size: 18),
                            label: const Text('Google Maps',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: C.textPrimary,
                              side: BorderSide(color: AppColors.border),
                              minimumSize: const Size(0, 50),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
