import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../services/location_service.dart';
import '../services/nearby_places_service.dart';

class NearestHospitalsPage extends StatefulWidget {
  const NearestHospitalsPage({super.key});
  @override State<NearestHospitalsPage> createState() => _NearestHospitalsPageState();
}

class _NearestHospitalsPageState extends State<NearestHospitalsPage> {
  String _filter = 'All';
  final _filters = ['All', 'Hospital', 'Police', 'Rescue', 'Pharmacy'];
  double? _userLat;
  double? _userLon;
  String _address = 'Saddar, Karachi';
  bool _loadingLocation = false;

  // REAL nearby facilities fetched from OpenStreetMap for the user's GPS.
  List<NearbyPlace> _live = [];
  bool _loadingPlaces = false;

  // Non-null when the last attempt failed (permission denied / GPS off /
  // location error). Drives the on-brand error state with a Retry button.
  String? _error;
  // True once at least one fetch has completed, so we can tell "still loading"
  // apart from "loaded but zero results" (the friendly empty state).
  bool _hasFetched = false;

  @override
  void initState() {
    super.initState();
    _requestAndFetchLocation();
  }

  Future<void> _requestAndFetchLocation() async {
    if (!mounted) return;
    setState(() {
      _loadingLocation = true;
      _error = null;
    });
    final permErr = await LocationService.instance.requestPermission();
    if (permErr != null) {
      debugPrint('Location permission denied: $permErr');
      if (mounted) {
        setState(() {
          _loadingLocation = false;
          _error = 'Location access is off. Enable location permission to '
              'find help near you.';
        });
      }
      return;
    }
    try {
      final loc = await LocationService.instance.getCurrentLocation();
      if (loc != null) {
        if (mounted) {
          setState(() {
            _userLat = loc.latitude;
            _userLon = loc.longitude;
          });
        }
        // Start the nearby search IMMEDIATELY; the place-name label resolves in
        // parallel (it no longer blocks the results from loading).
        unawaited(_fetchPlaceName(loc.latitude, loc.longitude));
        await _fetchNearby(loc.latitude, loc.longitude);
      } else if (mounted) {
        setState(() => _error =
            'Could not get your GPS location. Check that location is on and '
            'try again.');
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        setState(() => _error =
            'Something went wrong getting your location. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingLocation = false);
      }
    }
  }

  Future<void> _fetchPlaceName(double lat, double lon) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json&accept-language=en');
      final response =
          await http.get(url, headers: {'User-Agent': 'SmartSafeApp/1.0'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String placeName = '';
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final parts = [
            address['suburb'] ?? address['neighbourhood'] ?? address['village'] ?? address['quarter'] ?? address['subdivision'],
            address['city'] ?? address['town'] ?? address['county'],
          ].whereType<String>().toList();
          if (parts.isNotEmpty) {
            placeName = parts.join(', ');
          }
        }
        if (placeName.isEmpty) {
          placeName = data['display_name'] ?? '';
        }
        if (placeName.isNotEmpty && mounted) {
          setState(() {
            _address = placeName;
          });
        }
      }
    } catch (_) {}
  }

  /// Fetches REAL nearby facilities from OpenStreetMap for this GPS fix.
  Future<void> _fetchNearby(double lat, double lon) async {
    if (!mounted) return;
    setState(() => _loadingPlaces = true);
    try {
      final results = await NearbyPlacesService.instance.fetch(lat, lon);
      if (mounted) setState(() => _live = results);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _loadingPlaces = false;
          _hasFetched = true;
        });
      }
    }
  }

  /// Maps a real place to the UI shape, with the right icon/colour and a
  /// sensible default emergency number when OSM has no phone for it.
  Map<String, dynamic> _placeToMap(NearbyPlace p) {
    IconData icon;
    Color color;
    String defaultPhone;
    switch (p.category) {
      case 'Police':
        icon = Icons.local_police_rounded;
        color = C.accent;
        defaultPhone = '15';
        break;
      case 'Rescue':
        icon = Icons.fire_truck_rounded;
        color = C.warning;
        defaultPhone = '1122';
        break;
      case 'Pharmacy':
        icon = Icons.local_pharmacy_rounded;
        color = C.success;
        defaultPhone = '';
        break;
      default: // Hospital
        icon = Icons.local_hospital_rounded;
        color = C.accent;
        defaultPhone = '1122';
    }
    final hasPhone = p.phone != null && p.phone!.trim().isNotEmpty;
    return {
      'name': p.name,
      'type': p.category,
      'lat': p.lat,
      'lng': p.lon,
      'phone': hasPhone ? p.phone! : defaultPhone,
      'hasRealPhone': hasPhone,
      'color': color,
      'icon': icon,
      'address': p.address,
    };
  }

  /// ONLY real, location-accurate results from OpenStreetMap. We deliberately
  /// do NOT fall back to a hardcoded other-city list — showing the wrong
  /// hospitals/police in an emergency is dangerous. When the live fetch returns
  /// nothing, the UI shows a "retry" state instead (the real national emergency
  /// numbers in the quick-call row always stay available).
  List<Map<String, dynamic>> get _allItems =>
      _live.map(_placeToMap).toList();

  List<Map<String, dynamic>> get _filtered {
    final base = _allItems;
    List<Map<String, dynamic>> list = _filter == 'All'
        ? List.from(base)
        : base.where((p) => p['type'] == _filter).toList();

    if (_userLat != null && _userLon != null) {
      final List<Map<String, dynamic>> updatedList = [];
      for (var p in list) {
        final double distInMeters = Geolocator.distanceBetween(
          _userLat!,
          _userLon!,
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
        );
        final distInKm = distInMeters / 1000;
        final durationMin = (distInKm / 5 * 60).round();

        final item = Map<String, dynamic>.from(p);
        item['distVal'] = distInKm;
        item['dist'] = '${distInKm.toStringAsFixed(1)} km';
        item['time'] = durationMin <= 0 ? '1 min' : '$durationMin min';
        updatedList.add(item);
      }
      updatedList.sort((a, b) =>
          (a['distVal'] as double).compareTo(b['distVal'] as double));
      return updatedList;
    }

    return list;
  }

  Future<void> _makeCall(String number) async {
    // Place a REAL direct call from the device SIM.
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    try {
      await FlutterPhoneDirectCaller.callNumber(clean);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: C.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text('Could not place the call to $number',
              style: TextStyle(color: C.textPrimary)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            if (Navigator.canPop(context)) ...[
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
              ),
              const SizedBox(width: 12),
            ],
            DynText('nearest_hospitals', 'title', 'Nearest Help', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          ]),
          GestureDetector(
            onTap: _requestAndFetchLocation,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              BlinkDot(color: _userLat != null ? C.success : C.accent),
              const SizedBox(width: 6),
              Text(_userLat != null ? 'Live GPS' : 'No GPS', style: TextStyle(color: _userLat != null ? C.success : C.accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 4),
        Text('$_address — ${_loadingLocation ? "Updating..." : "Updated just now"}', style: TextStyle(color: C.textMuted, fontSize: 12)),
        const SizedBox(height: 16),

        // Quick call row
        Row(children: [
          _QuickCall(label: '1122', sub: 'Ambulance', color: C.accent, onTap: () => _makeCall('1122')),
          const SizedBox(width: 8),
          _QuickCall(label: '15', sub: 'Police', color: C.accent, onTap: () => _makeCall('15')),
          const SizedBox(width: 8),
          _QuickCall(label: '115', sub: 'Edhi', color: C.success, onTap: () => _makeCall('115')),
          const SizedBox(width: 8),
          _QuickCall(label: '1099', sub: 'Madadgar', color: C.accent, onTap: () => _makeCall('1099')),
        ]),

        const SizedBox(height: 16),

        // Filter chips
        SizedBox(height: 34, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final f = _filters[i]; final sel = f == _filter;
            return GestureDetector(onTap: () => setState(() => _filter = f),
              child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: sel ? C.accent : C.bg2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? C.accent : C.textDim)),
                child: Center(child: Text(f,
                  style: TextStyle(color: sel ? Colors.white : C.textMuted, fontSize: 12,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.normal)))));
          },
        )),
        const SizedBox(height: 16),
      ])),

      // List / loading / empty / error — exactly one at a time.
      Expanded(child: _buildBody()),

      const SizedBox(height: 12),
    ])),
  );

  /// Mutually-exclusive content states: LOADING xor ERROR xor EMPTY xor LIST.
  /// We only fall back to error/empty once nothing is in-flight and we have no
  /// cached results, so the area never sits on a bare spinner in a black void.
  Widget _buildBody() {
    final busy = _loadingLocation || _loadingPlaces;

    // LOADING — first fetch (or a retry with nothing to show yet). Also covers
    // the brief window before the very first fetch has completed, so we never
    // flash an empty state prematurely.
    if (_live.isEmpty && (busy || (!_hasFetched && _error == null))) {
      return _buildLoading();
    }

    // ERROR — permission denied / GPS off / location error, no cached results.
    if (_error != null && _live.isEmpty) return _buildError();

    final items = _filtered;

    // EMPTY — loaded, but nothing matches (either nothing nearby, or the
    // selected filter has no matches). Never an endless spinner.
    if (items.isEmpty) return _buildEmpty();

    // LIST — real OpenStreetMap results.
    return _buildList(items);
  }

  Widget _buildLoading() => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SmartSafeLoader(dotSize: 8),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _loadingLocation && _userLat == null
                    ? 'Getting your location…'
                    : 'Finding nearby help…',
                style: TextStyle(
                    color: C.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          for (int i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: _ShimmerCard(),
            ),
        ],
      );

  Widget _buildError() => _StateMessage(
        icon: Icons.location_off_rounded,
        title: 'Location unavailable',
        message: _error ?? 'We couldn\'t find nearby help. Please try again.',
        actionLabel: 'Retry',
        onAction: _requestAndFetchLocation,
      );

  Widget _buildEmpty() {
    final filtered = _filter != 'All' && _live.isNotEmpty;
    return _StateMessage(
      icon: filtered ? Icons.filter_alt_off_rounded : Icons.search_off_rounded,
      title: filtered ? 'No $_filter found nearby' : 'No facilities found nearby',
      message: filtered
          ? 'Nothing in this category within range. Try another filter or search again.'
          : 'No results within range yet. Check your connection, then search again.',
      actionLabel: 'Search again',
      onAction: _requestAndFetchLocation,
      secondaryLabel: filtered ? 'Show all' : null,
      onSecondary: filtered ? () => setState(() => _filter = 'All') : null,
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items) => RefreshIndicator(
        color: C.accent,
        backgroundColor: C.bg2,
        onRefresh: _requestAndFetchLocation,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final p = items[i];
            final color = p['color'] as Color;
            final phone = p['phone'] as String;
            return SlideUpFade(
              delay: Duration(milliseconds: i * 50),
              child: DCard(
                  child: Row(children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(p['icon'] as IconData, color: color, size: 22)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(p['name'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: C.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      Text(p['address'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: C.textMuted, fontSize: 11)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.directions_walk_rounded,
                            color: C.accent, size: 12),
                        const SizedBox(width: 3),
                        Text('${p['dist']} · ${p['time']}',
                            style: TextStyle(
                                color: C.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: C.success)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(p['type'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: C.success, fontSize: 10)),
                        ),
                      ]),
                    ])),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _makeCall(phone),
                  child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.call_rounded, color: color, size: 18)),
                ),
              ])),
            );
          },
        ),
      );
}

/// On-brand shimmer placeholder that mirrors a facility card's layout, shown
/// while the real OpenStreetMap results are being fetched.
class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();
  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: C.textDim.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(6),
        ),
      );

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) =>
              Opacity(opacity: 0.4 + _c.value * 0.5, child: child),
          child: DCard(
            child: Row(children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: C.textDim.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(12))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _bar(double.infinity, 12),
                    const SizedBox(height: 8),
                    _bar(140, 10),
                    const SizedBox(height: 8),
                    _bar(90, 10),
                  ])),
              const SizedBox(width: 8),
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: C.textDim.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(10))),
            ]),
          ),
        ),
      );
}

/// Reusable, responsive centered state (empty / error): icon + title + message
/// + a primary Retry/Search button and an optional secondary text action.
/// Wrapped in a scroll view so it never overflows on small Android screens.
class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: C.accent.withValues(alpha: 0.12),
                        border: Border.all(
                            color: C.accent.withValues(alpha: 0.25)),
                      ),
                      child: Icon(icon, size: 40, color: C.accent),
                    ),
                    const SizedBox(height: 20),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: C.textMuted,
                            fontSize: 12.5,
                            height: 1.4)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: onAction,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: C.accent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: C.accent.withValues(alpha: 0.28),
                                blurRadius: 18,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(actionLabel,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                    if (secondaryLabel != null) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: onSecondary,
                        behavior: HitTestBehavior.opaque,
                        child: Text(secondaryLabel!,
                            style: TextStyle(
                                color: C.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _QuickCall extends StatelessWidget {
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  const _QuickCall({required this.label, required this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(
    onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .4))),
      child: Column(children: [
        Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        Text(sub, style: TextStyle(color: C.textMuted, fontSize: 9)),
      ])),
  ));
}