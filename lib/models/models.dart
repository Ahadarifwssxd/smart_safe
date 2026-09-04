import 'package:flutter/material.dart';
import '../theme/colors.dart';

// ── Contact ──────────────────────────────────────────────────
class Contact {
  final String id, name, phone, role;
  final String? email;
  final Color color;
  final bool isOnline, smsAlert, pushAlert, callAlert;
  const Contact(
      {required this.id,
      required this.name,
      required this.phone,
      required this.role,
      this.email,
      required this.color,
      this.isOnline = true,
      this.smsAlert = true,
      this.pushAlert = true,
      this.callAlert = true});
  String get initial => name[0].toUpperCase();
  static String? _firstLetter(String value) {
    for (final match in RegExp(r'[A-Za-z]').allMatches(value)) {
      return match.group(0)!.toUpperCase();
    }
    return null;
  }

  String get initials {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final parts =
        clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final a = _firstLetter(parts[0]);
      final b = _firstLetter(parts[1]);
      if (a != null && b != null) return '$a$b';
    }
    return _firstLetter(clean) ?? '?';
  }

  String get displayFirstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '?' : parts.first;
  }

  Color get avatarColor => color;
  String get relation => role;
  bool get smsEnabled => smsAlert;
  bool get pushEnabled => pushAlert;
}

// ── Alert History ────────────────────────────────────────────
enum AlertType { sos, crash, safe, gps, contact, route }

class AlertEvent {
  final String title, location;
  final DateTime time;
  final AlertType type;
  final String? note;
  const AlertEvent(
      {required this.title,
      required this.location,
      required this.time,
      required this.type,
      this.note});

  Color get color {
    switch (type) {
      case AlertType.sos:
        return C.accent;
      case AlertType.crash:
        return C.warning;
      case AlertType.safe:
        return C.success;
      case AlertType.gps:
        return C.accent;
      case AlertType.contact:
        return C.accent;
      case AlertType.route:
        return C.success;
    }
  }

  String get label {
    switch (type) {
      case AlertType.sos:
        return 'SOS';
      case AlertType.crash:
        return 'Crash';
      case AlertType.safe:
        return 'Safe';
      case AlertType.gps:
        return 'GPS';
      case AlertType.contact:
        return 'Circle';
      case AlertType.route:
        return 'Route';
    }
  }

  IconData get icon {
    switch (type) {
      case AlertType.sos:
        return Icons.warning_amber_rounded;
      case AlertType.crash:
        return Icons.car_crash_rounded;
      case AlertType.safe:
        return Icons.check_circle_rounded;
      case AlertType.gps:
        return Icons.location_on_rounded;
      case AlertType.contact:
        return Icons.person_add_rounded;
      case AlertType.route:
        return Icons.route_rounded;
    }
  }
}

// ── Notification ─────────────────────────────────────────────
class AppNotif {
  final String? id;
  final String title, body;
  final DateTime time;
  final AlertType type;
  final bool isRead;
  AppNotif({
    this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.type,
    this.isRead = false,
  });
  Color get color =>
      AlertEvent(title: '', location: '', time: time, type: type).color;
  IconData get icon =>
      AlertEvent(title: '', location: '', time: time, type: type).icon;
}

// ── Route Segment ─────────────────────────────────────────────
enum SafetyLevel { safe, caution, avoid }

class RouteSegment {
  final String name, detail;
  final SafetyLevel level;
  final int minutes;
  const RouteSegment(
      {required this.name,
      required this.detail,
      required this.level,
      required this.minutes});
  Color get color {
    switch (level) {
      case SafetyLevel.safe:
        return C.success;
      case SafetyLevel.caution:
        return C.warning;
      case SafetyLevel.avoid:
        return C.accent;
    }
  }

  String get levelText {
    switch (level) {
      case SafetyLevel.safe:
        return 'Safe';
      case SafetyLevel.caution:
        return 'Caution';
      case SafetyLevel.avoid:
        return 'Avoid';
    }
  }
}

final List<RouteSegment> demoRoutes = [
  const RouteSegment(
      name: 'MA Jinnah Road',
      detail: 'Well-lit, high traffic area',
      level: SafetyLevel.safe,
      minutes: 12),
  const RouteSegment(
      name: 'Shahrah-e-Faisal',
      detail: 'Moderate traffic, busy at night',
      level: SafetyLevel.caution,
      minutes: 18),
  const RouteSegment(
      name: 'Lyari Expressway',
      detail: 'High crime reported after 10pm',
      level: SafetyLevel.avoid,
      minutes: 9),
];

// ── Safety Tip ────────────────────────────────────────────────
class SafetyTip {
  final String title, body, emoji;
  final Color color;
  const SafetyTip(
      {required this.title,
      required this.body,
      required this.emoji,
      required this.color});

  IconData get icon {
    switch (emoji) {
      case '🌙':
        return Icons.nightlight_round;
      case '📱':
        return Icons.phone_android_rounded;
      case '🚗':
        return Icons.directions_car_rounded;
      case '👥':
        return Icons.people_rounded;
      case '📍':
        return Icons.my_location_rounded;
      case '🔋':
        return Icons.battery_charging_full_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }
}

typedef AppNotification = AppNotif;

class RouteOption {
  final String name, safety, reason, distance, duration;
  final Color color;
  const RouteOption({
    required this.name,
    required this.safety,
    required this.reason,
    required this.distance,
    required this.duration,
    required this.color,
  });
}

