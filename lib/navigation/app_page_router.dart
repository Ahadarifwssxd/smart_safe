import 'package:flutter/material.dart';
import 'package:smartsafe/navigation/dark_route.dart';
import 'package:smartsafe/pages/04_map_page.dart';
import 'package:smartsafe/pages/05_safe_route_page.dart';
import 'package:smartsafe/pages/plan_a_route_page.dart';
import 'package:smartsafe/pages/06_crash_detection_page.dart';
import 'package:smartsafe/pages/07_alert_history_page.dart';
import 'package:smartsafe/pages/my_sos_history_page.dart';
import 'package:smartsafe/pages/11_safety_score_page.dart';
import 'package:smartsafe/pages/11_women_safety_page.dart';
import 'package:smartsafe/pages/12_driving_safety_page.dart';
import 'package:smartsafe/pages/12_panic_breathe_page.dart';
import 'package:smartsafe/pages/13_evidence_page.dart';
import 'package:smartsafe/pages/14_family_radar_page.dart';
import 'package:smartsafe/pages/15_emergency_will_page.dart';
import 'package:smartsafe/pages/15_first_aid_page.dart';
import 'package:smartsafe/pages/16_danger_zone_page.dart';
import 'package:smartsafe/pages/16_emergency_dial_page.dart';
import 'package:smartsafe/pages/17_safety_feed_page.dart';
import 'package:smartsafe/pages/19_panic_toolkit_page.dart';
import 'package:smartsafe/pages/20_child_safety_page.dart';
import 'package:smartsafe/pages/21_safe_checkin_page.dart';
import 'package:smartsafe/pages/22_incident_report_page.dart';
import 'package:smartsafe/pages/03_contacts_page.dart';
import 'package:smartsafe/pages/28_enhanced_community_sos_page.dart';
import 'package:smartsafe/pages/hub_community.dart';
import 'package:smartsafe/pages/hub_emergency.dart';
import 'package:smartsafe/pages/hub_health.dart';
import 'package:smartsafe/pages/hub_security.dart';
import 'package:smartsafe/pages/hub_travel.dart';

/// Opens app pages from dynamic Firestore [routeKey].
class AppPageRouter {
  static void open(
    BuildContext context,
    String routeKey, {
    VoidCallback? onSOSTap,
  }) {
    final page = _pageForRoute(routeKey, onSOSTap: onSOSTap);
    if (page == null) return;
    Navigator.push(context, darkRoute(page));
  }

  static Widget? _pageForRoute(String routeKey, {VoidCallback? onSOSTap}) {
    switch (routeKey) {
      case 'community_sos':
        return const EnhancedCommunitySosPage();
      case 'crisis_hub':
        return EmergencyHubPage(onSOSTap: onSOSTap);
      case 'women_safety':
        return const WomenSafetyPage();
      case 'evidence':
        return const EvidencePage();
      case 'emergency_dial':
        return const EmergencyDialPage();
      case 'emergency_will':
        return const EmergencyWillPage();
      case 'travel_hub':
        return TravelHubPage(onSOSTap: onSOSTap);
      case 'danger_zone':
        return const DangerZonePage();
      case 'safe_checkin':
        return SafeCheckInPage(onSOSTap: onSOSTap ?? () {});
      case 'security_hub':
        return const SecurityHubPage();
      case 'crash_detection':
        return const CrashDetectionPage();
      case 'driving_safety':
        return const DrivingSafetyPage();
      case 'child_safety':
        return const ChildSafetyPage();
      case 'incident_report':
        return const IncidentReportPage();
      case 'health_hub':
        return const HealthHubPage();
      case 'first_aid':
        return const FirstAidPage();
      case 'panic_breathe':
        return const PanicBreathePage();
      case 'community_hub':
        return const CommunityHubPage();
      case 'safety_score':
        return const SafetyScorePage();
      case 'family_radar':
        return const FamilyRadarPage();
      case 'alert_history':
        return const AlertHistoryPage();
      case 'my_sos_history':
        return const MySosHistoryPage();
      case 'safety_feed':
        return const SafetyFeedPage();
      case 'live_gps':
        return const MapPage();
      case 'safe_route':
        // "Plan Route" now opens the rebuilt, full-featured page (live GPS,
        // Nominatim search, OSRM alternatives, danger-zone overlay, turn-by-turn,
        // live journey sharing). The old SafeRoutePage is kept for reference.
        return const PlanARoutePage();
      case 'panic_toolkit':
        return PanicToolkitPage(onSOSTap: onSOSTap ?? () {});
      case 'contacts_page':
        return const ContactsPage();
      default:
        return null;
    }
  }
}
