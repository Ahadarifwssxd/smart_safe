import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A computed route: the path plus its real distance & driving duration.
class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });
}

class RoutingService {
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;
  RoutingService._internal();

  /// Like [getRoute] but also returns real distance (km) + duration (min)
  /// from OSRM. Falls back to a straight line + great-circle estimate.
  Future<RouteResult> getRouteDetails(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$startLon,$startLat;$endLon,$endLat?geometries=geojson&overview=full',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'SmartSafeApp/1.0'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final coordinates = route['geometry']['coordinates'] as List;
          final points = coordinates
              .map((c) => LatLng(
                  (c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          final meters = (route['distance'] as num?)?.toDouble() ?? 0;
          final seconds = (route['duration'] as num?)?.toDouble() ?? 0;
          return RouteResult(
            points: points,
            distanceKm: meters / 1000,
            durationMin: (seconds / 60).round(),
          );
        }
      }
    } catch (e) {
      print('Error fetching OSRM route details: $e');
    }

    // Fallback: straight line + great-circle distance, ~30 km/h estimate.
    final km = const Distance().as(
        LengthUnit.Kilometer, LatLng(startLat, startLon), LatLng(endLat, endLon));
    return RouteResult(
      points: [LatLng(startLat, startLon), LatLng(endLat, endLon)],
      distanceKm: km,
      durationMin: (km / 30 * 60).round(),
    );
  }

  /// Returns up to 3 REAL alternative driving routes from OSRM (each with its
  /// own geometry, distance & duration) so the caller can score them and let
  /// the user pick Safest / Balanced / Fastest. Falls back to a single
  /// straight-line estimate if the service is unreachable.
  Future<List<RouteResult>> getAlternatives(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$startLon,$startLat;$endLon,$endLat'
        '?alternatives=3&geometries=geojson&overview=full',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'SmartSafeApp/1.0'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] is List &&
            (data['routes'] as List).isNotEmpty) {
          final out = <RouteResult>[];
          for (final route in (data['routes'] as List)) {
            final coordinates = route['geometry']['coordinates'] as List;
            final points = coordinates
                .map((c) =>
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                .toList();
            if (points.length < 2) continue;
            final meters = (route['distance'] as num?)?.toDouble() ?? 0;
            final seconds = (route['duration'] as num?)?.toDouble() ?? 0;
            out.add(RouteResult(
              points: points,
              distanceKm: meters / 1000,
              durationMin: (seconds / 60).round(),
            ));
          }
          if (out.isNotEmpty) return out;
        }
      }
    } catch (e) {
      print('Error fetching OSRM alternatives: $e');
    }

    // Fallback: one straight line so the UI still shows something.
    final km = const Distance().as(
        LengthUnit.Kilometer, LatLng(startLat, startLon), LatLng(endLat, endLon));
    return [
      RouteResult(
        points: [LatLng(startLat, startLon), LatLng(endLat, endLon)],
        distanceKm: km,
        durationMin: (km / 30 * 60).round(),
      ),
    ];
  }

  // Simple memory cache: key = "startLat,startLon->endLat,endLon"
  final Map<String, List<LatLng>> _routeCache = {};

  Future<List<LatLng>> getRoute(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) async {
    // Generate cache key with 4 decimal places of accuracy (~11 meters) to throttle updates
    final key = "${startLat.toStringAsFixed(4)},${startLon.toStringAsFixed(4)}->${endLat.toStringAsFixed(4)},${endLon.toStringAsFixed(4)}";

    if (_routeCache.containsKey(key)) {
      return _routeCache[key]!;
    }

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$startLon,$startLat;$endLon,$endLat?geometries=geojson',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'SmartSafeApp/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry'];
          final coordinates = geometry['coordinates'] as List;
          
          final List<LatLng> points = coordinates.map((coord) {
            final double lon = (coord[0] as num).toDouble();
            final double lat = (coord[1] as num).toDouble();
            return LatLng(lat, lon);
          }).toList();

          _routeCache[key] = points;
          return points;
        }
      }
    } catch (e) {
      print('Error fetching OSRM route: $e');
    }

    // Fallback: Return direct straight line if API fails
    return [LatLng(startLat, startLon), LatLng(endLat, endLon)];
  }
}
