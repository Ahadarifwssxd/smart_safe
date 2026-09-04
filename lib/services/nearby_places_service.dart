import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// A real-world emergency facility near the user (from OpenStreetMap).
class NearbyPlace {
  final String name;
  final String category; // Hospital | Police | Rescue | Pharmacy
  final double lat;
  final double lon;
  final double distanceKm;
  final String? phone; // null when OSM has no number → caller uses the default
  final String address;

  const NearbyPlace({
    required this.name,
    required this.category,
    required this.lat,
    required this.lon,
    required this.distanceKm,
    required this.address,
    this.phone,
  });

  /// Rough walking time at ~5 km/h.
  int get walkMin {
    final m = (distanceKm / 5 * 60).round();
    return m <= 0 ? 1 : m;
  }
}

/// Finds REAL nearby emergency facilities around the user's GPS using the
/// OpenStreetMap Overpass API — no hardcoded list. Hospitals, clinics, police
/// stations, fire/rescue stations and pharmacies within [radiusMeters].
class NearbyPlacesService {
  static final NearbyPlacesService instance = NearbyPlacesService._();
  NearbyPlacesService._();

  // A couple of mirrors — if one is busy we try the next.
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  String _categoryFor(String amenity) {
    switch (amenity) {
      case 'hospital':
      case 'clinic':
      case 'doctors':
        return 'Hospital';
      case 'police':
        return 'Police';
      case 'fire_station':
        return 'Rescue';
      case 'pharmacy':
        return 'Pharmacy';
      default:
        return 'Hospital';
    }
  }

  Future<List<NearbyPlace>> fetch(
    double lat,
    double lon, {
    int radiusMeters = 6000,
    int limit = 40,
  }) async {
    // A wide-enough radius so dense-but-sparsely-mapped areas still return real
    // NAMED facilities (many OSM points in Pakistan have no name and are skipped).
    final query = '[out:json][timeout:15];'
        '('
        'node["amenity"~"hospital|clinic|doctors|police|fire_station|pharmacy"](around:$radiusMeters,$lat,$lon);'
        'way["amenity"~"hospital|clinic|doctors|police|fire_station|pharmacy"](around:$radiusMeters,$lat,$lon);'
        ');'
        'out center $limit;';

    // RACE both mirrors at once — speed comes from using whichever answers
    // first, WITHOUT shrinking the radius. Prefer a NON-EMPTY result: if one
    // mirror returns empty, wait for the other before giving up.
    final completer = Completer<List<NearbyPlace>>();
    var pending = _endpoints.length;
    List<NearbyPlace>? fallback;
    for (final endpoint in _endpoints) {
      _fetchFrom(endpoint, query, lat, lon).then((result) {
        if (result != null && result.isNotEmpty && !completer.isCompleted) {
          completer.complete(result);
        } else if (result != null) {
          fallback = result; // valid but empty — keep as a last resort
        }
      }).whenComplete(() {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(fallback ?? <NearbyPlace>[]);
        }
      });
    }
    return completer.future;
  }

  /// Queries ONE Overpass mirror; returns parsed places, or null on failure.
  Future<List<NearbyPlace>?> _fetchFrom(
      String endpoint, String query, double lat, double lon) async {
    try {
      final res = await http
          .post(Uri.parse(endpoint),
              body: {'data': query},
              headers: {'User-Agent': 'SmartSafeApp/1.0'})
          .timeout(const Duration(seconds: 16));
      if (res.statusCode != 200) return null;

      final data = json.decode(res.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List?) ?? [];
      final places = <NearbyPlace>[];

      for (final e in elements) {
        final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};
        final name = tags['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue; // skip unnamed nodes

        // Node has lat/lon; way has center.{lat,lon}.
        final plat = (e['lat'] ?? e['center']?['lat']) as num?;
        final plon = (e['lon'] ?? e['center']?['lon']) as num?;
        if (plat == null || plon == null) continue;

        final amenity = tags['amenity']?.toString() ?? '';
        final phone = (tags['phone'] ??
                tags['contact:phone'] ??
                tags['emergency:phone'])
            ?.toString();

        final addr = [
          tags['addr:street'],
          tags['addr:suburb'] ?? tags['addr:neighbourhood'],
          tags['addr:city'],
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

        final distKm = Geolocator.distanceBetween(
                lat, lon, plat.toDouble(), plon.toDouble()) /
            1000;

        places.add(NearbyPlace(
          name: name,
          category: _categoryFor(amenity),
          lat: plat.toDouble(),
          lon: plon.toDouble(),
          distanceKm: distKm,
          address: addr.isNotEmpty ? addr : 'Near you',
          phone: (phone != null && phone.trim().isNotEmpty) ? phone : null,
        ));
      }

      // De-duplicate by name+category (ways + nodes can overlap), nearest wins.
      final seen = <String>{};
      places.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      final unique = <NearbyPlace>[];
      for (final p in places) {
        final key = '${p.category}|${p.name.toLowerCase()}';
        if (seen.add(key)) unique.add(p);
      }
      return unique;
    } catch (_) {
      return null;
    }
  }
}
