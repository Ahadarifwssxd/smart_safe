import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/live_tracking_service.dart';
import '../services/location_service.dart';
import '../theme/colors.dart';
import '../widgets/live_map_widget.dart';

/// Helper-side live view. Opens when a nearby user accepts a Community SOS.
/// Shows the victim's LIVE location + address on a map, the helper's own
/// position, distance/ETA, and lets the helper update their status as they
/// move ("On my way" → "I've arrived"). Both sides see each other live because
/// [LiveTrackingService] keeps writing positions to Firestore.
class HelperResponsePage extends StatefulWidget {
  final String sosUserId;
  final String victimName;
  const HelperResponsePage({
    super.key,
    required this.sosUserId,
    this.victimName = 'Someone nearby',
  });

  @override
  State<HelperResponsePage> createState() => _HelperResponsePageState();
}

class _HelperResponsePageState extends State<HelperResponsePage> {
  final _tracking = LiveTrackingService();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _victimSub;
  StreamSubscription<LocationData>? _meSub;

  double? _victimLat, _victimLon;
  String _victimAddress = '';
  double? _myLat, _myLon;
  String _status = 'arriving';
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    // Register as a helper (adds us to the SOS + starts our live tracking).
    _tracking.respondToSOS(widget.sosUserId);

    // Watch the victim's live location.
    _victimSub = FirebaseFirestore.instance
        .collection('live_tracking')
        .doc(widget.sosUserId)
        .snapshots()
        .listen((doc) {
      final d = doc.data();
      if (d == null || !mounted) return;
      setState(() {
        _victimLat = (d['latitude'] ?? _victimLat)?.toDouble();
        _victimLon = (d['longitude'] ?? _victimLon)?.toDouble();
        _victimAddress = d['address']?.toString() ?? _victimAddress;
      });
    });

    // Watch our own location.
    LocationService.instance.getCurrentLocation().then((loc) {
      if (loc != null && mounted) {
        setState(() {
          _myLat = loc.latitude;
          _myLon = loc.longitude;
        });
      }
    });
    _meSub = LocationService.instance.onLocationChanged.listen((loc) {
      if (!mounted) return;
      setState(() {
        _myLat = loc.latitude;
        _myLon = loc.longitude;
      });
    });
  }

  @override
  void dispose() {
    _victimSub?.cancel();
    _meSub?.cancel();
    super.dispose();
  }

  double? get _distanceKm {
    if (_victimLat == null ||
        _victimLon == null ||
        _myLat == null ||
        _myLon == null) {
      return null;
    }
    return calculateDistance(_myLat!, _myLon!, _victimLat!, _victimLon!);
  }

  String get _eta {
    final d = _distanceKm;
    if (d == null) return '—';
    final mins = ((d / 30) * 60).round(); // ~30 km/h
    return mins < 1 ? '<1 min' : '$mins min';
  }

  Future<void> _setStatus(String status) async {
    setState(() => _status = status);
    await _tracking.updateHelperStatus(status);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: C.success,
        behavior: SnackBarBehavior.floating,
        content: Text(
          status == 'arrived' ? 'Marked as arrived' : 'Status updated',
          style: const TextStyle(color: Colors.white),
        ),
      ));
    }
  }

  Future<void> _stopHelping() async {
    if (_ending) return;
    setState(() => _ending = true);
    await _tracking.stopLiveTracking();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasVictim = _victimLat != null && _victimLon != null;
    final hasMe = _myLat != null && _myLon != null;

    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _stopHelping,
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: C.textPrimary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Helping ${widget.victimName}',
                            style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        Text('Live emergency response',
                            style:
                                TextStyle(color: C.accent, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Live map (victim centered; helper shown as a marker w/ route)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: hasVictim
                    ? LiveMapWidget(
                        myLatitude: _victimLat!,
                        myLongitude: _victimLon!,
                        myAddress: _victimAddress.isNotEmpty
                            ? _victimAddress
                            : 'Locating ${widget.victimName}…',
                        sosRadiusKm: 0,
                        helpers: hasMe
                            ? [
                                HelperInfo(
                                  userId: 'me',
                                  name: 'You',
                                  latitude: _myLat!,
                                  longitude: _myLon!,
                                  status: _status,
                                  timestamp: DateTime.now(),
                                )
                              ]
                            : const [],
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: C.accent),
                            const SizedBox(height: 16),
                            Text('Getting ${widget.victimName}\'s location…',
                                style: TextStyle(color: C.textMuted)),
                          ],
                        ),
                      ),
              ),
            ),

            // Stats + actions
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.bg2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat(Icons.location_on, 'Distance',
                          _distanceKm == null
                              ? '—'
                              : '${_distanceKm!.toStringAsFixed(1)} km'),
                      Container(width: 1, height: 36, color: C.border),
                      _stat(Icons.access_time, 'ETA', _eta),
                    ],
                  ),
                  if (_victimAddress.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.place, color: C.accent, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_victimAddress,
                              style: TextStyle(
                                  color: C.textMuted, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _setStatus('arrived'),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: C.success,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text("I've arrived",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _stopHelping,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              border: Border.all(color: C.accent),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('Stop helping',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: C.accent,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: C.accent, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: C.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        Text(label, style: TextStyle(color: C.textMuted, fontSize: 10)),
      ],
    );
  }
}
