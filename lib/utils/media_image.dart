import 'dart:convert';
import 'package:flutter/material.dart';

/// Resolves a stored media URL to an [ImageProvider], transparently handling
/// both inline base64 `data:` URIs (our zero-setup image storage) and normal
/// https URLs. Returns null for empty/invalid values so callers can fall back
/// to initials/placeholders.
ImageProvider? mediaImageProvider(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('data:')) {
    try {
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      return MemoryImage(base64Decode(url.substring(comma + 1)));
    } catch (_) {
      return null;
    }
  }
  if (url.startsWith('http')) return NetworkImage(url);
  return null;
}
