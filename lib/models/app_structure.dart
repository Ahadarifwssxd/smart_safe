import 'package:flutter/material.dart';

/// Folder = app drawer section / dashboard group (e.g. Crisis & SOS).
class AppSection {
  final String id;
  final String title;
  final int sortOrder;
  final bool enabled;
  /// app | dashboard | both
  final String context;

  const AppSection({
    required this.id,
    required this.title,
    this.sortOrder = 0,
    this.enabled = true,
    this.context = 'both',
  });

  factory AppSection.fromFirestore(String id, Map<String, dynamic> d) {
    return AppSection(
      id: id,
      title: d['title']?.toString() ?? 'Section',
      sortOrder: d['sortOrder'] as int? ?? 0,
      enabled: d['enabled'] != false,
      context: d['context']?.toString() ?? 'both',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'sortOrder': sortOrder,
        'enabled': enabled,
        'context': context,
        'updatedAt': DateTime.now().toIso8601String(),
      };
}

/// File/button inside a folder — label, button text, icon, route all editable.
class AppSectionItem {
  final String id;
  final String sectionId;
  final String label;
  final String subtitle;
  final String buttonText;
  final String iconName;
  final int colorHex;
  final String routeKey;
  final String itemType;
  final String dataSource;
  final int sortOrder;
  final bool enabled;
  final String context;

  const AppSectionItem({
    required this.id,
    required this.sectionId,
    required this.label,
    this.subtitle = '',
    this.buttonText = '',
    this.iconName = 'folder_rounded',
    this.colorHex = 0xFFE63946,
    this.routeKey = '',
    this.itemType = 'file',
    this.dataSource = '',
    this.sortOrder = 0,
    this.enabled = true,
    this.context = 'both',
  });

  factory AppSectionItem.fromFirestore(String id, Map<String, dynamic> d) {
    return AppSectionItem(
      id: id,
      sectionId: d['sectionId']?.toString() ?? '',
      label: d['label']?.toString() ?? '',
      subtitle: d['subtitle']?.toString() ?? '',
      buttonText: d['buttonText']?.toString() ?? '',
      iconName: d['iconName']?.toString() ?? 'folder_rounded',
      colorHex: d['colorHex'] as int? ?? 0xFFE63946,
      routeKey: d['routeKey']?.toString() ?? '',
      itemType: d['itemType']?.toString() ?? 'file',
      dataSource: d['dataSource']?.toString() ?? '',
      sortOrder: d['sortOrder'] as int? ?? 0,
      enabled: d['enabled'] != false,
      context: d['context']?.toString() ?? 'both',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'sectionId': sectionId,
        'label': label,
        'subtitle': subtitle,
        'buttonText': buttonText,
        'iconName': iconName,
        'colorHex': colorHex,
        'routeKey': routeKey,
        'itemType': itemType,
        'dataSource': dataSource,
        'sortOrder': sortOrder,
        'enabled': enabled,
        'context': context,
      };

  Color get color => Color(colorHex);
  IconData get icon => iconFromName(iconName);
}

IconData iconFromName(String name) {
  const map = <String, IconData>{
    'dashboard_rounded': Icons.dashboard_rounded,
    'warning_amber_rounded': Icons.warning_amber_rounded,
    'contact_phone_rounded': Icons.contact_phone_rounded,
    'dangerous_rounded': Icons.dangerous_rounded,
    'report_rounded': Icons.report_rounded,
    'people_alt_rounded': Icons.people_alt_rounded,
    'sos_rounded': Icons.sos_rounded,
    'notifications_rounded': Icons.notifications_rounded,
    'lightbulb_rounded': Icons.lightbulb_rounded,
    'settings_rounded': Icons.settings_rounded,
    'folder_rounded': Icons.folder_rounded,
    'groups_rounded': Icons.groups_rounded,
    'campaign_rounded': Icons.campaign_rounded,
    'female_rounded': Icons.female_rounded,
    'camera_alt_rounded': Icons.camera_alt_rounded,
    'phone_forwarded_rounded': Icons.phone_forwarded_rounded,
    'gavel_rounded': Icons.gavel_rounded,
    'map_rounded': Icons.map_rounded,
    'local_fire_department_rounded': Icons.local_fire_department_rounded,
    'timer_rounded': Icons.timer_rounded,
    'security_rounded': Icons.security_rounded,
    'car_crash_rounded': Icons.car_crash_rounded,
    'directions_car_rounded': Icons.directions_car_rounded,
    'child_care_rounded': Icons.child_care_rounded,
    'description_rounded': Icons.description_rounded,
    'healing_rounded': Icons.healing_rounded,
    'medical_services_rounded': Icons.medical_services_rounded,
    'air_rounded': Icons.air_rounded,
    'group_rounded': Icons.group_rounded,
    'shield_rounded': Icons.shield_rounded,
    'radar_rounded': Icons.radar_rounded,
    'history_rounded': Icons.history_rounded,
    'rss_feed_rounded': Icons.rss_feed_rounded,
    'location_on_rounded': Icons.location_on_rounded,
    'route_rounded': Icons.route_rounded,
    'tune_rounded': Icons.tune_rounded,
    'add_rounded': Icons.add_rounded,
    'auto_stories_rounded': Icons.auto_stories_rounded,
    // Women Safety prevention-tip icons.
    'share_location_rounded': Icons.share_location_rounded,
    'headphones_rounded': Icons.headphones_rounded,
    'light_mode_rounded': Icons.light_mode_rounded,
    'local_taxi_rounded': Icons.local_taxi_rounded,
    'phone_in_talk_rounded': Icons.phone_in_talk_rounded,
  };
  return map[name] ?? Icons.insert_drive_file_rounded;
}

const List<String> availableIconNames = [
  'folder_rounded',
  'dashboard_rounded',
  'warning_amber_rounded',
  'contact_phone_rounded',
  'dangerous_rounded',
  'report_rounded',
  'people_alt_rounded',
  'sos_rounded',
  'notifications_rounded',
  'lightbulb_rounded',
  'settings_rounded',
  'groups_rounded',
  'campaign_rounded',
  'female_rounded',
  'camera_alt_rounded',
  'phone_forwarded_rounded',
  'gavel_rounded',
  'map_rounded',
  'local_fire_department_rounded',
  'timer_rounded',
  'security_rounded',
  'car_crash_rounded',
  'directions_car_rounded',
  'child_care_rounded',
  'description_rounded',
  'healing_rounded',
  'medical_services_rounded',
  'air_rounded',
  'group_rounded',
  'shield_rounded',
  'radar_rounded',
  'history_rounded',
  'rss_feed_rounded',
  'location_on_rounded',
  'route_rounded',
  'tune_rounded',
  'add_rounded',
  'auto_stories_rounded',
];

/// Ensures [DropdownButton] value exists exactly once in [availableIconNames].
String normalizeIconName(String? name) {
  if (name != null && availableIconNames.contains(name)) return name;
  return availableIconNames.first;
}

const List<String> dashboardRouteKeys = [
  'dashboard',
  'alerts',
  'emergency_contacts',
  'danger_zones',
  'incident_reports',
  'users',
  'sos_activity',
  'notifications',
  'safety_tips',
  'panic_tools',
  'onboarding',
  'page_content',
  'app_feedback',
  'chatbot_faq',
  'app_structure',
  'settings',
];

const List<String> appRouteKeys = [
  'community_sos',
  'crisis_hub',
  'women_safety',
  'evidence',
  'emergency_dial',
  'emergency_will',
  'travel_hub',
  'danger_zone',
  'safe_checkin',
  'security_hub',
  'crash_detection',
  'driving_safety',
  'child_safety',
  'incident_report',
  'health_hub',
  'first_aid',
  'panic_breathe',
  'community_hub',
  'safety_score',
  'family_radar',
  'alert_history',
  'my_sos_history',
  'safety_feed',
  'live_gps',
  'safe_route',
  'panic_toolkit',
  'contacts_page',
];
