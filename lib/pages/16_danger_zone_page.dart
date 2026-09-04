import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart' as geo;
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../services/location_service.dart';
import '../services/app_firestore_service.dart';

class DangerZonePage extends StatefulWidget {
  const DangerZonePage({super.key});

  @override
  State<DangerZonePage> createState() => _DangerZonePageState();
}

class _DangerZonePageState extends State<DangerZonePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _heatCtrl;
  String _selectedCategory = 'All';
  /// Time filter for the reports list: 'All' | 'Today' | 'Week'.
  String _timeFilter = 'All';
  bool _showReportForm = false;
  String _reportType = 'Unsafe Area';
  final _reportCtrl = TextEditingController();   // incident description
  final _searchCtrl = TextEditingController();   // location search
  final _customTypeCtrl = TextEditingController();

  List<dynamic> _locationSuggestions = [];
  bool _isSearchingLocation = false;
  String _locationAddress = '';   // human-readable address of selected point
  bool _showPreviousLocations = false; // show previously reported locations

  LatLng? _userLocation;
  LatLng? _selectedLocation;
  final MapController _mapController = MapController();
  Timer? _debounce;
  Timer? _searchDebounce;

  final List<String> _categories = [
    'All',
    'Theft',
    'Harassment',
    'Dark Area',
    'Accident',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _heatCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _initLocation();
  }

  Future<void> _initLocation() async {
    await LocationService.instance.requestPermission();
    final loc = await LocationService.instance.getCurrentLocation();

    if (mounted) {
      setState(() {
        if (loc != null) {
          _userLocation = LatLng(loc.latitude, loc.longitude);
          _selectedLocation = _userLocation;
        } else {
          _userLocation = const LatLng(33.6844, 73.0479);
          _selectedLocation = _userLocation;
        }
      });
      // Move map then reverse-geocode the starting point
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(_userLocation!, 15);
        _reverseGeocode(_userLocation!);
      });
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    if (!mounted) return;
    final coords =
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    // Show the coordinates IMMEDIATELY so the field is never stuck on a long
    // "Fetching address…". The human-readable address then replaces them the
    // moment it resolves. Each attempt is time-boxed so a slow/offline geocoder
    // can't hang the UI.
    setState(() {
      _selectedLocation = point;
      _locationAddress = coords;
    });

    // 1) Native platform geocoder first — it's fast and has no public rate
    //    limit (unlike Nominatim), so it usually answers in well under a second.
    try {
      final marks = await geo
          .placemarkFromCoordinates(point.latitude, point.longitude)
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      if (marks.isNotEmpty) {
        final m = marks.first;
        final parts = [
          m.subLocality,
          m.locality,
          m.subAdministrativeArea,
          m.administrativeArea,
        ].where((p) => p != null && p.trim().isNotEmpty).toList();
        if (parts.isNotEmpty) {
          setState(() => _locationAddress = parts.join(', '));
          return;
        }
      }
    } catch (_) {
      // fall through to the network geocoder
    }

    // 2) Fallback: Nominatim, but time-boxed so it can't hang; coordinates stay
    //    on screen if it fails.
    try {
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json&addressdetails=1'),
        headers: {'Accept-Language': 'en', 'User-Agent': 'SmartSafe/1.0'},
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        final name = data['display_name'];
        if (name != null && name.toString().trim().isNotEmpty) {
          setState(() => _locationAddress = name);
        }
      }
    } catch (_) {
      // keep the coordinates already shown
    }
  }

  // Debounces the location search so we wait until the user pauses typing —
  // Nominatim rate-limits to ~1 request/second, so firing on every keystroke
  // gets throttled and returns nothing.
  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().isEmpty) {
      _searchLocation(q);
      return;
    }
    _searchDebounce =
        Timer(const Duration(milliseconds: 450), () => _searchLocation(q));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _heatCtrl.dispose();
    _reportCtrl.dispose();
    _searchCtrl.dispose();
    _customTypeCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _locationSuggestions = [];
        _showPreviousLocations = true;
      });
      return;
    }
    setState(() => _showPreviousLocations = false);
    setState(() => _isSearchingLocation = true);
    try {
      // Nominatim REQUIRES a User-Agent — without it the request is blocked and
      // no suggestions come back (which is why search looked "broken"). The
      // country filter is dropped so places outside Pakistan also resolve.
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=6&addressdetails=1'),
        headers: const {
          'Accept-Language': 'en',
          'User-Agent': 'SmartSafe/1.0 (safety app)',
        },
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _locationSuggestions = json.decode(res.body) as List<dynamic>;
        });
      }
    } catch (e) {
      debugPrint('Error searching: $e');
    } finally {
      if (mounted) setState(() => _isSearchingLocation = false);
    }
  }

  void _submitReport() async {
    if (_locationAddress.isEmpty || _locationAddress == 'Fetching address...') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please wait — fetching location address...')));
      return;
    }

    String finalType = _reportType == 'Other'
        ? (_customTypeCtrl.text.isNotEmpty ? _customTypeCtrl.text : 'Other')
        : _reportType;

    // Build location string: address + GPS coords
    String locationString = _locationAddress;
    if (_selectedLocation != null) {
      locationString += ' (${_selectedLocation!.latitude.toStringAsFixed(4)}, ${_selectedLocation!.longitude.toStringAsFixed(4)})';
    }

    // Optional extra description from user
    final description = _reportCtrl.text.isNotEmpty
        ? '${_reportCtrl.text} — $locationString'
        : locationString;

    try {
      await AppFirestoreService.instance.addDangerZoneReport(
        incidentType: finalType,
        description: description,
        location: locationString,
        // Store the REAL coordinates so the map + dashboard can plot this report
        // exactly, instead of trying to parse them back out of the address text.
        latitude: _selectedLocation?.latitude,
        longitude: _selectedLocation?.longitude,
      );

      if (mounted) {
        setState(() {
          _showReportForm = false;
          _reportCtrl.clear();
          _searchCtrl.clear();
          _customTypeCtrl.clear();
          _locationSuggestions = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Report sent for review — it appears once a moderator approves it.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to submit report: $e')));
      }
    }
  }

  /// When a report was filed. Prefers the real server timestamp; falls back to
  /// the legacy 'time' string on older documents.
  DateTime? _reportTime(Map<String, dynamic> r) {
    final ts = r['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return DateTime.tryParse(r['time']?.toString() ?? '');
  }

  List<Map<String, dynamic>> _filterReports(List<Map<String, dynamic>> reports) {
    var out = reports;

    // Category filter (Theft / Harassment / …)
    if (_selectedCategory != 'All') {
      out = out
          .where((r) =>
              r['incidentType'] == _selectedCategory ||
              (_selectedCategory == 'Other' &&
                  !_categories.contains(r['incidentType'])))
          .toList();
    }

    // Time filter — these used to be decorative labels that did nothing.
    if (_timeFilter != 'All') {
      final now = DateTime.now();
      out = out.where((r) {
        final t = _reportTime(r);
        if (t == null) return false;
        if (_timeFilter == 'Today') {
          return t.year == now.year && t.month == now.month && t.day == now.day;
        }
        // 'Week' — the last 7 days.
        return now.difference(t).inDays < 7;
      }).toList();
    }
    return out;
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'Harassment':
        return AppColors.accent;
      case 'Theft':
        return AppColors.warning;
      case 'Dark Area':
        return C.textMuted;
      case 'Accident':
        return C.red;
      default:
        return AppColors.accent;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Harassment':
        return Icons.person_off_rounded;
      case 'Theft':
        return Icons.no_backpack_rounded;
      case 'Dark Area':
        return Icons.nightlight_round;
      case 'Accident':
        return Icons.car_crash_rounded;
      default:
        return Icons.warning_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: AppFirestoreService.instance.watchApprovedDangerZones(),
        builder: (context, snapshot) {
          final reports = snapshot.data ?? [];
          final filteredReports = _filterReports(reports);

          return Stack(
            children: [
              RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
              SafeArea(
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: SlideUpFade(
                        child: Row(
                          children: [
                            if (Navigator.canPop(context)) ...[
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DynText('danger_zone', 'title', 'Danger Zones',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: C.textPrimary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      )),
                                  Text('Community-reported unsafe areas',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setState(
                                  () => _showReportForm = !_showReportForm),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.accent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.add_location_alt_rounded,
                                        color: AppColors.accent, size: 15),
                                    const SizedBox(width: 5),
                                    Text('Report',
                                        style: TextStyle(
                                          color: AppColors.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Category filters
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SlideUpFade(
                        delay: const Duration(milliseconds: 80),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _categories.map((c) {
                              final sel = c == _selectedCategory;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedCategory = c),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? AppColors.accent.withValues(alpha: 0.12)
                                        : AppColors.bg2,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: sel
                                          ? AppColors.accent.withValues(alpha: 0.4)
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Text(c,
                                      style: TextStyle(
                                        color: sel
                                            ? AppColors.accent
                                            : AppColors.textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      )),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Scrollable body — report form + map + stats + list
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Report form
                            if (_showReportForm)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: SlideUpFade(
                                  child: DCard(
                                    child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Report Unsafe Area',
                                    style: TextStyle(
                                        color: C.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                const SizedBox(height: 12),
                                // Type chips
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    'Unsafe Area',
                                    'Harassment',
                                    'Theft',
                                    'Dark Area',
                                    'Accident',
                                    'Other',
                                  ].map((t) {
                                    final sel = t == _reportType;
                                    return GestureDetector(
                                      onTap: () =>
                                          setState(() => _reportType = t),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: sel
                                              ? AppColors.accent
                                                  .withValues(alpha: 0.15)
                                              : AppColors.bg3,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: sel
                                                ? AppColors.accent
                                                    .withValues(alpha: 0.4)
                                                : AppColors.border,
                                          ),
                                        ),
                                        child: Text(t,
                                            style: TextStyle(
                                              color: sel
                                                  ? AppColors.accent
                                                  : AppColors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            )),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                if (_reportType == 'Other') ...[
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _customTypeCtrl,
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Enter custom incident type...',
                                      hintStyle: TextStyle(color: AppColors.textMuted),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                // Location search field
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.bg3,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(left: 10),
                                        child: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: _searchCtrl,
                                          onChanged: _onSearchChanged,
                                          onTap: () {
                                            if (_searchCtrl.text.isEmpty) {
                                              setState(() => _showPreviousLocations = true);
                                            }
                                          },
                                          style: TextStyle(color: C.textPrimary, fontSize: 13),
                                          decoration: InputDecoration(
                                            hintText: 'Search location (e.g. Golimar, Karachi)...',
                                            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          ),
                                        ),
                                      ),
                                      if (_isSearchingLocation)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 10),
                                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                        ),
                                    ],
                                  ),
                                ),
                                // Suggestions dropdown
                                if (_locationSuggestions.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    constraints: const BoxConstraints(maxHeight: 160),
                                    decoration: BoxDecoration(
                                      color: AppColors.bg3,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: _locationSuggestions.length,
                                      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                                      itemBuilder: (context, index) {
                                        final s = _locationSuggestions[index];
                                        final name = s['display_name'] ?? '';
                                        return InkWell(
                                          onTap: () {
                                            final lat = double.tryParse(s['lat']?.toString() ?? '');
                                            final lon = double.tryParse(s['lon']?.toString() ?? '');
                                            setState(() {
                                              _searchCtrl.text = name;
                                              _locationSuggestions = [];
                                              _showPreviousLocations = false;
                                              if (lat != null && lon != null) {
                                                _selectedLocation = LatLng(lat, lon);
                                                _locationAddress = name;
                                                _mapController.move(_selectedLocation!, 15);
                                              }
                                            });
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            child: Row(
                                              children: [
                                                Icon(Icons.location_on_outlined, color: AppColors.accent, size: 16),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    style: TextStyle(color: C.textPrimary, fontSize: 12),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                // Previously reported locations as suggestions
                                if (_locationSuggestions.isEmpty && _showPreviousLocations)
                                  Builder(
                                    builder: (context) {
                                      // Extract unique locations from existing Firestore reports
                                      final reports = AppFirestoreService.instance.watchApprovedDangerZones();
                                      return StreamBuilder<List<Map<String, dynamic>>>(
                                        stream: reports,
                                        builder: (context, snap) {
                                          final allReports = snap.data ?? [];
                                          // Extract unique location strings
                                          final seen = <String>{};
                                          final previousLocs = <Map<String, dynamic>>[];
                                          for (final r in allReports) {
                                            final loc = r['location']?.toString() ?? '';
                                            if (loc.isNotEmpty && !seen.contains(loc)) {
                                              seen.add(loc);
                                              previousLocs.add(r);
                                            }
                                          }
                                          if (previousLocs.isEmpty) return const SizedBox.shrink();
                                          return Container(
                                            margin: const EdgeInsets.only(top: 4),
                                            constraints: const BoxConstraints(maxHeight: 200),
                                            decoration: BoxDecoration(
                                              color: AppColors.bg3,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.history_rounded, color: AppColors.accent, size: 14),
                                                      const SizedBox(width: 6),
                                                      Text('Previously Reported',
                                                        style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                                                    ],
                                                  ),
                                                ),
                                                Divider(height: 1, color: AppColors.border),
                                                Flexible(
                                                  child: ListView.separated(
                                                    shrinkWrap: true,
                                                    itemCount: previousLocs.length > 8 ? 8 : previousLocs.length,
                                                    separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                                                    itemBuilder: (context, index) {
                                                      final r = previousLocs[index];
                                                      final locStr = r['location']?.toString() ?? '';
                                                      final type = r['incidentType']?.toString() ?? '';
                                                      // Try to extract lat/lon from location string (format: "address (lat, lon)")
                                                      LatLng? coords;
                                                      final coordMatch = RegExp(r'\(([\d.-]+),\s*([\d.-]+)\)').firstMatch(locStr);
                                                      if (coordMatch != null) {
                                                        final lat = double.tryParse(coordMatch.group(1) ?? '');
                                                        final lon = double.tryParse(coordMatch.group(2) ?? '');
                                                        if (lat != null && lon != null) coords = LatLng(lat, lon);
                                                      }
                                                      // Clean display name (remove coords part)
                                                      final displayName = locStr.replaceAll(RegExp(r'\s*\([\d.,-\s]+\)\s*$'), '');
                                                      return InkWell(
                                                        onTap: () {
                                                          setState(() {
                                                            _searchCtrl.text = displayName;
                                                            _locationAddress = displayName;
                                                            _showPreviousLocations = false;
                                                            if (coords != null) {
                                                              _selectedLocation = coords;
                                                              _mapController.move(coords, 15);
                                                            } else {
                                                              // If no coords, search for the location
                                                              _searchLocation(displayName);
                                                            }
                                                          });
                                                        },
                                                        child: Padding(
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                          child: Row(
                                                            children: [
                                                              Icon(Icons.location_on_outlined, color: _getColorForType(type), size: 16),
                                                              const SizedBox(width: 8),
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Text(displayName,
                                                                      style: TextStyle(color: C.textPrimary, fontSize: 12),
                                                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                                                    if (type.isNotEmpty)
                                                                      Text(type,
                                                                        style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                                                  ],
                                                                ),
                                                              ),
                                                              Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 12),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),

                                const SizedBox(height: 10),
                                // Current selected address chip
                                if (_locationAddress.isNotEmpty && _locationAddress != 'Fetching address...')
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle_outline_rounded, color: AppColors.accent, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _locationAddress,
                                            style: TextStyle(color: C.textPrimary, fontSize: 11),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (_locationAddress == 'Fetching address...')
                                  Row(
                                    children: [
                                      const SizedBox(width: 4, height: 4, child: CircularProgressIndicator(strokeWidth: 2)),
                                      const SizedBox(width: 8),
                                      Text('Getting address...', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                    ],
                                  ),
                                const SizedBox(height: 10),
                                // Optional extra description
                                TextField(
                                  controller: _reportCtrl,
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Add details (optional)...',
                                    hintStyle: TextStyle(color: AppColors.textMuted),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    GestureDetector(
                                      onTap: () => setState(
                                          () => _showReportForm = false),
                                      child: Text('Cancel',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 13)),
                                    ),
                                    const SizedBox(width: 16),
                                    GestureDetector(
                                      onTap: _submitReport,
                                      child: Text('Submit Report',
                                          style: TextStyle(
                                              color: AppColors.accent,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                            // Map View
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  height: _showReportForm ? 160 : 220,
                                  child: _userLocation == null 
                                ? Center(child: CircularProgressIndicator(color: C.accent))
                                : Stack(
                                    children: [
                                      FlutterMap(
                                        mapController: _mapController,
                                        options: MapOptions(
                                          center: _selectedLocation ?? _userLocation ?? const LatLng(33.6844, 73.0479),
                                          zoom: 15,
                                          onPositionChanged: (position, hasGesture) {
                                            if (hasGesture && position.center != null) {
                                              setState(() {
                                                _selectedLocation = position.center;
                                              });
                                              if (_debounce?.isActive ?? false) _debounce!.cancel();
                                              _debounce = Timer(const Duration(milliseconds: 800), () {
                                                _reverseGeocode(position.center!);
                                              });
                                            }
                                          },
                                        ),
                                        children: [
                                          TileLayer(
                                            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                            subdomains: const ['a', 'b', 'c'],
                                            userAgentPackageName: 'com.smartsafe.app',
                                          ),
                                          MarkerLayer(
                                            markers: [
                                              if (_userLocation != null)
                                                Marker(
                                                  point: _userLocation!,
                                                  width: 20,
                                                  height: 20,
                                                  builder: (ctx) => Container(
                                                    decoration: BoxDecoration(
                                                      color: C.accent,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: Colors.white, width: 2),
                                                      boxShadow: const [
                                                        BoxShadow(color: Colors.black26, blurRadius: 4),
                                                      ]
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.only(bottom: 40.0),
                                          child: Icon(Icons.location_on, color: C.accent, size: 40),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Time filters. These were decorative labels before —
                            // tapping them now actually narrows the list below.
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(
                                children: [
                                  _TimePill(
                                    label: '${filteredReports.length} Reports',
                                    icon: Icons.report_rounded,
                                    color: AppColors.accent,
                                    selected: _timeFilter == 'All',
                                    onTap: () =>
                                        setState(() => _timeFilter = 'All'),
                                  ),
                                  const SizedBox(width: 8),
                                  _TimePill(
                                    label: 'Today',
                                    icon: Icons.calendar_today_rounded,
                                    color: AppColors.warning,
                                    selected: _timeFilter == 'Today',
                                    onTap: () =>
                                        setState(() => _timeFilter = 'Today'),
                                  ),
                                  const SizedBox(width: 8),
                                  _TimePill(
                                    label: 'This Week',
                                    icon: Icons.date_range_rounded,
                                    color: AppColors.accent,
                                    selected: _timeFilter == 'Week',
                                    onTap: () =>
                                        setState(() => _timeFilter = 'Week'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Reports list
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: filteredReports.length,
                              itemBuilder: (ctx, i) {
                          final r = filteredReports[i];
                          // Resilient across app-reported zones (incidentType/
                          // location) and admin-created zones (name/coordinates).
                          final rType =
                              (r['incidentType'] ?? r['name'] ?? 'Unsafe Area')
                                  .toString();
                          final rArea = (r['location'] ??
                                  r['safetyAdvice'] ??
                                  r['coordinates'] ??
                                  'Unknown Area')
                              .toString();
                          final rTime = r['time'] ?? 'Just now';
                          final color = _getColorForType(rType);

                          return SlideUpFade(
                            delay: Duration(milliseconds: 220 + i * 50),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DCard(
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                          _iconForType(rType),
                                          color: color,
                                          size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: StatusBadge(
                                                    label: rType, color: color),
                                              ),
                                              const Spacer(),
                                              Text(rTime,
                                                  style: TextStyle(
                                                      color: AppColors.textMuted,
                                                      fontSize: 10)),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(rArea,
                                              style: TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 5),
                                          Row(
                                            children: [
                                              Icon(Icons.person,
                                                  color: AppColors.textMuted, size: 12),
                                              const SizedBox(width: 4),
                                              Text(
                                                  '${r['user'] ?? 'User'}',
                                                  style: TextStyle(
                                                      color: AppColors.textMuted,
                                                      fontSize: 11)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}

/// A tappable time filter (All / Today / This Week) for the reports list.
/// Highlights when active so it's obvious which slice you're looking at.
class _TimePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TimePill({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.22 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: color.withValues(alpha: selected ? 0.8 : 0.2),
                width: selected ? 1.4 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatPill(this.label, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
