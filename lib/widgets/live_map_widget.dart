import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/live_tracking_service.dart';
import '../services/routing_service.dart';
import '../theme/colors.dart';

class LiveMapWidget extends StatefulWidget {
  final double myLatitude;
  final double myLongitude;
  final String myAddress;
  final List<HelperInfo> helpers;
  final bool showRoute;
  final Function(HelperInfo)? onHelperTap;

  /// SOS broadcast radius (km) drawn as a circle on the map. 0 = no circle.
  final double sosRadiusKm;

  const LiveMapWidget({
    Key? key,
    required this.myLatitude,
    required this.myLongitude,
    this.myAddress = '',
    this.helpers = const [],
    this.showRoute = true,
    this.onHelperTap,
    this.sosRadiusKm = 5.0,
  }) : super(key: key);

  @override
  State<LiveMapWidget> createState() => _LiveMapWidgetState();
}

class _LiveMapWidgetState extends State<LiveMapWidget> {
  late final MapController _mapController;
  final Map<String, List<LatLng>> _helperRoutes = {};

  // Route fetching guards. didUpdateWidget fires on EVERY helper/own position
  // tick (several times a minute while someone drives), and each changed
  // endpoint used to trigger a fresh OSRM HTTP request. A short debounce
  // coalesces bursts, and a per-helper minimum interval keeps steady-state
  // traffic to one request per helper per ~15 s.
  Timer? _routeDebounce;
  final Map<String, DateTime> _lastRouteFetchAt = {};
  static const _routeRefreshInterval = Duration(seconds: 15);

  bool _mapReady = false;
  bool _didInitialFit = false;
  int _lastHelperCount = -1;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _updateRoutes();
  }

  @override
  void didUpdateWidget(covariant LiveMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleRouteUpdate();
    // Re-fit the camera when the helper SET changes (someone joins/leaves) or
    // when our own position first becomes available — so the helper marker and
    // the route are always on-screen instead of off the edge.
    final helperCount = _validHelpers.length;
    final myMoved = oldWidget.myLatitude != widget.myLatitude ||
        oldWidget.myLongitude != widget.myLongitude;
    if (helperCount != _lastHelperCount || myMoved) {
      _lastHelperCount = helperCount;
      _fitToContent();
    }
  }

  /// A point counts as real only if it isn't (0,0) "null island" or NaN — that
  /// guards against a half-written helper doc placing a marker off Africa.
  bool _isValidLatLng(double lat, double lon) {
    if (lat.isNaN || lon.isNaN) return false;
    if (lat.abs() < 0.0001 && lon.abs() < 0.0001) return false;
    return lat.abs() <= 90 && lon.abs() <= 180;
  }

  List<HelperInfo> get _validHelpers => widget.helpers
      .where((h) => _isValidLatLng(h.latitude, h.longitude))
      .toList();

  /// Fits the camera around the victim, every valid helper, and the route so
  /// the whole rescue picture is visible at once.
  void _fitToContent() {
    if (!_mapReady || !mounted) return;
    final pts = <LatLng>[LatLng(widget.myLatitude, widget.myLongitude)];
    for (final h in _validHelpers) {
      pts.add(LatLng(h.latitude, h.longitude));
    }
    for (final r in _helperRoutes.values) {
      pts.addAll(r);
    }
    if (pts.length <= 1) {
      _mapController.move(pts.first, _fitZoom);
      return;
    }
    _mapController.fitBounds(
      LatLngBounds.fromPoints(pts),
      options: const FitBoundsOptions(
        padding: EdgeInsets.all(64),
        maxZoom: 16.5,
      ),
    );
  }

  /// Coalesces rapid didUpdateWidget calls into a single route pass.
  void _scheduleRouteUpdate() {
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(seconds: 3), _updateRoutes);
  }

  Future<void> _updateRoutes() async {
    bool updated = false;
    final now = DateTime.now();
    for (final helper in _validHelpers) {
      final cachedRoute = _helperRoutes[helper.userId];
      // Endpoints must have moved enough to matter (~55 m, not GPS jitter).
      final endpointsMoved = cachedRoute == null ||
          cachedRoute.isEmpty ||
          (cachedRoute.first.latitude - helper.latitude).abs() > 0.0005 ||
          (cachedRoute.first.longitude - helper.longitude).abs() > 0.0005 ||
          (cachedRoute.last.latitude - widget.myLatitude).abs() > 0.0005 ||
          (cachedRoute.last.longitude - widget.myLongitude).abs() > 0.0005;
      final rateOk = !_lastRouteFetchAt.containsKey(helper.userId) ||
          now.difference(_lastRouteFetchAt[helper.userId]!) >=
              _routeRefreshInterval;
      if (!endpointsMoved || !rateOk) continue;

      _lastRouteFetchAt[helper.userId] = now;
      final route = await RoutingService().getRoute(
        helper.latitude,
        helper.longitude,
        widget.myLatitude,
        widget.myLongitude,
      );
      if (mounted) {
        _helperRoutes[helper.userId] = route;
        updated = true;
      }
    }
    if (updated && mounted) {
      setState(() {});
      // Now that the real road path exists, widen the view to include it.
      _fitToContent();
    }
  }

  /// Zoom level that roughly fits the SOS radius circle in view.
  double get _fitZoom {
    final r = widget.sosRadiusKm;
    if (r <= 0) return 15;
    final z = 14 - (log(r) / log(2));
    return z.clamp(10.0, 16.0);
  }

  void _centerOnMe() {
    if (!mounted) return;
    _mapController.move(
        LatLng(widget.myLatitude, widget.myLongitude), _fitZoom);
  }

  @override
  void dispose() {
    _routeDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final polylines = <Polyline>[];

    if (widget.showRoute) {
      for (final helper in _validHelpers) {
        final points = _helperRoutes[helper.userId] ?? [
          LatLng(widget.myLatitude, widget.myLongitude),
          LatLng(helper.latitude, helper.longitude),
        ];
        polylines.add(
          Polyline(
            points: points,
            // The live tracking route to the person in danger is always GREEN
            // — "help is on the way". (Marker colours still reflect status.)
            color: C.success,
            strokeWidth: 5,
            borderStrokeWidth: 2.5,
            borderColor: Colors.black.withValues(alpha: 0.4),
          ),
        );
      }
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(widget.myLatitude, widget.myLongitude),
              zoom: _fitZoom,
              minZoom: 9,
              maxZoom: 18,
              onMapReady: () {
                _mapReady = true;
                if (!_didInitialFit) {
                  _didInitialFit = true;
                  _lastHelperCount = _validHelpers.length;
                  _fitToContent();
                }
              },
            ),
            children: [
              TileLayer(
                // Voyager = clear, readable streets (vs the very dim dark_all).
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                // Without this list the '{s}' placeholder resolves to empty and
                // the tile host becomes invalid → blank map. CartoDB serves a–d.
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'smartsafe.app',
                maxZoom: 19,
                keepBuffer: 6,
              ),
              // SOS broadcast radius — people inside this circle get alerted.
              if (widget.sosRadiusKm > 0)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(widget.myLatitude, widget.myLongitude),
                      radius: widget.sosRadiusKm * 1000,
                      useRadiusInMeter: true,
                      color: C.accent.withValues(alpha: 0.10),
                      borderColor: C.accent.withValues(alpha: 0.55),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              PolylineLayer(polylines: polylines),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(widget.myLatitude, widget.myLongitude),
                    width: 60,
                    height: 60,
                    builder: (context) => GestureDetector(
                      onTap: _centerOnMe,
                      // The person in danger — pulsing ring + a clear SOS badge
                      // so it's never mistaken for a helper.
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 50,
                            height: 50,
                            // The SOS victim is always RED (emergency) so it's
                            // unmistakable and never blends with helper markers.
                            child: CustomPaint(
                              painter: PulsingCirclePainter(C.red),
                            ),
                          ),
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: C.red,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: C.red.withValues(alpha: 0.6),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.sos_rounded,
                                color: Colors.white, size: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ..._validHelpers.map(
                    (helper) => Marker(
                      point: LatLng(helper.latitude, helper.longitude),
                      width: 96,
                      height: 86,
                      builder: (context) => GestureDetector(
                        onTap: () => widget.onHelperTap?.call(helper),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Name label so the victim instantly sees WHO is
                            // coming, not just a coloured dot.
                            Container(
                              constraints: const BoxConstraints(maxWidth: 94),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                helper.name.trim().isNotEmpty
                                    ? helper.name.split(' ').first
                                    : 'Helper',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _getHelperColor(helper.status),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _getHelperColor(helper.status)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  helper.name.trim().isNotEmpty
                                      ? helper.name[0].toUpperCase()
                                      : 'H',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getHelperColor(helper.status),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _statusLabel(helper.status),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Distance label floating at the middle of each helper's
                  // route, so the victim sees how far off help is at a glance.
                  ..._validHelpers.map((helper) {
                    final route = _helperRoutes[helper.userId];
                    final mid = (route != null && route.length > 2)
                        ? route[route.length ~/ 2]
                        : LatLng(
                            (widget.myLatitude + helper.latitude) / 2,
                            (widget.myLongitude + helper.longitude) / 2,
                          );
                    final km = calculateDistance(widget.myLatitude,
                        widget.myLongitude, helper.latitude, helper.longitude);
                    return Marker(
                      point: mid,
                      width: 74,
                      height: 26,
                      builder: (context) => Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: C.bg.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _getHelperColor(helper.status),
                                width: 1.2),
                          ),
                          child: Text(
                            km < 1
                                ? '${(km * 1000).round()} m'
                                : '${km.toStringAsFixed(1)} km',
                            style: TextStyle(
                              color: C.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
        // Bottom overlay: OpenStreetMap attribution sits just ABOVE the address
        // card so the watermark is never covered by the card and never covers
        // map content. SafeArea keeps it clear of the system nav bar.
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: C.bg.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(
                        color: C.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: C.bg2.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.accent.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _addressLine(
                        icon: Icons.my_location,
                        title: 'Your location',
                        address: widget.myAddress.isNotEmpty
                            ? widget.myAddress
                            : '${widget.myLatitude.toStringAsFixed(5)}, ${widget.myLongitude.toStringAsFixed(5)}',
                        color: C.accent,
                      ),
                      if (_validHelpers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Builder(builder: (_) {
                          final h = _validHelpers.first;
                          final name =
                              h.name.trim().isNotEmpty ? h.name : 'Helper';
                          return _addressLine(
                            icon: Icons.person_pin_circle,
                            title: '$name location',
                            address: h.address.isNotEmpty
                                ? h.address
                                : '${h.latitude.toStringAsFixed(5)}, ${h.longitude.toStringAsFixed(5)}',
                            color: _getHelperColor(h.status),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _addressLine({
    required IconData icon,
    required String title,
    required String address,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: C.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                address,
                style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'arriving':
        return 'Arriving';
      case 'arrived':
        return 'Arrived';
      case 'helping':
        return 'Helping';
      default:
        return 'Live';
    }
  }

  Color _getHelperColor(String status) {
    switch (status) {
      case 'arriving':
        return Colors.orange;
      case 'arrived':
        return Colors.yellow;
      case 'helping':
        return C.success;
      default:
        return C.accent;
    }
  }
}

class PulsingCirclePainter extends CustomPainter {
  final Color color;

  PulsingCirclePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.3 - (i * 0.1))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, radius + (i * 5), paint);
    }

    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.6, centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}
