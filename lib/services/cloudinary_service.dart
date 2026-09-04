import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Free, no-credit-card media storage via Cloudinary (25 GB free tier).
///
/// Replaces Firebase Storage — which now forces the paid Blaze plan just to
/// turn Storage on. Cloudinary's UNSIGNED upload lets the app upload directly
/// from the device with no server and no secret key, so nothing sensitive ships
/// in the APK.
///
/// ─────────────────────────────────────────────────────────────────────────
/// ONE-TIME SETUP (free, no card):
///   1. Sign up: https://cloudinary.com/users/register_free
///   2. Dashboard → copy your **Cloud name**.
///   3. Settings (⚙) → Upload → "Upload presets" → Add upload preset →
///      set **Signing Mode = Unsigned** → Save → copy the **preset name**.
///   4. Paste both into [cloudName] and [uploadPreset] below.
/// After that, chat photos, evidence, incident photos & avatars all upload for
/// free with zero backend.
/// ─────────────────────────────────────────────────────────────────────────
class CloudinaryService {
  CloudinaryService._();
  static final CloudinaryService instance = CloudinaryService._();

  // ⬇️⬇️ CLOUDINARY VALUES (cloud name + unsigned upload preset) ⬇️⬇️
  static const String cloudName = 'wbrmardd';
  static const String uploadPreset = 'smartsafe';
  // ⬆️⬆️ ───────────────────────────────────────────────────────── ⬆️⬆️

  /// True once real Cloudinary credentials have been pasted in.
  bool get isConfigured =>
      cloudName.trim().isNotEmpty && cloudName != 'YOUR_CLOUD_NAME';

  String _endpoint(String resourceType) =>
      'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload';

  /// Maps our logical media type to a Cloudinary resource type.
  /// Cloudinary stores audio under the "video" resource type.
  String _resourceType(String type) {
    switch (type) {
      case 'video':
      case 'audio':
        return 'video';
      case 'raw':
        return 'raw';
      default:
        return 'image';
    }
  }

  void _ensureConfigured() {
    if (!isConfigured) {
      throw Exception(
          'Media storage is not set up yet. Add your free Cloudinary cloud '
          'name and unsigned upload preset in cloudinary_service.dart.');
    }
  }

  /// Uploads a file from disk (mobile). Returns the hosted https URL.
  Future<String> uploadFile(File file,
      {String type = 'image', String folder = ''}) async {
    _ensureConfigured();
    final req = http.MultipartRequest(
        'POST', Uri.parse(_endpoint(_resourceType(type))))
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    if (folder.isNotEmpty) req.fields['folder'] = folder;
    return _send(req);
  }

  /// Stores an image with ZERO external setup: small images are kept inline as
  /// a base64 `data:` URI (saved straight into the Firestore document), so
  /// evidence photos and profile pictures work on every phone with no Cloudinary
  /// account needed. Larger images fall back to Cloudinary if it's configured.
  Future<String> storeImage(Uint8List bytes, {String folder = ''}) async {
    // Keep the whole Firestore doc comfortably under its 1 MB limit
    // (base64 inflates size ~33%, so ~700 KB raw → ~950 KB encoded).
    const int maxInlineBytes = 700 * 1024;
    if (bytes.length <= maxInlineBytes) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
    // Too big to inline — needs a media host.
    return uploadBytes(bytes, 'image.jpg', type: 'image', folder: folder);
  }

  /// Stores ANY small media (audio / video / image) with ZERO external setup by
  /// inlining it as a base64 `data:` URI (kept straight in the Firestore doc),
  /// so voice notes and the SOS auto-recording work on every phone with no
  /// Cloudinary account. Files above the inline limit fall back to Cloudinary
  /// (if configured). Used by evidence + SOS recordings.
  Future<String> storeMedia(Uint8List bytes,
      {required String type, String folder = ''}) async {
    // Stay comfortably under Firestore's 1 MB document limit (base64 ~+33%).
    const int maxInlineBytes = 700 * 1024;
    if (bytes.length <= maxInlineBytes) {
      final mime = type == 'audio'
          ? 'audio/mp4'
          : type == 'video'
              ? 'video/mp4'
              : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    }
    final ext = type == 'audio'
        ? 'm4a'
        : type == 'video'
            ? 'mp4'
            : 'jpg';
    return uploadBytes(bytes, 'file.$ext', type: type, folder: folder);
  }

  /// Uploads raw bytes (web images, or in-memory chat/avatar images).
  Future<String> uploadBytes(Uint8List bytes, String filename,
      {String type = 'image', String folder = ''}) async {
    _ensureConfigured();
    final req = http.MultipartRequest(
        'POST', Uri.parse(_endpoint(_resourceType(type))))
      ..fields['upload_preset'] = uploadPreset
      ..files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (folder.isNotEmpty) req.fields['folder'] = folder;
    return _send(req);
  }

  Future<String> _send(http.MultipartRequest req) async {
    final resp = await req.send().timeout(const Duration(seconds: 30));
    final body = await resp.stream.bytesToString();
    if (resp.statusCode == 200) {
      final data = json.decode(body) as Map<String, dynamic>;
      final url = data['secure_url']?.toString();
      if (url != null && url.isNotEmpty) return url;
      throw Exception('Cloudinary returned no URL: $body');
    }
    // A 401 "Unknown API key" almost always means the upload preset is still in
    // "Signed" mode (or unsigned uploads are disabled) — the app uploads
    // unsigned. Give an actionable message instead of the raw Cloudinary error.
    if (resp.statusCode == 401 || body.contains('Unknown API key')) {
      throw Exception(
          'Media upload is not enabled yet. In your Cloudinary dashboard open '
          'Settings → Upload → the "$uploadPreset" preset and set '
          'Signing Mode = Unsigned (and enable unsigned uploading under '
          'Settings → Security). Then photos, evidence and avatars will upload.');
    }
    throw Exception('Cloudinary upload failed (${resp.statusCode}): $body');
  }
}
