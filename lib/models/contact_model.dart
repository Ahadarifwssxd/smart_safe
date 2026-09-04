import 'package:flutter/material.dart';

class Contact {
  final String id, name, phone, role;
  final Color color;
  final bool isOnline, smsAlert, pushAlert, callAlert;

  const Contact({
    this.id = '',
    required this.name,
    this.phone = '',
    required this.role,
    required this.color,
    this.isOnline = true,
    this.smsAlert = true,
    this.pushAlert = true,
    this.callAlert = true,
  });

  String get initial => name[0].toUpperCase();
  String get initials {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean[0].toUpperCase();
  }

  Color get avatarColor => color;
  String get relation => role;
  bool get smsEnabled => smsAlert;
  bool get pushEnabled => pushAlert;
}
