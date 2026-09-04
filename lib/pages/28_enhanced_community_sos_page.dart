import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../navigation/dark_route.dart';
import '../services/live_tracking_service.dart';
import '../services/location_service.dart';
import '../theme/colors.dart';
import '../widgets/live_map_widget.dart';
import '../widgets/widgets.dart';

class EnhancedCommunitySosPage extends StatefulWidget {
  final VoidCallback? onCancel;

  const EnhancedCommunitySosPage({super.key, this.onCancel});

  static void open(BuildContext context, {VoidCallback? onCancel}) {
    Navigator.push(
      context,
      darkRoute(EnhancedCommunitySosPage(onCancel: onCancel)),
    );
  }

  @override
  State<EnhancedCommunitySosPage> createState() =>
      _EnhancedCommunitySosPageState();
}

class _EnhancedCommunitySosPageState extends State<EnhancedCommunitySosPage>
    with TickerProviderStateMixin {
  // Services
  late LiveTrackingService _trackingService;
  late AnimationController _sosScale;
  late AnimationController _mapPinPulse;
  late List<AnimationController> _rings;
  late List<AnimationController> _waveBars;

  // State
  bool _sosActive = false;
  double _myLat = 24.8607; // Default until the first real GPS fix arrives
  double _myLon = 67.0011;
  // True once a REAL device fix has replaced the default above — distances/ETAs
  // stay "—" until then instead of showing wrong values vs the Karachi default.
  bool _hasMyFix = false;
  String _myPlaceName = 'Loading...';
  List<HelperInfo> _helpers = [];
  int _helperCount = 0;
  // Highest responder count we've already announced, and whether the responder
  // dialog is on screen — together they stop the "X person is responding"
  // popup from re-appearing on every 2-second helper poll.
  int _lastNotifiedHelperCount = 0;
  bool _helperDialogOpen = false;
  final List<Timer> _timers = [];

  // Streams
  StreamSubscription<LocationData>? _locationSub;
  StreamSubscription<List<HelperInfo>>? _helpersSub;
  StreamSubscription<int>? _helperCountSub;
  DateTime? _lastGeocodeTime;

  // UI State
  bool _mapVisible = false;
  HelperInfo? _selectedHelper;

  @override
  void initState() {
    super.initState();
    _trackingService = LiveTrackingService();

    // Initialize animations
    // Same cadence as the main SOS button (PulseSOSButton) for a unified feel.
    _sosScale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _mapPinPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _rings = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      );
      Future.delayed(Duration(milliseconds: i * 600), () {
        if (mounted) c.repeat();
      });
      return c;
    });

    _waveBars = List.generate(5, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });

    _initLocation();
  }

  void _initLocation() async {
    if (!LocationService.instance.isTracking) {
      final err = await LocationService.instance.requestPermission();
      if (err == null) {
        LocationService.instance.startTracking();
      }
    }
    // Fetch initial location immediately to avoid showing default Karachi coordinates
    try {
      final loc = await LocationService.instance.getCurrentLocation();
      if (loc != null && mounted) {
        setState(() {
          _myLat = loc.latitude;
          _myLon = loc.longitude;
          _hasMyFix = true;
        });
        _fetchPlaceName(loc.latitude, loc.longitude);
      }
    } catch (_) {}
    _startLocationListener();
  }

  void _startLocationListener() {
    _locationSub?.cancel();
    _locationSub = LocationService.instance.onLocationChanged.listen((data) {
      if (mounted) {
        setState(() {
          _myLat = data.latitude;
          _myLon = data.longitude;
          _hasMyFix = true;
        });
        _fetchPlaceName(data.latitude, data.longitude);
      }
    });
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
      final response = await http.get(
        url,
        headers: {'User-Agent': 'SmartSafeApp/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'];
        if (displayName != null && mounted) {
          final parts = displayName.toString().split(',');
          final shortName = parts.take(3).join(',').trim();
          setState(() {
            _myPlaceName =
                shortName.isNotEmpty ? shortName : displayName.toString();
          });
          await _trackingService.updateCurrentAddress(_myPlaceName);
        }
      }
    } catch (e) {
      debugPrint('Error fetching place name: $e');
    }
  }

  Future<void> _activateSOS() async {
    if (_sosActive) return;

    setState(() => _sosActive = true);

    try {
      // Activate SOS in service
      await _trackingService.activateSOS();

      // Show success feedback
      _showSuccessMessage(
          'SOS Activated! Nearby people are being notified...');

      // Listen to helpers
      _helpersSub?.cancel();
      _helpersSub = _trackingService
          .getHelpersForSOS(FirebaseAuth.instance.currentUser!.uid)
          .listen((helpers) {
        if (mounted) {
          setState(() => _helpers = helpers);
        }
      });

      // Listen to helper count
      _helperCountSub?.cancel();
      _helperCountSub = _trackingService.helperCount.listen((count) {
        if (mounted) {
          setState(() => _helperCount = count);
          // Announce ONLY when a NEW responder joins (count rises) and no
          // dialog is already open. The stream re-emits every ~2s, so the old
          // `if (count > 0)` re-opened this popup endlessly.
          if (count > _lastNotifiedHelperCount && !_helperDialogOpen) {
            _lastNotifiedHelperCount = count;
            _showHelperNotification(count);
          }
        }
      });

      // Auto-show map almost immediately (was 2s — felt sluggish).
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() => _mapVisible = true);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error activating SOS: $e')),
        );
      }
      setState(() => _sosActive = false);
    }
  }

  Future<void> _deactivateSOS() async {
    setState(() {
      _sosActive = false;
      _helpers = [];
      _helperCount = 0;
      // Reset so a fresh SOS in the same session announces responders again.
      _lastNotifiedHelperCount = 0;
      _mapVisible = false;
    });

    await _trackingService.deactivateSOS();
    _helpersSub?.cancel();
    _helperCountSub?.cancel();

    if (mounted) {
      _showSuccessMessage('SOS Deactivated');
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: C.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showHelperNotification(int count) {
    _helperDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: C.bg2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.success.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: C.success.withValues(alpha: 0.2),
                  border: Border.all(color: C.success, width: 2),
                ),
                child: Icon(
                  Icons.people,
                  color: C.success,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$count ${count == 1 ? 'person is' : 'people are'} responding',
                style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Stay safe. Help is on the way!',
                style: TextStyle(
                  color: C.textMuted,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: C.red),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            color: C.red,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _mapVisible = true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: C.success,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'View Map',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _helperDialogOpen = false);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _helpersSub?.cancel();
    _helperCountSub?.cancel();
    _sosScale.dispose();
    _mapPinPulse.dispose();
    for (var ring in _rings) {
      ring.dispose();
    }
    for (var bar in _waveBars) {
      bar.dispose();
    }
    for (var timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return WillPopScope(
      onWillPop: () async {
        if (_sosActive) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: C.bg2,
              title: Text(
                'Deactivate SOS?',
                style: TextStyle(color: C.textPrimary),
              ),
              content: Text(
                'Are you sure? Helpers are being notified.',
                style: TextStyle(color: C.textMuted),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: C.red)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child:
                      Text('Yes, Deactivate', style: TextStyle(color: C.red)),
                ),
              ],
            ),
          );

          if (confirm == true) {
            await _deactivateSOS();
            widget.onCancel?.call();
            return true;
          }
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: _sosActive && _mapVisible
            ? _buildMapView()
            : Stack(
                children: [
                  const DotGrid(),
                  _buildControlView(screenHeight, isMobile),
                ],
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Control View (SOS Button)
  // ─────────────────────────────────────────────

  Widget _buildControlView(double screenHeight, bool isMobile) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Header — matches the rest of the app (back arrow + title + subtitle)
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: C.textPrimary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DynText(
                        'community_sos',
                        'title',
                        'Community SOS',
                        style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text('Alert nearby helpers instantly',
                          style:
                              TextStyle(color: C.textMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Location Info
              SlideUpFade(
                delay: const Duration(milliseconds: 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: C.bg2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: C.red.withValues(alpha: 0.2),
                        ),
                        child: Icon(Icons.location_on, color: C.red, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Location',
                              style: TextStyle(
                                color: C.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _myPlaceName,
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // SOS Button
              SlideUpFade(
                delay: const Duration(milliseconds: 100),
                child: Center(
                  child: _sosActive
                      // Active = broadcasting. Green pulse rings + check.
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            PulseRing(color: C.success, size: 160),
                            Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    C.success,
                                    C.success.withValues(alpha: 0.7)
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: C.success.withValues(alpha: 0.35),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_rounded,
                                      color: Colors.white, size: 46),
                                  SizedBox(height: 2),
                                  Text('ACTIVE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.5,
                                      )),
                                ],
                              ),
                            ),
                          ],
                        )
                      // Idle = animated brand button (logo icon + "Community SOS").
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            PulseRing(color: C.red, size: 170),
                            // Same animation as the main SOS button: a subtle
                            // 1.0→1.04 easeInOutSine pulse with a radial
                            // highlight and haptic feedback on tap.
                            RepaintBoundary(
                              child: AnimatedBuilder(
                              animation: _sosScale,
                              builder: (_, child) => Transform.scale(
                                scale: Tween<double>(begin: 1.0, end: 1.04)
                                    .animate(CurvedAnimation(
                                        parent: _sosScale,
                                        curve: Curves.easeInOutSine))
                                    .value,
                                child: child,
                              ),
                              child: GestureDetector(
                                onTapDown: (_) =>
                                    HapticFeedback.lightImpact(),
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  _activateSOS();
                                },
                                child: Container(
                                  width: 150,
                                  height: 150,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: AppTheme.sosGradient,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.35),
                                        blurRadius: 22,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0.2),
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.3),
                                        ],
                                        stops: const [0.0, 0.7, 1.0],
                                        center: Alignment.topLeft,
                                        radius: 1.2,
                                      ),
                                      border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          width: 1.5),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.shield_rounded,
                                            color: Colors.white, size: 44),
                                        SizedBox(height: 6),
                                        Text('Community',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            )),
                                        Text('SOS',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 2,
                                            )),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Status
              SlideUpFade(
                delay: const Duration(milliseconds: 150),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: C.bg2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _sosActive
                          ? C.success.withValues(alpha: 0.5)
                          : C.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_sosActive)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: C.success,
                          ),
                        ),
                      SizedBox(width: _sosActive ? 8 : 0),
                      Text(
                        _sosActive
                            ? 'Broadcasting live location...'
                            : 'Press SOS to alert nearby people',
                        style: TextStyle(
                          color: _sosActive ? C.success : C.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_sosActive) ...[
                const SizedBox(height: 24),

                // Helper Count
                SlideUpFade(
                  delay: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: C.bg2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _helperCount > 0
                            ? C.success.withValues(alpha: 0.5)
                            : C.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (_helperCount > 0 ? C.success : C.warning)
                                .withValues(alpha: 0.2),
                          ),
                          child: Icon(
                            Icons.people,
                            color: _helperCount > 0 ? C.success : C.warning,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'People Helping',
                                style: TextStyle(
                                  color: C.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _helperCount.toString(),
                                style: TextStyle(
                                  color: _helperCount > 0 ? C.success : C.warning,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Responders list — who is coming + their status.
                if (_helpers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SlideUpFade(
                    delay: const Duration(milliseconds: 220),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: C.bg2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.success.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Coming to help',
                              style: TextStyle(
                                  color: C.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          ..._helpers.map((h) {
                            final arrived = h.status == 'arrived';
                            final statusLabel =
                                arrived ? 'Arrived' : 'On the way';
                            final statusColor =
                                arrived ? C.success : C.warning;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: statusColor.withValues(alpha: 0.18),
                                  ),
                                  child: Center(
                                    child: Text(
                                      h.name.isNotEmpty
                                          ? h.name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    h.name.isNotEmpty ? h.name : 'A helper',
                                    style: TextStyle(
                                        color: C.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(
                                        arrived
                                            ? Icons.check_circle_rounded
                                            : Icons.directions_walk_rounded,
                                        color: statusColor,
                                        size: 13),
                                    const SizedBox(width: 4),
                                    Text(statusLabel,
                                        style: TextStyle(
                                            color: statusColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700)),
                                  ]),
                                ),
                              ]),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // View Map Button
                SlideUpFade(
                  delay: const Duration(milliseconds: 250),
                  child: GestureDetector(
                    onTap: () => setState(() => _mapVisible = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [C.red, C.red.withValues(alpha: 0.7)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'View Live Map',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Deactivate SOS Button
                SlideUpFade(
                  delay: const Duration(milliseconds: 300),
                  child: GestureDetector(
                    onTap: () async => await _deactivateSOS(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: C.red),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Deactivate SOS',
                        style: TextStyle(
                          color: C.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Info Cards
              SlideUpFade(
                delay: const Duration(milliseconds: 300),
                child: Column(
                  children: [
                    _infoCard(
                      icon: Icons.location_on,
                      title: 'Live Location',
                      description: 'Your exact location shared in real-time',
                      color: C.red,
                    ),
                    const SizedBox(height: 12),
                    _infoCard(
                      icon: Icons.people,
                      title: 'Community Help',
                      description: 'Nearby SmartSafe users notified instantly',
                      color: C.success,
                    ),
                    const SizedBox(height: 12),
                    _infoCard(
                      icon: Icons.navigation,
                      title: 'Route Tracking',
                      description: 'See helper routes and ETA on map',
                      color: C.warning,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: C.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: C.textMuted,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Live Map View
  // ─────────────────────────────────────────────

  Widget _buildMapView() {
    return Stack(
      children: [
        // Map + bottom helper bar share a single Column so the helper bar can
        // never overlap the map's own address card / attribution — the map
        // simply gets a bit shorter and the bar owns its own space below it.
        Column(
          children: [
            Expanded(
              child: LiveMapWidget(
                myLatitude: _myLat,
                myLongitude: _myLon,
                myAddress: _myPlaceName,
                helpers: _helpers,
                showRoute: true,
                // Community SOS now reaches every user, not a fixed radius —
                // so don't draw a misleading broadcast circle.
                sosRadiusKm: 0,
                onHelperTap: (helper) {
                  setState(() => _selectedHelper = helper);
                  _showHelperDetails(helper);
                },
              ),
            ),
            // Bottom helper bar — page-owned, solid background, inside SafeArea.
            if (_helpers.isNotEmpty) _buildHelperBottomBar(),
          ],
        ),

        // Top Bar — overlays only the top of the map. spaceBetween keeps the
        // back button, LIVE badge and Helping pill each in their own space.
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _mapVisible = false),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.bg.withValues(alpha: 0.8),
                      border: Border.all(color: C.red),
                    ),
                    child: Icon(Icons.arrow_back, color: C.textPrimary, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: C.bg.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: C.success, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: C.success,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: C.success,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: C.bg.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: C.warning),
                    ),
                    child: Text(
                      '$_helperCount Helping',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: C.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Bottom helper bar shown under the map in the map view. Lives in its own
  // Column cell (not a Positioned overlay) so it never overlaps the map's
  // address card or attribution, and stays inside SafeArea on all sizes.
  Widget _buildHelperBottomBar() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: C.bg2,
        border: Border(
          top: BorderSide(color: C.red.withValues(alpha: 0.35)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Helpers on the way',
                style: TextStyle(
                  color: C.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 132),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        _helpers.map((helper) => _helperCard(helper)).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helperCard(HelperInfo helper) {
    return GestureDetector(
      onTap: () => _showHelperDetails(helper),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: helper.status == 'helping'
                ? C.success
                : helper.status == 'arrived'
                    ? C.success
                    : C.warning,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: helper.status == 'helping'
                    ? C.success
                    : helper.status == 'arrived'
                        ? C.success
                        : C.warning,
              ),
              child: Center(
                child: Text(
                  helper.name.isNotEmpty ? helper.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              helper.name,
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: (helper.status == 'helping'
                        ? C.success
                        : helper.status == 'arrived'
                            ? C.success
                            : C.warning)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                helper.status == 'arriving'
                    ? 'Arriving'
                    : helper.status == 'arrived'
                        ? 'Arrived'
                        : 'Helping',
                style: TextStyle(
                  color: helper.status == 'helping'
                      ? C.success
                      : helper.status == 'arrived'
                          ? C.success
                          : C.warning,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelperDetails(HelperInfo helper) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(
            top: BorderSide(
              color: helper.status == 'helping'
                  ? C.success
                  : helper.status == 'arrived'
                      ? C.success
                      : C.warning,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: helper.status == 'helping'
                    ? C.success
                    : helper.status == 'arrived'
                        ? C.success
                        : C.warning,
              ),
              child: Center(
                child: Text(
                  helper.name.isNotEmpty ? helper.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              helper.name,
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (helper.status == 'helping'
                        ? C.success
                        : helper.status == 'arrived'
                            ? C.success
                            : C.warning)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                helper.status == 'arriving'
                    ? 'On the way'
                    : helper.status == 'arrived'
                        ? 'Arrived'
                        : 'Helping you',
                style: TextStyle(
                  color: helper.status == 'helping'
                      ? C.success
                      : helper.status == 'arrived'
                          ? C.success
                          : C.warning,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (helper.address.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place, color: C.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      helper.address,
                      style: TextStyle(color: C.textMuted, fontSize: 12),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Icon(Icons.location_on, color: C.red, size: 20),
                      const SizedBox(height: 4),
                      Text(
                        _hasMyFix
                            ? '${_calculateDistance(helper.latitude, helper.longitude).toStringAsFixed(1)} km'
                            : '—',
                        style: TextStyle(
                          color: C.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'away',
                        style: TextStyle(
                          color: C.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: C.bg2,
                  ),
                  Column(
                    children: [
                      Icon(Icons.access_time, color: C.warning, size: 20),
                      const SizedBox(height: 4),
                      Text(
                        _hasMyFix
                            ? _calculateETA(helper.latitude, helper.longitude)
                            : '—',
                        style: TextStyle(
                          color: C.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'ETA',
                        style: TextStyle(
                          color: C.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: C.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Close',
                        style: TextStyle(
                          color: C.red,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      // Add contact action if needed
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: C.success,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Share Thank You',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _calculateDistance(double helperLat, double helperLon) {
    // Simple Haversine formula
    const R = 6371; // Earth radius in km
    final dLat = (helperLat - _myLat) * 3.14159 / 180;
    final dLon = (helperLon - _myLon) * 3.14159 / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_myLat * 3.14159 / 180) *
            cos(helperLat * 3.14159 / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * asin(sqrt(a));
    return R * c;
  }

  String _calculateETA(double helperLat, double helperLon) {
    final distance = _calculateDistance(helperLat, helperLon);
    final minutes = ((distance * 60) / 30).toInt(); // Assuming 30 km/h average
    if (minutes < 1) return '< 1 min';
    return '$minutes min';
  }
}
