import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../services/advanced_live_tracking_service.dart';
import '../services/routing_service.dart';
import '../theme/colors.dart';

class AdvancedLiveMapWidget extends StatefulWidget {
  final double myLatitude;
  final double myLongitude;
  final List<HelperInfo> helpers;
  final List<RoutePoint> myRouteHistory;
  final bool showRoute;
  final bool isOnline;
  final Function(HelperInfo)? onHelperTap;

  const AdvancedLiveMapWidget({
    Key? key,
    required this.myLatitude,
    required this.myLongitude,
    this.helpers = const [],
    this.myRouteHistory = const [],
    this.showRoute = true,
    this.isOnline = true,
    this.onHelperTap,
  }) : super(key: key);

  @override
  State<AdvancedLiveMapWidget> createState() => _AdvancedLiveMapWidgetState();
}

class _AdvancedLiveMapWidgetState extends State<AdvancedLiveMapWidget>
    with SingleTickerProviderStateMixin {
  late MapController _mapController;
  late AnimationController _pulseController;
  final Map<String, List<LatLng>> _helperRoutes = {};

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    Future.delayed(Duration.zero, () {
      if (mounted) {
        _mapController.move(
          LatLng(widget.myLatitude, widget.myLongitude),
          15,
        );
      }
    });
    _updateRoutes();
  }

  @override
  void didUpdateWidget(covariant AdvancedLiveMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateRoutes();
  }

  Future<void> _updateRoutes() async {
    bool updated = false;
    for (final helper in widget.helpers) {
      final cachedRoute = _helperRoutes[helper.userId];
      if (cachedRoute == null ||
          cachedRoute.isEmpty ||
          (cachedRoute.first.latitude - helper.latitude).abs() > 0.0001 ||
          (cachedRoute.first.longitude - helper.longitude).abs() > 0.0001 ||
          (cachedRoute.last.latitude - widget.myLatitude).abs() > 0.0001 ||
          (cachedRoute.last.longitude - widget.myLongitude).abs() > 0.0001) {
        
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
    }
    if (updated && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Polyline> polylines = [];

    // User route history
    if (widget.showRoute && widget.myRouteHistory.isNotEmpty) {
      polylines.add(
        Polyline(
          points: widget.myRouteHistory
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(),
          color: C.accent.withValues(alpha: 0.6),
          strokeWidth: 3,
          borderStrokeWidth: 1,
          borderColor: Colors.white.withValues(alpha: 0.7),
        ),
      );
    }

    // Helper routes to user
    if (widget.showRoute) {
      for (var helper in widget.helpers) {
        final points = _helperRoutes[helper.userId] ?? [
          LatLng(widget.myLatitude, widget.myLongitude),
          LatLng(helper.latitude, helper.longitude),
        ];
        polylines.add(
          Polyline(
            points: points,
            color: _getHelperColor(helper.status),
            strokeWidth: 5,
            borderStrokeWidth: 2.5,
            borderColor: Colors.black.withValues(alpha: 0.4),
          ),
        );
      }
    }

    return Stack(
      children: [
        // Map
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(widget.myLatitude, widget.myLongitude),
              zoom: 15,
              minZoom: 12,
              maxZoom: 18,
            ),
            children: [
              // Base layer - OpenStreetMap
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'smartsafe.app',
                maxZoom: 19,
                keepBuffer: 6,
                tileProvider: NetworkTileProvider(),
              ),

              // Polylines (routes)
              PolylineLayer(polylines: polylines),

              // Markers
              MarkerLayer(
                markers: [
                  // User marker
                  Marker(
                    point: LatLng(widget.myLatitude, widget.myLongitude),
                    width: 70,
                    height: 70,
                    builder: (context) => GestureDetector(
                      onTap: () => _mapController.move(
                        LatLng(widget.myLatitude, widget.myLongitude),
                        15,
                      ),
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: 0.8 + (_pulseController.value * 0.4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Pulsing outer circle
                                Container(
                                  width: 50 + (_pulseController.value * 20),
                                  height: 50 + (_pulseController.value * 20),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: C.red.withValues(alpha:
                                      0.3 - (_pulseController.value * 0.2),
                                    ),
                                    border: Border.all(
                                      color: C.red.withValues(alpha:
                                        0.5 - (_pulseController.value * 0.3),
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                // Inner marker — the person in SOS is always RED.
                                Transform.translate(
                                  offset: const Offset(
                                    0,
                                    -15,
                                  ),
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: C.red,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: C.red.withValues(alpha: 0.6),
                                          blurRadius: 15,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Helper markers
                  ...widget.helpers.map(
                    (helper) => Marker(
                      point: LatLng(helper.latitude, helper.longitude),
                      width: 60,
                      height: 60,
                      builder: (context) => GestureDetector(
                        onTap: () => widget.onHelperTap?.call(helper),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Helper marker
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _getHelperColor(
                                  helper.status,
                                ),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _getHelperColor(
                                      helper.status,
                                    ).withValues(alpha: 0.5),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Text(
                                      helper.name.isNotEmpty
                                          ? helper.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  // Offline indicator
                                  if (!helper.isOnline)
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.grey,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.signal_cellular_off,
                                          size: 8,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Distance tag
                            Container(
                              margin: const EdgeInsets.only(
                                top: 4,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getHelperColor(
                                  helper.status,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${helper.distanceToUser.toStringAsFixed(1)}km',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Attribution
              const SimpleAttributionWidget(
                source: Text(
                  '© OpenStreetMap contributors',
                ),
              ),
            ],
          ),
        ),

        // Top status bar
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: C.bg.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isOnline
                    ? C.success.withValues(alpha: 0.5)
                    : Colors.orange.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                )
              ],
            ),
            child: Row(
              children: [
                // Status indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isOnline ? C.success : Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isOnline
                      ? 'LIVE • Broadcasting'
                      : 'OFFLINE • Buffering',
                  style: TextStyle(
                    color: widget.isOnline ? C.success : Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                // Helper count badge
                if (widget.helpers.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: C.warning,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.helpers.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.directions_car_rounded,
                            color: Colors.white, size: 11),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bottom info panel
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: C.bg2.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: C.accent.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _infoChip(
                  icon: Icons.location_on_rounded,
                  label: 'Latitude',
                  value: widget.myLatitude.toStringAsFixed(4),
                ),
                _infoChip(
                  icon: Icons.explore_rounded,
                  label: 'Longitude',
                  value: widget.myLongitude.toStringAsFixed(4),
                ),
                if (widget.helpers.isNotEmpty)
                  _infoChip(
                    icon: Icons.groups_rounded,
                    label: 'Helpers',
                    value: widget.helpers.length.toString(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: C.accent, size: 16),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: C.textMuted,
            fontSize: 9,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: C.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
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
