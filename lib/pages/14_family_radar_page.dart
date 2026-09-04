import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import '../models/models.dart';
import '../services/app_firestore_service.dart';
import '../services/live_tracking_service.dart';
import '../services/location_service.dart';
import '../theme/colors.dart';
import '../utils/phone_utils.dart';
import '../widgets/widgets.dart';
import '../widgets/live_map_widget.dart';

class FamilyRadarPage extends StatefulWidget {
  const FamilyRadarPage({super.key});

  @override
  State<FamilyRadarPage> createState() => _FamilyRadarPageState();
}

/// Resolved live location of a contact (only for SmartSafe users sharing it).
class _Loc {
  final bool known;
  final double distanceKm;
  final String address;
  final double lat;
  final double lon;
  const _Loc(this.known, this.distanceKm, this.address,
      {this.lat = 0, this.lon = 0});
  const _Loc.unknown()
      : known = false,
        distanceKm = 0,
        address = '',
        lat = 0,
        lon = 0;
}

class _FamilyRadarPageState extends State<FamilyRadarPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _radarCtrl;
  StreamSubscription<List<Contact>>? _contactsSub;
  StreamSubscription<LocationData>? _myLocSub;
  Timer? _refreshTimer;

  List<Contact> _contacts = [];
  final Map<String, _Loc> _locs = {}; // contactId -> location
  double? _myLat, _myLon;
  bool _showMap = true; // Map view (real positions) vs the radar animation.

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();

    // Real emergency contacts (with real online status).
    _contactsSub =
        AppFirestoreService.instance.watchMyEmergencyContacts().listen((list) {
      if (!mounted) return;
      setState(() => _contacts = list);
      _resolveLocations();
    });

    // My own live location.
    LocationService.instance.getCurrentLocation().then((loc) {
      if (loc != null && mounted) {
        setState(() {
          _myLat = loc.latitude;
          _myLon = loc.longitude;
        });
        _resolveLocations();
      }
    });
    if (!LocationService.instance.isTracking) {
      LocationService.instance.requestPermission().then((_) {
        LocationService.instance.startTracking();
      });
    }
    _myLocSub = LocationService.instance.onLocationChanged.listen((loc) {
      if (!mounted) return;
      _myLat = loc.latitude;
      _myLon = loc.longitude;
    });

    // Refresh contact locations periodically.
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 12), (_) => _resolveLocations());
  }

  /// For each contact, find the matching SmartSafe user (by phone) and read
  /// their shared live location, then compute the real distance from me.
  Future<void> _resolveLocations() async {
    // NOTE: we deliberately do NOT require my own GPS here. This used to bail
    // out whenever my location wasn't ready (indoors, permission still pending),
    // which meant family members who WERE sharing their location showed up as
    // "unknown" — the radar looked broken. Now their positions always resolve;
    // only the distance-from-me needs my fix, and it's simply omitted until I
    // have one.
    if (_contacts.isEmpty) return;
    final db = FirebaseFirestore.instance;
    for (final c in _contacts) {
      final norm = normalizePhone(c.phone);
      if (norm.isEmpty) {
        _locs[c.id] = const _Loc.unknown();
        continue;
      }
      try {
        final us = await db
            .collection('users')
            .where('phoneNormalized', isEqualTo: norm)
            .limit(1)
            .get();
        if (us.docs.isEmpty) {
          _locs[c.id] = const _Loc.unknown();
          continue;
        }
        final uid = us.docs.first.id;
        final lt = await db.collection('live_tracking').doc(uid).get();
        final d = lt.data();
        final lat = (d?['latitude'] as num?)?.toDouble();
        final lon = (d?['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) {
          _locs[c.id] = const _Loc.unknown();
          continue;
        }
        // Distance only makes sense once I have my own fix; -1 means "unknown".
        final dist = (_myLat != null && _myLon != null)
            ? distanceKm(_myLat!, _myLon!, lat, lon)
            : -1.0;
        _locs[c.id] = _Loc(true, dist, d?['address']?.toString() ?? '',
            lat: lat, lon: lon);
      } catch (_) {
        _locs[c.id] = const _Loc.unknown();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _contactsSub?.cancel();
    _myLocSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Family members (with a known shared location) as map markers. Online =
  /// green marker, offline = red.
  List<HelperInfo> _familyHelpers() {
    final list = <HelperInfo>[];
    for (final c in _contacts) {
      final loc = _locs[c.id];
      if (loc != null && loc.known) {
        list.add(HelperInfo(
          userId: c.id,
          name: c.name,
          latitude: loc.lat,
          longitude: loc.lon,
          address: loc.address,
          status: c.isOnline ? 'helping' : 'live',
          timestamp: DateTime.now(),
        ));
      }
    }
    return list;
  }

  /// Stable position on the radar — angle from the name, ring from real distance.
  Offset _radarPos(Contact c, double maxW, double maxH) {
    final loc = _locs[c.id];
    final angle = (c.name.hashCode % 360) * pi / 180;
    // distanceKm < 0 means "we know where they are, but not how far — my own GPS
    // isn't ready yet"; park them mid-ring rather than at the unknown edge.
    final norm = (loc != null && loc.known)
        ? (loc.distanceKm < 0
            ? 0.55
            : (loc.distanceKm / 10).clamp(0.12, 0.95))
        : 0.9; // unknown → outer edge
    final dx = 0.5 + norm * 0.45 * cos(angle);
    final dy = 0.5 + norm * 0.45 * sin(angle);
    return Offset(dx * maxW - 20, dy * maxH - 20);
  }

  @override
  Widget build(BuildContext context) {
    final sharing = _contacts.where((c) => _locs[c.id]?.known == true).length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: Column(
              children: [
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DynText('family_radar', 'title', 'Family Radar',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: C.textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800)),
                              Text('Live location of your circle',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.textMuted, fontSize: 12)),
                            ],
                          ),
                        ),
                        // Map ⟷ Radar view toggle.
                        GestureDetector(
                          onTap: () => setState(() => _showMap = !_showMap),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: AppColors.bg2,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                    _showMap
                                        ? Icons.radar_rounded
                                        : Icons.map_rounded,
                                    color: AppColors.accent,
                                    size: 14),
                                const SizedBox(width: 4),
                                Text(_showMap ? 'Radar' : 'Map',
                                    style: TextStyle(
                                        color: C.textPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              BlinkDot(color: AppColors.accent, size: 8),
                              const SizedBox(width: 6),
                              Text('LIVE',
                                  style: TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Real MAP view: you + each family member at their actual
                // position (e.g. you in Malir, them in North Karachi).
                if (_showMap)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SlideUpFade(
                      delay: const Duration(milliseconds: 100),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: _myLat == null
                            ? Container(
                                decoration: BoxDecoration(
                                  color: AppColors.bg2,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.accent),
                                ),
                              )
                            : LiveMapWidget(
                                myLatitude: _myLat!,
                                myLongitude: _myLon!,
                                myAddress: 'You are here',
                                sosRadiusKm: 0,
                                showRoute: false,
                                helpers: _familyHelpers(),
                              ),
                      ),
                    ),
                  ),

                // Radar
                if (!_showMap)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SlideUpFade(
                    delay: const Duration(milliseconds: 100),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                  painter: _RadarPainter(_radarCtrl)),
                            ),
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: _radarCtrl,
                                  builder: (_, __) => CustomPaint(
                                    painter:
                                        _RadarSweepPainter(_radarCtrl.value),
                                  ),
                                ),
                              ),
                            ),
                            const Center(child: _CenterDot()),
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                return Stack(
                                  children: _contacts.map((c) {
                                    final pos = _radarPos(c,
                                        constraints.maxWidth,
                                        constraints.maxHeight);
                                    return AnimatedPositioned(
                                      duration:
                                          const Duration(milliseconds: 600),
                                      curve: Curves.easeInOut,
                                      left: pos.dx,
                                      top: pos.dy,
                                      child: _MemberDot(
                                        contact: c,
                                        known: _locs[c.id]?.known == true,
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                    _contacts.isEmpty
                        ? 'Add emergency contacts to see them here'
                        : '$sharing of ${_contacts.length} sharing live location',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(height: 12),

                // Real contact cards
                Expanded(
                  child: _contacts.isEmpty
                      ? Center(
                          child: Text('No contacts yet',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 14)))
                      : ListView.builder(
                          cacheExtent: 500,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _contacts.length,
                          itemBuilder: (ctx, i) {
                            final c = _contacts[i];
                            final loc = _locs[c.id];
                            final known = loc?.known == true;
                            return SlideUpFade(
                              delay: Duration(milliseconds: 120 + i * 50),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: DCard(
                                  child: Row(
                                    children: [
                                      Stack(children: [
                                        AvatarWidget(
                                          initials: c.initials,
                                          color: c.avatarColor,
                                          size: 44,
                                        ),
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            width: 13,
                                            height: 13,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: AppColors.bg,
                                              border: Border.all(
                                                  color: AppColors.bg,
                                                  width: 2),
                                            ),
                                            child: c.isOnline
                                                ? BlinkDot(
                                                    color: AppColors.success,
                                                    size: 9)
                                                : Container(
                                                    decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: AppColors
                                                            .textMuted)),
                                          ),
                                        ),
                                      ]),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(c.name,
                                                style: TextStyle(
                                                    color: C.textPrimary,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13)),
                                            const SizedBox(height: 3),
                                            Row(children: [
                                              Icon(Icons.location_on_rounded,
                                                  color: AppColors.textMuted,
                                                  size: 12),
                                              const SizedBox(width: 3),
                                              Expanded(
                                                child: Text(
                                                    known
                                                        ? (loc!.distanceKm < 0
                                                            ? (loc.address.isNotEmpty
                                                                ? loc.address
                                                                : 'Sharing location')
                                                            : '${loc.address.isNotEmpty ? loc.address : 'Nearby'} • ${loc.distanceKm.toStringAsFixed(1)} km away')
                                                        : 'Location not shared',
                                                    style: TextStyle(
                                                        color: AppColors
                                                            .textMuted,
                                                        fontSize: 11),
                                                    maxLines: 1,
                                                    overflow: TextOverflow
                                                        .ellipsis),
                                              ),
                                            ]),
                                          ],
                                        ),
                                      ),
                                      StatusBadge(
                                        label:
                                            c.isOnline ? 'Online' : 'Away',
                                        color: c.isOnline
                                            ? AppColors.success
                                            : AppColors.textMuted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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

class _MemberDot extends StatelessWidget {
  final Contact contact;
  final bool known;
  const _MemberDot({required this.contact, required this.known});

  @override
  Widget build(BuildContext context) {
    final color = known ? contact.avatarColor : AppColors.textMuted;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
            ),
          ),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: C.textPrimary, width: 2),
            ),
            child: Center(
              child: Text(
                contact.initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterDot extends StatelessWidget {
  const _CenterDot();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
            border: Border.all(color: C.textPrimary, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.5),
                blurRadius: 10,
                spreadRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('YOU',
              style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Animation<double> ctrl;
  _RadarPainter(this.ctrl) : super(repaint: ctrl);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = min(size.width, size.height) / 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = C.bg2);
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(
          center,
          maxR * i / 4,
          Paint()
            ..color = AppColors.accent.withValues(alpha: 0.1)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke);
    }
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      canvas.drawLine(
          center,
          Offset(center.dx + maxR * cos(angle), center.dy + maxR * sin(angle)),
          Paint()
            ..color = AppColors.accent.withValues(alpha: 0.07)
            ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => false;
}

class _RadarSweepPainter extends CustomPainter {
  final double progress;
  _RadarSweepPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = min(size.width, size.height) / 2;
    final angle = progress * 2 * pi - pi / 2;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle - pi / 3,
        endAngle: angle,
        colors: [
          Colors.transparent,
          AppColors.accent.withValues(alpha: 0.25),
        ],
        transform: GradientRotation(angle - pi / 2 - pi / 3),
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR, sweepPaint);
    canvas.drawLine(
        center,
        Offset(center.dx + maxR * cos(angle), center.dy + maxR * sin(angle)),
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.8)
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter old) =>
      old.progress != progress;
}
