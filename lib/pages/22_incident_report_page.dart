import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../services/app_firestore_service.dart';
import '../services/cloudinary_service.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../widgets/widgets.dart';

class IncidentReportPage extends StatefulWidget {
  const IncidentReportPage({super.key});
  @override State<IncidentReportPage> createState() => _IncidentReportPageState();
}

class _IncidentReportPageState extends State<IncidentReportPage> {
  final _descCtrl = TextEditingController();
  String _type = 'Harassment';
  bool _anonymous = false;
  bool _submitted = false;
  bool _saving = false;
  File? _photo;

  String _locationStr = 'Locating…';
  /// Real GPS coordinates of the report, saved alongside the address so the map
  /// and the dashboard can plot it exactly.
  double? _lat;
  double? _lng;
  late final String _nowStr;

  final _types = ['Harassment', 'Stalking', 'Theft', 'Assault', 'Road Accident', 'Other'];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h12 = n.hour % 12 == 0 ? 12 : n.hour % 12;
    _nowStr = '${months[n.month - 1]} ${n.day}, ${n.year} · '
        '${h12.toString()}:${n.minute.toString().padLeft(2, '0')} ${n.hour < 12 ? 'AM' : 'PM'}';
    _captureLocation();
  }

  @override
  void dispose() { _descCtrl.dispose(); super.dispose(); }

  Future<void> _captureLocation() async {
    if (mounted) setState(() => _locationStr = 'Locating…');
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _locationStr = 'Turn on GPS/Location, then tap to retry');
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationStr = 'Location permission denied');
        return;
      }

      // Fresh high-accuracy fix, but never hang — fall back to the last known
      // position if the GPS is slow.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high)
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        if (mounted) {
          setState(() => _locationStr = 'Location unavailable — tap to retry');
        }
        return;
      }
      final p0 = pos;

      // Street-level address so the report shows the ACTUAL live spot, not just
      // the city area.
      String addr =
          '${p0.latitude.toStringAsFixed(5)}, ${p0.longitude.toStringAsFixed(5)}';
      try {
        final pm = await placemarkFromCoordinates(p0.latitude, p0.longitude);
        if (pm.isNotEmpty) {
          final p = pm.first;
          final parts = <String>[];
          for (final e in [
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ]) {
            final v = (e ?? '').trim();
            // Skip Google "Plus Codes" (e.g. "W23R+FH") — they're unreadable to
            // other users; keep only real place names so the location is clear.
            if (v.isNotEmpty && !parts.contains(v) && !_isPlusCode(v)) {
              parts.add(v);
            }
          }
          if (parts.isNotEmpty) addr = parts.join(', ');
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _lat = p0.latitude;
          _lng = p0.longitude;
          _locationStr = '$addr (GPS)';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _locationStr = 'Location unavailable — tap to retry');
      }
    }
  }

  // A Google Plus Code looks like "W23R+FH" — unreadable as a place name.
  bool _isPlusCode(String s) =>
      RegExp(r'^[A-Z0-9]{4,}\+[A-Z0-9]{2,}$').hasMatch(s.replaceAll(' ', ''));

  /// Opens a report's photo full-screen (pinch-to-zoom) in an overlay.
  void _openImage(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (c, child, p) => p == null
                      ? child
                      : Center(
                          child: CircularProgressIndicator(color: C.accent)),
                  errorBuilder: (c, e, s) => Center(
                    child: Text('Could not load image',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: C.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.photo_camera_rounded, color: C.accent),
            title: Text('Take a photo', style: TextStyle(color: C.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_rounded, color: C.accent),
            title: Text('Choose from gallery', style: TextStyle(color: C.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source, maxWidth: 1600, imageQuality: 80);
      if (picked != null && mounted) {
        setState(() => _photo = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: C.accent, behavior: SnackBarBehavior.floating,
          content: Text('Could not pick photo: $e', style: TextStyle(color: C.textPrimary))));
      }
    }
  }

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: C.accent, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text('Please describe the incident', style: TextStyle(color: C.textPrimary))));
      return;
    }
    setState(() => _saving = true);
    try {
      String? photoUrl;
      if (_photo != null) {
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
          // Free media storage via Cloudinary (no Firebase Storage / Blaze).
          photoUrl = await CloudinaryService.instance.uploadFile(
            _photo!,
            type: 'image',
            folder: 'incident_photos/$uid',
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: C.warning, behavior: SnackBarBehavior.floating,
              content: Text('Photo upload failed — submitting report without it.',
                  style: TextStyle(color: C.textPrimary))));
          }
        }
      }
      await AppFirestoreService.instance.addIncidentReport(
        incidentType: _type,
        description: _descCtrl.text.trim(),
        location: _locationStr.replaceAll(' (GPS)', ''),
        status: 'Submitted',
        photoUrl: photoUrl,
        latitude: _lat,
        longitude: _lng,
      );
      // Clear the form after a successful submit so the description (and photo)
      // don't reappear when the user returns to file another report.
      if (mounted) {
        setState(() {
          _saving = false;
          _submitted = true;
          _descCtrl.clear();
          _photo = null;
          _type = 'Harassment';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: C.accent, behavior: SnackBarBehavior.floating,
          content: Text('Could not submit: $e', style: TextStyle(color: C.textPrimary))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: Stack(children: [
      const DotGrid(),
      SafeArea(child: SingleChildScrollView(
      padding: responsiveScrollPadding(context, horizontal: 20, vertical: 8),
      child: _submitted ? _SuccessView() : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Standard app header (matches the rest of the app)
        SlideUpFade(child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Row(children: [
            if (Navigator.canPop(context)) ...[
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DynText('incident_report', 'title', 'Report an Incident',
                    style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('Encrypted · GPS-tagged · sent to the control room',
                    style: TextStyle(color: C.textMuted, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        )),

        DCard(borderColor: C.accent, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(Icons.lock_rounded, color: C.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Your report is encrypted & confidential. Only shared with authorities if you choose.',
              style: TextStyle(color: C.textMuted, fontSize: 11))),
          ])),

        const SizedBox(height: 24),

        // Auto-captured info
        const SecHeader('Auto-captured details', icon: Icons.my_location_rounded),
        DCard(borderColor: C.accent, child: Column(children: [
          GestureDetector(
            onTap: _captureLocation, // tap to refresh / retry the live location
            behavior: HitTestBehavior.opaque,
            child: _AutoRow(
                icon: Icons.location_on_rounded,
                color: C.accent,
                label: 'Location',
                value: _locationStr),
          ),
          Divider(color: C.border, height: 16),
          _AutoRow(icon: Icons.access_time_rounded, color: C.accent, label: 'Date & Time', value: _nowStr),
          Divider(color: C.border, height: 16),
          _AutoRow(icon: Icons.cloud_upload_rounded, color: C.accent, label: 'Saved to', value: 'SmartSafe cloud'),
        ])),

        const SizedBox(height: 24),

        // Incident type
        const SecHeader('Incident type'),
        Wrap(spacing: 8, runSpacing: 8, children: _types.map((t) {
          final sel = t == _type;
          return GestureDetector(onTap: () => setState(() => _type = t),
            child: AnimatedContainer(duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: sel ? C.accent : C.bg2, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? C.accent : C.textDim)),
              child: Text(t, style: TextStyle(color: sel ? Colors.white : C.textMuted, fontSize: 12,
                fontWeight: sel ? FontWeight.w700 : FontWeight.normal))));
        }).toList()),

        const SizedBox(height: 24),

        // Description
        const SecHeader('Describe what happened'),
        TextField(controller: _descCtrl, maxLines: 5, maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Describe the incident in detail — what happened, who was involved, what they looked like...',
            alignLabelWithHint: true),
          style: TextStyle(color: C.textPrimary, fontSize: 13)),

        const SizedBox(height: 16),

        // Photo evidence
        const SecHeader('Add photo evidence (optional)', icon: Icons.photo_camera_rounded),
        _photo == null
          ? GestureDetector(onTap: _pickPhoto,
              child: Container(height: 80, width: double.infinity,
                decoration: BoxDecoration(color: C.bg2, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: C.textDim, style: BorderStyle.solid)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_rounded, color: C.textMuted, size: 28),
                  const SizedBox(height: 4),
                  Text('Tap to add photo', style: TextStyle(color: C.textMuted, fontSize: 12)),
                ])))
          : ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Stack(children: [
                Image.file(_photo!, height: 160, width: double.infinity, fit: BoxFit.cover),
                Positioned(top: 8, right: 8, child: Row(children: [
                  GestureDetector(onTap: _pickPhoto,
                    child: Container(padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18))),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => setState(() => _photo = null),
                    child: Container(padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18))),
                ])),
              ])),

        const SizedBox(height: 16),

        // Anonymous toggle
        DCard(child: TRow(
          label: 'Submit anonymously',
          sub: 'Your name won\'t be shared with authorities',
          value: _anonymous,
          onChanged: (v) => setState(() => _anonymous = v))),

        const SizedBox(height: 24),

        // Share options
        const SecHeader('Share with'),
        Row(children: [
          _ShareOpt(icon: Icons.security_rounded, label: 'Police', color: C.accent, selected: true),
          const SizedBox(width: 8),
          _ShareOpt(icon: Icons.group_rounded, label: 'SmartSafe Community', color: C.accent, selected: true),
          const SizedBox(width: 8),
          _ShareOpt(icon: Icons.person_rounded, label: 'Only me', color: C.textMuted, selected: false),
        ]),

        const SizedBox(height: 24),
        BigBtn(
          label: _saving ? 'Submitting…' : 'Submit Report',
          icon: Icons.upload_rounded,
          color: C.accent,
          onTap: _saving ? () {} : _submit,
        ),

        const SizedBox(height: 24),

        // Past reports — LIVE from Firestore (this user's reports)
        const SecHeader('Your past reports'),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: AppFirestoreService.instance.watchIncidentReports(),
          builder: (context, snap) {
            final myUid = FirebaseAuth.instance.currentUser?.uid;
            final all = (snap.data ?? [])
                .where((r) => r['userId'] == myUid)
                .toList();
            // Only APPROVED reports appear here — a report stays out of the app
            // until an admin approves it from the dashboard (same as danger
            // zones). Legacy reports with no moderationStatus count as approved.
            String mod(Map<String, dynamic> r) =>
                (r['moderationStatus']?.toString() ?? 'approved');
            final mine = all.where((r) => mod(r) == 'approved').toList();
            final pendingCount =
                all.where((r) => mod(r) == 'pending').length;

            if (mine.isEmpty && pendingCount == 0) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No reports yet — approved reports will appear here.',
                    style: TextStyle(color: C.textMuted, fontSize: 12)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pendingCount > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: C.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: C.warning.withValues(alpha: 0.35)),
                    ),
                    child: Row(children: [
                      Icon(Icons.hourglass_top_rounded,
                          color: C.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$pendingCount report${pendingCount == 1 ? '' : 's'} awaiting admin approval — will appear once approved.',
                          style: TextStyle(color: C.warning, fontSize: 11.5),
                        ),
                      ),
                    ]),
                  ),
                ...mine.map((r) {
                  final photoUrl = r['photoUrl']?.toString() ?? '';
                  final hasPhoto = photoUrl.isNotEmpty;
                  final loc = (r['location']?.toString() ?? '').trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DCard(
                      onTap: hasPhoto ? () => _openImage(photoUrl) : null,
                      child: Row(children: [
                        // Photo thumbnail (tap to open) or a document icon.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: hasPhoto
                              ? Image.network(photoUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(
                                        width: 44,
                                        height: 44,
                                        color: C.accent.withValues(alpha: .15),
                                        child: Icon(Icons.broken_image_rounded,
                                            color: C.textMuted, size: 20),
                                      ))
                              : Container(
                                  width: 44,
                                  height: 44,
                                  color: C.accent.withValues(alpha: .15),
                                  child: Icon(Icons.description_rounded,
                                      color: C.textMuted, size: 20),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(
                                      r['incidentType']?.toString() ??
                                          'Incident',
                                      style: TextStyle(
                                          color: C.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (hasPhoto)
                                  Icon(Icons.image_rounded,
                                      color: C.accent, size: 15),
                              ]),
                              const SizedBox(height: 2),
                              Text(r['time']?.toString() ?? '',
                                  style: TextStyle(
                                      color: C.textMuted, fontSize: 10)),
                              if (loc.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.place_rounded,
                                          color: C.accent, size: 12),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(loc,
                                            style: TextStyle(
                                                color: C.textMuted,
                                                fontSize: 11),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(label: 'Approved', color: C.success),
                      ]),
                    ),
                  );
                }),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
      ])),
    ),
    ]),
  );

  Widget _SuccessView() => Center(child: Padding(padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(height: 60),
      Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, color: C.success.withValues(alpha: .15)),
        child: Icon(Icons.check_circle_rounded, color: C.success, size: 56)),
      const SizedBox(height: 24),
      Text('Report Sent for Review', style: TextStyle(color: C.textPrimary, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
      const SizedBox(height: 12),
      Text('Your report has been recorded with GPS location and timestamp, and sent to the SmartSafe team. Once a moderator approves it, it will appear in the community Safety Feed.',
        style: TextStyle(color: C.textMuted, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
      const SizedBox(height: 32),
      BigBtn(label: 'Back to Safety', color: C.accent, onTap: () => setState(() => _submitted = false)),
    ])));
}

class _AutoRow extends StatelessWidget {
  final IconData icon; final Color color; final String label, value;
  const _AutoRow({required this.icon, required this.color, required this.label, required this.value});
  @override Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 8),
    Text('$label:', style: TextStyle(color: C.textMuted, fontSize: 12)),
    const SizedBox(width: 8),
    Expanded(child: Text(value, style: TextStyle(color: C.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
  ]);
}

class _ShareOpt extends StatelessWidget {
  final IconData icon; final String label; final Color color; final bool selected;
  const _ShareOpt({required this.icon, required this.label, required this.color, required this.selected});
  @override Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(color: selected ? color.withValues(alpha: .12) : C.bg2, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: selected ? color.withValues(alpha: .4) : C.textDim)),
    child: Column(children: [
      Icon(icon, color: selected ? color : C.textMuted, size: 20),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: selected ? color : C.textMuted, fontSize: 9, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
    ])));
}
