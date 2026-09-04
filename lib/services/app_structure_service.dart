import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/models/app_structure.dart';

class AppStructureService {
  static final AppStructureService instance = AppStructureService._internal();
  AppStructureService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _sections =>
      _db.collection('app_sections');
  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('app_section_items');

  // Cached watch streams. watchSections/watchItems are called from build()
  // methods, so creating a fresh stream per call re-subscribed a new
  // Firestore listener on EVERY rebuild. `.snapshots()` is broadcast, so one
  // cached instance per argument-key safely serves every StreamBuilder.
  final _sectionsStreamCache = <String, Stream<List<AppSection>>>{};
  final _itemsStreamCache = <String, Stream<List<AppSectionItem>>>{};

  Stream<List<AppSection>> watchSections({String? contextFilter}) {
    final key = contextFilter ?? '';
    return _sectionsStreamCache[key] ??= _sections.snapshots().map((snap) {
      var list = snap.docs
          .map((d) => AppSection.fromFirestore(d.id, d.data()))
          .where((s) => s.enabled)
          .toList();
      if (contextFilter != null) {
        list = list
            .where((s) => s.context == contextFilter || s.context == 'both')
            .toList();
      }
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    });
  }

  Stream<List<AppSectionItem>> watchItems(
      {String? contextFilter, String? sectionId}) {
    final key = '${contextFilter ?? ''}|${sectionId ?? ''}';
    return _itemsStreamCache[key] ??= _watchItemsQuery(contextFilter, sectionId);
  }

  Stream<List<AppSectionItem>> _watchItemsQuery(
      String? contextFilter, String? sectionId) {
    Query<Map<String, dynamic>> q = _items;
    if (sectionId != null) {
      q = q.where('sectionId', isEqualTo: sectionId);
    }
    return q.snapshots().map((snap) {
      var list = snap.docs
          .map((d) => AppSectionItem.fromFirestore(d.id, d.data()))
          .where((i) => i.enabled)
          .toList();
      if (contextFilter != null) {
        list = list
            .where((i) => i.context == contextFilter || i.context == 'both')
            .toList();
      }
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    });
  }

  Future<String> addSection(AppSection section) async {
    final ref = await _sections.add({
      ...section.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateSection(String id, AppSection section) async {
    await _sections.doc(id).set(section.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteSection(String id) async {
    final items = await _items.where('sectionId', isEqualTo: id).get();
    for (final d in items.docs) {
      await d.reference.delete();
    }
    await _sections.doc(id).delete();
  }

  Future<String> addItem(AppSectionItem item) async {
    final ref = await _items.add({
      ...item.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateItem(String id, AppSectionItem item) async {
    await _items.doc(id).set(item.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteItem(String id) async {
    await _items.doc(id).delete();
  }

  String _sectionLookupKey(String title, String ctx) =>
      '${title.trim().toLowerCase()}|$ctx';

  /// Restores missing default folders & items (keeps your existing data).
  Future<RestoreReport> restoreMissingDefaults() async {
    return _populateDefaults(onlyMissing: true);
  }

  Future<void> seedDefaultStructure() async {
    try {
      final existing = await _sections.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      await _populateDefaults(onlyMissing: false);
    } catch (e) {
      debugPrint('App structure seed error: $e');
    }
  }

  Future<RestoreReport> _populateDefaults({required bool onlyMissing}) async {
    final report = RestoreReport();
    try {
      final existingSectionDocs = await _sections.get();
      final sectionIds = <String, String>{};

      for (final doc in existingSectionDocs.docs) {
        final d = doc.data();
        final key = _sectionLookupKey(
          d['title']?.toString() ?? '',
          d['context']?.toString() ?? 'both',
        );
        sectionIds[key] = doc.id;
      }

      final existingItems = await _items.get();
      final itemKeys = <String>{};
      for (final doc in existingItems.docs) {
        final d = doc.data();
        final rk = d['routeKey']?.toString() ?? '';
        final label = d['label']?.toString() ?? '';
        final sid = d['sectionId']?.toString() ?? '';
        itemKeys.add('$sid|$rk|$label');
      }

      final sections = <String, String>{};

      Future<String> sec(
          String internalKey, String title, int order, String ctx) async {
        if (sections.containsKey(internalKey)) {
          report.sectionsFound++;
          return sections[internalKey]!;
        }
        final lookup = _sectionLookupKey(title, ctx);
        if (sectionIds.containsKey(lookup)) {
          sections[internalKey] = sectionIds[lookup]!;
          report.sectionsFound++;
          return sections[internalKey]!;
        }
        final ref = await _sections.add({
          'title': title,
          'sortOrder': order,
          'enabled': true,
          'context': ctx,
          'createdAt': FieldValue.serverTimestamp(),
        });
        sections[internalKey] = ref.id;
        sectionIds[lookup] = ref.id;
        report.sectionsAdded++;
        return ref.id;
      }

      Future<void> item({
        required String sectionKey,
        required String label,
        String subtitle = '',
        String buttonText = '',
        required String iconName,
        required int colorHex,
        required String routeKey,
        String itemType = 'file',
        String dataSource = '',
        required int sortOrder,
        String context = 'both',
      }) async {
        final sid = sections[sectionKey];
        if (sid == null) return;
        final iKey = '$sid|$routeKey|$label';
        if (itemKeys.contains(iKey)) {
          report.itemsFound++;
          return;
        }
        if (onlyMissing) {
          await _items.add({
            'sectionId': sid,
            'label': label,
            'subtitle': subtitle,
            'buttonText': buttonText,
            'iconName': iconName,
            'colorHex': colorHex,
            'routeKey': routeKey,
            'itemType': itemType,
            'dataSource': dataSource,
            'sortOrder': sortOrder,
            'enabled': true,
            'context': context,
            'createdAt': FieldValue.serverTimestamp(),
          });
          itemKeys.add(iKey);
          report.itemsAdded++;
          return;
        }
        await _items.add({
          'sectionId': sid,
          'label': label,
          'subtitle': subtitle,
          'buttonText': buttonText,
          'iconName': iconName,
          'colorHex': colorHex,
          'routeKey': routeKey,
          'itemType': itemType,
          'dataSource': dataSource,
          'sortOrder': sortOrder,
          'enabled': true,
          'context': context,
          'createdAt': FieldValue.serverTimestamp(),
        });
        itemKeys.add(iKey);
        report.itemsAdded++;
      }

      // ── Dashboard folders (My Files style) ──
      await sec('dash_core', 'Core Operations', 0, 'dashboard');
      await item(
          sectionKey: 'dash_core',
          label: 'Emergency Alerts',
          subtitle: 'SOS & crash logs',
          buttonText: 'Open Alerts',
          iconName: 'warning_amber_rounded',
          colorHex: 0xFFFF3B4F,
          routeKey: 'alerts',
          dataSource: 'alerts',
          sortOrder: 0,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_core',
          label: 'User Contacts',
          subtitle: 'App emergency contacts',
          buttonText: 'View Contacts',
          iconName: 'contact_phone_rounded',
          colorHex: 0xFF4D9FFF,
          routeKey: 'emergency_contacts',
          dataSource: 'emergency_contacts',
          sortOrder: 1,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_core',
          label: 'Danger Zones',
          subtitle: 'Risk areas map',
          buttonText: 'Manage Zones',
          iconName: 'dangerous_rounded',
          colorHex: 0xFFFFB347,
          routeKey: 'danger_zones',
          dataSource: 'danger_zones',
          sortOrder: 2,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_core',
          label: 'Incident Reports',
          subtitle: 'User reports',
          buttonText: 'View Reports',
          iconName: 'report_rounded',
          colorHex: 0xFF00E5C8,
          routeKey: 'incident_reports',
          dataSource: 'incident_reports',
          sortOrder: 3,
          context: 'dashboard');

      await sec('dash_data', 'Live User Data', 1, 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'SOS Activity',
          subtitle: 'Press count per user',
          buttonText: 'Open SOS Log',
          iconName: 'sos_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'sos_activity',
          dataSource: 'sos_events',
          sortOrder: 0,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Notifications',
          subtitle: 'App alerts feed',
          buttonText: 'View All',
          iconName: 'notifications_rounded',
          colorHex: 0xFF00B4D8,
          routeKey: 'notifications',
          dataSource: 'app_notifications',
          sortOrder: 1,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Safety Tips',
          subtitle: 'Home screen tips',
          buttonText: 'Edit Tips',
          iconName: 'lightbulb_rounded',
          colorHex: 0xFFF4A261,
          routeKey: 'safety_tips',
          dataSource: 'safety_tips',
          sortOrder: 2,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Users & Roles',
          subtitle: 'Promote admins',
          buttonText: 'Manage Users',
          iconName: 'people_alt_rounded',
          colorHex: 0xFF9B5DE5,
          routeKey: 'users',
          sortOrder: 3,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Emergency Will',
          subtitle: 'Users\' private emergency info',
          buttonText: 'View Info',
          iconName: 'gavel_rounded',
          colorHex: 0xFFF4A261,
          routeKey: 'emergency_info',
          dataSource: 'emergency_info',
          sortOrder: 4,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Safety Guides',
          subtitle: 'Driving, Child & First-Aid content',
          buttonText: 'Edit Guides',
          iconName: 'healing_rounded',
          colorHex: 0xFF06D6A0,
          routeKey: 'safety_guides',
          dataSource: 'safety_guides',
          sortOrder: 5,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Hand Signals',
          subtitle: 'Women Safety "Signal for Help" content',
          buttonText: 'Edit Signals',
          iconName: 'female_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'hand_signals',
          dataSource: 'hand_signals',
          sortOrder: 6,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Women Safety',
          subtitle: 'Warning signs, prevention & helplines content',
          buttonText: 'Edit Content',
          iconName: 'female_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'women_safety',
          dataSource: 'women_safety_items',
          sortOrder: 7,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Panic Toolkit',
          subtitle: 'What-to-do, stay-calm & after-care guidance',
          buttonText: 'Edit Content',
          iconName: 'shield_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'panic_tools',
          dataSource: 'panic_tools',
          sortOrder: 8,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_data',
          label: 'Onboarding',
          subtitle: 'First-run walkthrough slides',
          buttonText: 'Edit Slides',
          iconName: 'auto_stories_rounded',
          colorHex: 0xFF00B4D8,
          routeKey: 'onboarding',
          dataSource: 'onboarding_slides',
          sortOrder: 9,
          context: 'dashboard');

      await sec(
          'dash_config', 'App Layout (Folders & Buttons)', 2, 'dashboard');
      await item(
          sectionKey: 'dash_config',
          label: 'Sections & Buttons',
          subtitle: 'Edit menu, labels, button text',
          buttonText: 'Open Editor',
          iconName: 'tune_rounded',
          colorHex: 0xFF06D6A0,
          routeKey: 'app_structure',
          itemType: 'button',
          sortOrder: 0,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_config',
          label: 'Page Content',
          subtitle: 'Edit page headings, hero text & button labels',
          buttonText: 'Open Editor',
          iconName: 'description_rounded',
          colorHex: 0xFF06D6A0,
          routeKey: 'page_content',
          itemType: 'button',
          sortOrder: 1,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_config',
          label: 'Feedback & Ratings',
          subtitle: 'User star ratings & feedback from the app',
          buttonText: 'View Feedback',
          iconName: 'star_rounded',
          colorHex: 0xFFF59E0B,
          routeKey: 'app_feedback',
          itemType: 'button',
          sortOrder: 2,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_config',
          label: 'Chatbot Q&A',
          subtitle: 'Edit SafeBot answers & suggested questions',
          buttonText: 'Edit Chatbot',
          iconName: 'description_rounded',
          colorHex: 0xFF00B4D8,
          routeKey: 'chatbot_faq',
          itemType: 'button',
          sortOrder: 3,
          context: 'dashboard');
      await item(
          sectionKey: 'dash_config',
          label: 'Settings',
          subtitle: 'Admin profile',
          buttonText: 'Open Settings',
          iconName: 'settings_rounded',
          colorHex: 0xFFADB5BD,
          routeKey: 'settings',
          sortOrder: 4,
          context: 'dashboard');

      // ── App drawer sections (mirror app) ──
      await sec('crisis_sos', 'Crisis & SOS', 10, 'app');
      await item(
          sectionKey: 'crisis_sos',
          label: 'Community SOS',
          subtitle: 'Alert nearby SmartSafe users',
          buttonText: 'Open',
          iconName: 'groups_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'community_sos',
          sortOrder: 0,
          context: 'app');
      await item(
          sectionKey: 'crisis_sos',
          label: 'Crisis Hub',
          subtitle: 'All emergency tools',
          buttonText: 'Open Hub',
          iconName: 'campaign_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'crisis_hub',
          sortOrder: 1,
          context: 'app');
      await item(
          sectionKey: 'crisis_sos',
          label: 'Women Safety',
          buttonText: 'Open',
          iconName: 'female_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'women_safety',
          sortOrder: 2,
          context: 'app');
      await item(
          sectionKey: 'crisis_sos',
          label: 'Evidence Recorder',
          buttonText: 'Record',
          iconName: 'camera_alt_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'evidence',
          sortOrder: 3,
          context: 'app');
      await item(
          sectionKey: 'crisis_sos',
          label: 'Emergency Dial',
          buttonText: 'Dial',
          iconName: 'phone_forwarded_rounded',
          colorHex: 0xFF00B4D8,
          routeKey: 'emergency_dial',
          sortOrder: 4,
          context: 'app');
      await item(
          sectionKey: 'crisis_sos',
          label: 'Emergency Will',
          buttonText: 'View',
          iconName: 'gavel_rounded',
          colorHex: 0xFFF4A261,
          routeKey: 'emergency_will',
          sortOrder: 5,
          context: 'app');

      await sec('travel_guard', 'Travel Guard', 11, 'app');
      await item(
          sectionKey: 'travel_guard',
          label: 'Travel Hub',
          subtitle: 'Routes & check-ins',
          buttonText: 'Open',
          iconName: 'map_rounded',
          colorHex: 0xFF00B4D8,
          routeKey: 'travel_hub',
          sortOrder: 0,
          context: 'app');
      await item(
          sectionKey: 'travel_guard',
          label: 'Danger Zones',
          buttonText: 'Map',
          iconName: 'local_fire_department_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'danger_zone',
          sortOrder: 1,
          context: 'app');
      await item(
          sectionKey: 'travel_guard',
          label: 'Safe Check-In',
          buttonText: 'Start Timer',
          iconName: 'timer_rounded',
          colorHex: 0xFF00B4D8,
          routeKey: 'safe_checkin',
          sortOrder: 2,
          context: 'app');

      await sec('smart_security', 'Smart Security', 12, 'app');
      await item(
          sectionKey: 'smart_security',
          label: 'Security Hub',
          buttonText: 'Open',
          iconName: 'security_rounded',
          colorHex: 0xFF4D9FFF,
          routeKey: 'security_hub',
          sortOrder: 0,
          context: 'app');
      await item(
          sectionKey: 'smart_security',
          label: 'Crash Detection',
          buttonText: 'Open',
          iconName: 'car_crash_rounded',
          colorHex: 0xFFF4A261,
          routeKey: 'crash_detection',
          sortOrder: 1,
          context: 'app');
      await item(
          sectionKey: 'smart_security',
          label: 'Driving Safety',
          buttonText: 'Open',
          iconName: 'directions_car_rounded',
          colorHex: 0xFF4D9FFF,
          routeKey: 'driving_safety',
          sortOrder: 2,
          context: 'app');
      await item(
          sectionKey: 'smart_security',
          label: 'Child Safety',
          buttonText: 'Open',
          iconName: 'child_care_rounded',
          colorHex: 0xFF9B5DE5,
          routeKey: 'child_safety',
          sortOrder: 3,
          context: 'app');
      await item(
          sectionKey: 'smart_security',
          label: 'Incident Report',
          buttonText: 'Report',
          iconName: 'description_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'incident_report',
          sortOrder: 4,
          context: 'app');

      await sec('health_calm', 'Health & Calm', 13, 'app');
      await item(
          sectionKey: 'health_calm',
          label: 'First Aid Hub',
          buttonText: 'Open',
          iconName: 'healing_rounded',
          colorHex: 0xFF06D6A0,
          routeKey: 'health_hub',
          sortOrder: 0,
          context: 'app');
      await item(
          sectionKey: 'health_calm',
          label: 'First Aid Guides',
          buttonText: 'Guides',
          iconName: 'medical_services_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'first_aid',
          sortOrder: 1,
          context: 'app');
      await item(
          sectionKey: 'health_calm',
          label: 'Breathe & De-stress',
          buttonText: 'Breathe',
          iconName: 'air_rounded',
          colorHex: 0xFF00B4D8,
          routeKey: 'panic_breathe',
          sortOrder: 2,
          context: 'app');

      await sec('insights_circle', 'Insights & Circle', 14, 'app');
      await item(
          sectionKey: 'insights_circle',
          label: 'Community Hub',
          buttonText: 'Open',
          iconName: 'group_rounded',
          colorHex: 0xFF9B5DE5,
          routeKey: 'community_hub',
          sortOrder: 0,
          context: 'app');
      await item(
          sectionKey: 'insights_circle',
          label: 'Safety Score',
          buttonText: 'View Score',
          iconName: 'shield_rounded',
          colorHex: 0xFF4D9FFF,
          routeKey: 'safety_score',
          sortOrder: 1,
          context: 'app');
      await item(
          sectionKey: 'insights_circle',
          label: 'Family Radar',
          buttonText: 'Open Radar',
          iconName: 'radar_rounded',
          colorHex: 0xFF9B5DE5,
          routeKey: 'family_radar',
          sortOrder: 2,
          context: 'app');
      await item(
          sectionKey: 'insights_circle',
          label: 'Alert History',
          buttonText: 'History',
          iconName: 'history_rounded',
          colorHex: 0xFF9B5DE5,
          routeKey: 'alert_history',
          sortOrder: 3,
          context: 'app');
      await item(
          sectionKey: 'insights_circle',
          label: 'My SOS History',
          subtitle: 'Kitni dafa SOS diya — date & time',
          buttonText: 'View History',
          iconName: 'history_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'my_sos_history',
          sortOrder: 4,
          context: 'app');
      await item(
          sectionKey: 'insights_circle',
          label: 'Live Safety Feed',
          buttonText: 'Feed',
          iconName: 'rss_feed_rounded',
          colorHex: 0xFFF4A261,
          routeKey: 'safety_feed',
          sortOrder: 5,
          context: 'app');

      await sec('home_quick', 'Home Quick Access', 15, 'app');
      await item(
          sectionKey: 'home_quick',
          label: 'Live GPS',
          buttonText: 'Open Map',
          iconName: 'location_on_rounded',
          colorHex: 0xFF00B4D8,
          routeKey: 'live_gps',
          itemType: 'button',
          sortOrder: 0,
          context: 'app');
      await item(
          sectionKey: 'home_quick',
          label: 'Safe Route',
          buttonText: 'Plan Route',
          iconName: 'route_rounded',
          colorHex: 0xFF06D6A0,
          routeKey: 'safe_route',
          itemType: 'button',
          sortOrder: 1,
          context: 'app');
      await item(
          sectionKey: 'home_quick',
          label: 'Panic Tool',
          buttonText: 'Open Toolkit',
          iconName: 'campaign_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'panic_toolkit',
          itemType: 'button',
          sortOrder: 2,
          context: 'app');

      await sec('home_featured', 'Home Featured', 16, 'app');
      await item(
          sectionKey: 'home_featured',
          label: 'Community SOS',
          subtitle: 'Alert nearby users - 10 km radius',
          buttonText: 'Tap to Open',
          iconName: 'groups_rounded',
          colorHex: 0xFFE63946,
          routeKey: 'community_sos',
          itemType: 'button',
          sortOrder: 0,
          context: 'app');

      debugPrint(
        'App structure ${onlyMissing ? "restore" : "seed"}: +${report.sectionsAdded} sections, +${report.itemsAdded} items',
      );
    } catch (e) {
      debugPrint('App structure populate error: $e');
    }
    return report;
  }
}

class RestoreReport {
  int sectionsAdded = 0;
  int itemsAdded = 0;
  int sectionsFound = 0;
  int itemsFound = 0;
}
