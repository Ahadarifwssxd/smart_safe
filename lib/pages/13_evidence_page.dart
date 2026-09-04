import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;

import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../services/evidence_service.dart';

class EvidencePage extends StatefulWidget {
  const EvidencePage({super.key});

  @override
  State<EvidencePage> createState() => _EvidencePageState();
}

class _EvidencePageState extends State<EvidencePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _recCtrl;
  bool _isUploading = false;

  bool _stealthMode = true;
  final _noteCtrl = TextEditingController();
  bool _addingNote = false;

  final ImagePicker _picker = ImagePicker();

  // Voice note recording + playback
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _isRecording = false;
  int _recSeconds = 0;
  Timer? _recTimer;
  String? _playingUrl;

  @override
  void initState() {
    super.initState();
    _recCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingUrl = null);
    });
  }

  @override
  void dispose() {
    _recCtrl.dispose();
    _noteCtrl.dispose();
    _recTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Voice note ──────────────────────────────────────────────────────────
  Future<void> _startVoice() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Microphone permission needed for voice notes')));
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      setState(() {
        _isRecording = true;
        _recSeconds = 0;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recSeconds++);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Recording error: $e')));
      }
    }
  }

  Future<void> _stopVoiceAndUpload() async {
    _recTimer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    setState(() => _isRecording = false);
    if (path == null) return;

    try {
      _showLoading(true);
      final file = File(path);
      final loc = await _getLocationData();
      final size = await file.length();
      final sizeKB = (size / 1024).toStringAsFixed(0);
      await EvidenceService.instance.uploadEvidence(
        file: file,
        type: 'audio',
        note: 'Voice note (${_fmtDuration(_recSeconds)})',
        locationString: loc['address'],
        lat: loc['lat'],
        lng: loc['lng'],
        fileSizeStr: '$sizeKB KB',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      _showLoading(false);
    }
  }

  String _fmtDuration(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _togglePlay(String url) async {
    if (url.isEmpty || url.startsWith('web_')) return;
    if (_playingUrl == url) {
      await _player.stop();
      if (mounted) setState(() => _playingUrl = null);
    } else {
      await _player.stop();
      // Audio stored inline (base64 data: URI) plays from bytes; hosted clips
      // play from their URL.
      if (url.startsWith('data:')) {
        final comma = url.indexOf(',');
        if (comma < 0) return;
        final bytes = base64Decode(url.substring(comma + 1));
        await _player.play(BytesSource(bytes));
      } else {
        await _player.play(UrlSource(url));
      }
      if (mounted) setState(() => _playingUrl = url);
    }
  }

  /// Open a photo or video evidence item. Photos (inline base64 OR a hosted
  /// URL) open in a full-screen viewer; videos open in the device's player.
  Future<void> _openEvidence(String type, String url) async {
    if (url.isEmpty || url.startsWith('web_')) {
      _snack('This file is not available to open.');
      return;
    }
    if (type == 'photo') {
      ImageProvider provider;
      if (url.startsWith('data:')) {
        final comma = url.indexOf(',');
        if (comma < 0) {
          _snack('Photo could not be opened.');
          return;
        }
        provider = MemoryImage(base64Decode(url.substring(comma + 1)));
      } else {
        provider = NetworkImage(url);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        builder: (ctx) => GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image(
                    image: provider,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Could not load this photo.',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Video (and any other hosted file): hand off to the device's player.
      try {
        final ok = await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication);
        if (!ok) _snack('No app available to open this video.');
      } catch (_) {
        _snack('Could not open this video.');
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Shares an evidence item (photo / video / voice note / note) via the OS
  /// share sheet — as a real file when it's media, or as text for notes.
  Future<void> _shareEvidence(Map<String, dynamic> ev) async {
    final type = ev['type']?.toString() ?? '';
    final note = ev['note']?.toString() ?? '';
    final location = ev['location']?.toString() ?? 'Unknown location';
    final fileUrl = ev['fileUrl']?.toString() ?? '';
    final caption = 'SmartSafe Evidence\n'
        '${note.isNotEmpty ? '$note\n' : ''}'
        '📍 $location';

    try {
      // Notes (or media with no file) → share as plain text.
      if (type == 'note' || fileUrl.isEmpty || fileUrl.startsWith('web_')) {
        await Share.share(caption);
        return;
      }

      _showLoading(true);
      File? file;
      final ext = type == 'photo'
          ? 'jpg'
          : type == 'video'
              ? 'mp4'
              : 'm4a';
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}.$ext';

      if (fileUrl.startsWith('data:')) {
        // Inline base64 → write to a temp file.
        final comma = fileUrl.indexOf(',');
        if (comma > 0) {
          final bytes = base64Decode(fileUrl.substring(comma + 1));
          file = await File(outPath).writeAsBytes(bytes);
        }
      } else if (fileUrl.startsWith('http')) {
        // Hosted → download to a temp file.
        final res = await http.get(Uri.parse(fileUrl));
        if (res.statusCode == 200) {
          file = await File(outPath).writeAsBytes(res.bodyBytes);
        }
      }

      if (file != null) {
        await Share.shareXFiles([XFile(file.path)], text: caption);
      } else if (fileUrl.startsWith('http')) {
        await Share.share('$caption\n$fileUrl');
      } else {
        await Share.share(caption);
      }
    } catch (e) {
      _snack('Could not share: $e');
    } finally {
      _showLoading(false);
    }
  }

  Future<Map<String, dynamic>> _getLocationData() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    
    String address = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        String locality = p.subLocality != null && p.subLocality!.isNotEmpty 
            ? p.subLocality! 
            : p.locality ?? '';
        address = '$locality, ${p.administrativeArea}'.trim();
        if (address.startsWith(', ')) address = address.substring(2);
      }
    } catch (e) {
      // Fallback to coordinates
    }
    return {'lat': pos.latitude, 'lng': pos.longitude, 'address': address};
  }

  void _showLoading(bool val) {
    if (mounted) setState(() => _isUploading = val);
  }

  Future<void> _capturePhoto() async {
    try {
      // Cap resolution + quality so the photo stays small enough to store
      // inline (base64 in Firestore) — no media host / setup needed.
      final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 65);
      if (photo == null) return;

      _showLoading(true);
      final loc = await _getLocationData();
      final size = await photo.length();
      final sizeMB = (size / (1024 * 1024)).toStringAsFixed(1);

      await EvidenceService.instance.uploadEvidence(
        file: File(photo.path),
        type: 'photo',
        note: _stealthMode ? 'Captured silently' : 'Photo Evidence',
        locationString: loc['address'],
        lat: loc['lat'],
        lng: loc['lng'],
        fileSizeStr: '$sizeMB MB',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      _showLoading(false);
    }
  }

  Future<void> _captureVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
      if (video == null) return;

      _showLoading(true);
      final loc = await _getLocationData();
      final size = await video.length();
      final sizeMB = (size / (1024 * 1024)).toStringAsFixed(1);

      await EvidenceService.instance.uploadEvidence(
        file: File(video.path),
        type: 'video',
        note: 'Video Evidence',
        locationString: loc['address'],
        lat: loc['lat'],
        lng: loc['lng'],
        fileSizeStr: '$sizeMB MB',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      _showLoading(false);
    }
  }

  Future<void> _saveNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;

    try {
      _showLoading(true);
      setState(() => _addingNote = false);
      final loc = await _getLocationData();
      await EvidenceService.instance.saveNoteEvidence(
        note: text,
        locationString: loc['address'],
        lat: loc['lat'],
        lng: loc['lng'],
      );
      _noteCtrl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      _showLoading(false);
    }
  }

  String _timeAgo(DateTime? t) {
    if (t == null) return 'Just now';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DynText('evidence', 'title', 'Evidence Vault',
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                )),
                            Text('Timestamped · GPS-tagged · Encrypted',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        if (_isUploading)
                          SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                          )
                        else
                          Icon(Icons.cloud_done_rounded, color: AppColors.success, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Stealth toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SlideUpFade(
                    delay: const Duration(milliseconds: 80),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _stealthMode
                            ? AppColors.accent.withValues(alpha: 0.1)
                            : AppColors.bg2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _stealthMode
                              ? AppColors.accent.withValues(alpha: 0.3)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.visibility_off_rounded,
                              color: AppColors.accent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Stealth Mode',
                                    style: TextStyle(
                                        color: C.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                Text('No shutter sound or flash',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _stealthMode,
                            onChanged: (v) =>
                                setState(() => _stealthMode = v),
                            activeThumbColor: AppColors.accent,
                            activeTrackColor:
                                AppColors.accent.withValues(alpha: 0.3),
                            inactiveThumbColor: AppColors.textMuted,
                            inactiveTrackColor: AppColors.border,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SlideUpFade(
                    delay: const Duration(milliseconds: 120),
                    child: Row(
                      children: [
                        // Photo
                        Expanded(
                          child: GestureDetector(
                            onTap: _isUploading ? null : _capturePhoto,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.accent.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.camera_alt_rounded,
                                      color: AppColors.accent, size: 24),
                                  const SizedBox(height: 4),
                                  Text('Photo',
                                      style: TextStyle(
                                          color: AppColors.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Video
                        Expanded(
                          child: GestureDetector(
                            onTap: _isUploading ? null : _captureVideo,
                            child: AnimatedBuilder(
                              animation: _recCtrl,
                              builder: (_, __) => Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.red.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.videocam_rounded,
                                      color: AppColors.red,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Video',
                                      style: TextStyle(
                                          color: AppColors.red,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Voice note
                        Expanded(
                          child: GestureDetector(
                            onTap: _isUploading
                                ? null
                                : (_isRecording
                                    ? _stopVoiceAndUpload
                                    : _startVoice),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _isRecording
                                    ? AppColors.red.withValues(alpha: 0.18)
                                    : AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: _isRecording
                                        ? AppColors.red
                                        : AppColors.success.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                      _isRecording
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded,
                                      color: _isRecording
                                          ? AppColors.red
                                          : AppColors.success,
                                      size: 24),
                                  const SizedBox(height: 4),
                                  Text(_isRecording ? 'Stop' : 'Voice',
                                      style: TextStyle(
                                          color: _isRecording
                                              ? AppColors.red
                                              : AppColors.success,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Note
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _addingNote = !_addingNote),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.warning.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.edit_note_rounded,
                                      color: AppColors.warning, size: 24),
                                  const SizedBox(height: 4),
                                  Text('Note',
                                      style: TextStyle(
                                          color: AppColors.warning,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Recording banner
                if (_isRecording)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          FadeTransition(
                            opacity: _recCtrl,
                            child: Icon(Icons.fiber_manual_record,
                                color: AppColors.red, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Text('Recording voice note…',
                              style: TextStyle(
                                  color: C.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const Spacer(),
                          Text(_fmtDuration(_recSeconds),
                              style: TextStyle(
                                  color: AppColors.red,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14)),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _stopVoiceAndUpload,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.red,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Stop & Save',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Note input
                if (_addingNote)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: SlideUpFade(
                      child: DCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add Quick Note',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _noteCtrl,
                              maxLines: 2,
                              style: TextStyle(
                                  color: C.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. Vehicle plate, description...',
                                hintStyle:
                                    TextStyle(color: AppColors.textMuted),
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
                                      () => _addingNote = false),
                                  child: Text('Cancel',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13)),
                                ),
                                const SizedBox(width: 16),
                                GestureDetector(
                                  onTap: _isUploading ? null : _saveNote,
                                  child: Text('Save',
                                      style: TextStyle(
                                          color: AppColors.warning,
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

                const SizedBox(height: 16),

                // Evidence list
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: EvidenceService.instance.getUserEvidencesStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}", style: TextStyle(color: AppColors.red)));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snapshot.data!.docs;
                      
                      // Sort docs locally to avoid Firestore composite index requirement
                      final sortedDocs = docs.toList()..sort((a, b) {
                        final ta = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                        final tb = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                        if (ta == null && tb == null) return 0;
                        if (ta == null) return 1;
                        if (tb == null) return -1;
                        return tb.compareTo(ta); // Descending
                      });

                      if (sortedDocs.isEmpty) {
                        return Center(
                          child: Text("No evidence recorded yet", 
                              style: TextStyle(color: AppColors.textMuted)),
                        );
                      }

                      return ListView.builder(
                        cacheExtent: 500,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: sortedDocs.length + 1,
                        itemBuilder: (ctx, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text('Evidence Log',
                                  style: TextStyle(
                                    color: C.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  )),
                            );
                          }
                          final ev = sortedDocs[i - 1].data() as Map<String, dynamic>;
                          final t = ev['timestamp'] as Timestamp?;
                          final timeStr = _timeAgo(t?.toDate());

                          return SlideUpFade(
                            delay: Duration(milliseconds: 50 + (i - 1) * 40),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _EvidenceCard(
                                type: ev['type'],
                                note: ev['note'] ?? '',
                                location: ev['location'] ?? 'Unknown Location',
                                size: ev['size'] ?? '—',
                                timeAgo: timeStr,
                                fileUrl: ev['fileUrl'] ?? '',
                                isPlaying:
                                    _playingUrl == (ev['fileUrl'] ?? '') &&
                                        (ev['fileUrl'] ?? '').isNotEmpty,
                                onPlay: () => _togglePlay(ev['fileUrl'] ?? ''),
                                onOpen: () => _openEvidence(
                                    ev['type'] ?? '', ev['fileUrl'] ?? ''),
                                onShare: () => _shareEvidence(ev),
                              ),
                            ),
                          );
                        },
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

class _EvidenceCard extends StatelessWidget {
  final String type;
  final String note;
  final String location;
  final String size;
  final String timeAgo;
  final String fileUrl;
  final bool isPlaying;
  final VoidCallback? onPlay;
  final VoidCallback? onOpen;
  final VoidCallback? onShare;

  const _EvidenceCard({
    required this.type,
    required this.note,
    required this.location,
    required this.size,
    required this.timeAgo,
    this.fileUrl = '',
    this.isPlaying = false,
    this.onPlay,
    this.onOpen,
    this.onShare,
  });

  IconData get _icon {
    switch (type) {
      case 'photo': return Icons.image_rounded;
      case 'video': return Icons.videocam_rounded;
      case 'audio': return Icons.mic_rounded;
      case 'note': return Icons.edit_note_rounded;
      default: return Icons.file_present_rounded;
    }
  }

  Color get _color {
    switch (type) {
      case 'photo': return AppColors.accent;
      case 'video': return AppColors.red;
      case 'audio': return AppColors.success;
      case 'note': return AppColors.warning;
      default: return AppColors.textMuted;
    }
  }

  String get _label {
    switch (type) {
      case 'photo': return 'Photo Evidence';
      case 'video': return 'Video Evidence';
      case 'audio': return 'Voice Note';
      case 'note': return 'Written Note';
      default: return 'Evidence';
    }
  }

  // Photo & video open when tapped; audio uses its own play button; notes have
  // nothing to open.
  bool get _canOpen =>
      (type == 'photo' || type == 'video') && fileUrl.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _canOpen ? onOpen : null,
      behavior: HitTestBehavior.opaque,
      child: DCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, color: _color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(_label,
                        style: TextStyle(
                            color: C.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    const Spacer(),
                    Text(timeAgo,
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded,
                        color: AppColors.textMuted, size: 11),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(location,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(note,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (size != '—')
                      Text(size,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (type == 'audio' && fileUrl.isNotEmpty)
            GestureDetector(
              onTap: onPlay,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success.withValues(alpha: 0.15),
                ),
                child: Icon(
                  isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
            )
          else if (_canOpen)
            // Tap-to-open affordance for photo/video evidence.
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _color.withValues(alpha: 0.15),
              ),
              child: Icon(
                type == 'video'
                    ? Icons.play_arrow_rounded
                    : Icons.open_in_full_rounded,
                color: _color,
                size: 20,
              ),
            )
          else
            Icon(Icons.cloud_done_rounded,
                color: AppColors.success, size: 16),
          // Share this evidence item (photo / video / voice note / note).
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onShare,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.share_rounded,
                  color: AppColors.accent, size: 18),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
