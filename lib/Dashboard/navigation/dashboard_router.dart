import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/screens/alerts/alerts_screen.dart';
import 'package:smartsafe/Dashboard/screens/app_notifications/app_notifications_screen.dart';
import 'package:smartsafe/Dashboard/screens/app_structure/app_structure_screen.dart';
import 'package:smartsafe/Dashboard/screens/contacts/contacts_screen.dart';
import 'package:smartsafe/Dashboard/screens/danger_zones/danger_zones_screen.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/dashboard_screen.dart';
import 'package:smartsafe/Dashboard/screens/emergency_will/emergency_will_screen.dart';
import 'package:smartsafe/Dashboard/screens/safety_guides/safety_guides_screen.dart';
import 'package:smartsafe/Dashboard/screens/hand_signals/hand_signals_screen.dart';
import 'package:smartsafe/Dashboard/screens/women_safety/women_safety_screen.dart';
import 'package:smartsafe/Dashboard/screens/panic_tools/panic_tools_screen.dart';
import 'package:smartsafe/Dashboard/screens/onboarding/onboarding_screen.dart';
import 'package:smartsafe/Dashboard/screens/page_content/page_content_screen.dart';
import 'package:smartsafe/Dashboard/screens/feedback/feedback_screen.dart';
import 'package:smartsafe/Dashboard/screens/chatbot/chatbot_faq_screen.dart';
import 'package:smartsafe/Dashboard/screens/incident_reports/incident_reports_screen.dart';
import 'package:smartsafe/Dashboard/screens/safety_tips/safety_tips_screen.dart';
import 'package:smartsafe/Dashboard/screens/settings/settings_screen.dart';
import 'package:smartsafe/Dashboard/screens/sos_activity/sos_activity_screen.dart';
import 'package:smartsafe/Dashboard/screens/users/users_screen.dart';

/// Maps dynamic [routeKey] from Firestore to dashboard screens.
class DashboardRouter {
  static Widget screenForRoute(
    String routeKey, {
    required VoidCallback onLogout,
  }) {
    switch (routeKey) {
      case 'dashboard':
        return const DashboardScreen();
      case 'alerts':
        return const AlertsScreen();
      case 'emergency_contacts':
        return const ContactsScreen();
      case 'danger_zones':
        return const DangerZonesScreen();
      case 'incident_reports':
        return const IncidentReportsScreen();
      case 'users':
      case 'pro_subscribers':
        return const UsersScreen();
      case 'sos_activity':
        return const SosActivityScreen();
      case 'notifications':
        return const AppNotificationsScreen();
      case 'safety_tips':
        return const SafetyTipsScreen();
      case 'emergency_info':
        return const EmergencyWillScreen();
      case 'safety_guides':
        return const SafetyGuidesScreen();
      case 'hand_signals':
        return const HandSignalsScreen();
      case 'women_safety':
        return const WomenSafetyScreen();
      case 'panic_tools':
        return const PanicToolsScreen();
      case 'onboarding':
        return const OnboardingScreen();
      case 'page_content':
        return const PageContentScreen();
      case 'app_feedback':
        return const FeedbackScreen();
      case 'chatbot_faq':
        return const ChatbotFaqScreen();
      case 'app_structure':
        return const AppStructureScreen();
      case 'settings':
        return SettingsScreen(onLogout: onLogout);
      default:
        return const DashboardScreen();
    }
  }
}
