import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart' as dashboard;
import 'package:smartsafe/firebase_options.dart';
import 'package:smartsafe/services/app_structure_service.dart';
import 'package:smartsafe/services/page_content_service.dart';
import 'package:smartsafe/services/subscription_service.dart';

/// Fast app startup: Firebase init only in [main], seeding runs after first frame.
class AppBootstrap {
  static Future<void> ensureFirebase() async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // OFFLINE SUPPORT: keep a local cache so the app keeps working without
    // internet — cached contacts/profile/tips/history stay visible, and writes
    // (SOS records, chat messages, profile edits) queue and auto-sync once the
    // connection returns. Critical for a safety app on patchy networks.
    // Cache is capped at 100 MB (the Firestore default) instead of UNLIMITED:
    // an unbounded cache grows forever on disk and every app start pays to
    // re-index it — a classic slow-launch cause on low-storage devices.
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024,
      );
    } catch (e) {
      debugPrint('Firestore persistence setup skipped: $e');
    }
  }

  /// Initializes the subscription service with the current user's ID.
  /// Call this AFTER Firebase Auth has a signed-in user (e.g., after login
  /// or on app start if user is already logged in).
  ///
  /// Safe to call multiple times — the service caches initialization and
  /// only re-initializes if the userId changes.
  static Future<void> initSubscriptionService() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await SubscriptionService.instance.init(uid);
  }

  /// Clears subscription service state. Call on logout.
  static Future<void> resetSubscriptionService() async {
    await SubscriptionService.instance.reset();
  }

  /// Firestore default data — never block [runApp] or hot restart UI.
  static void scheduleBackgroundSeeding({bool includeDashboardDemo = false}) {
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _seedInBackground(includeDashboardDemo: includeDashboardDemo);
    });
  }

  /// The seed checks are idempotent but they still cost ~10 Firestore reads,
  /// and they used to run on EVERY launch AND again after every login. Once a
  /// signed-in run has verified the content, we skip everything for a week
  /// (fresh defaults still get picked up weekly, or on fresh install).
  static const _seedCheckFlag = 'content_seed_verified_at';
  static const _seedCheckInterval = Duration(days: 7);

  static Future<void> _seedInBackground({required bool includeDashboardDemo}) async {
    try {
      // Skip if a recent signed-in pass already verified the default content.
      final prefs = await SharedPreferences.getInstance();
      final lastVerified = prefs.getInt(_seedCheckFlag);
      if (lastVerified != null &&
          DateTime.now().millisecondsSinceEpoch - lastVerified <
              _seedCheckInterval.inMilliseconds) {
        return;
      }

      if (includeDashboardDemo) {
        await Future.wait([
          dashboard.FirebaseService.instance.seedDefaultAdminConfig(),
          AppStructureService.instance.seedDefaultStructure(),
        ]);
        await dashboard.FirebaseService.instance.seedInitialDemoData();
      } else {
        await AppStructureService.instance.seedDefaultStructure();
      }
      // Seed the Home screen's Safety Tips once so a fresh install doesn't show
      // "No safety tips available yet" (idempotent — no-op once seeded).
      await dashboard.FirebaseService.instance.seedSafetyTipsIfEmpty();
      // Seed the Driving/Child/First-Aid guides once so admins can edit them
      // and the app shows real content (idempotent — no-op if already seeded).
      await dashboard.FirebaseService.instance.seedSafetyGuidesIfEmpty();
      // Seed the Women Safety "Hand Signals for Help" once so admins can edit
      // them and the app shows real content (idempotent — no-op if seeded).
      await dashboard.FirebaseService.instance.seedHandSignalsIfEmpty();
      // Seed the rest of the Women Safety page content (warning signs,
      // prevention, self-defense, what-to-carry, worst-case steps, helplines)
      // once so admins can edit it (idempotent — no-op if already seeded).
      await dashboard.FirebaseService.instance.seedWomenSafetyIfEmpty();
      // Seed the informational Panic Toolkit guidance cards once so admins can
      // edit them (idempotent — no-op if already seeded).
      await dashboard.FirebaseService.instance.seedPanicToolsIfEmpty();
      // Seed the first-run Onboarding walkthrough slides once so admins can
      // edit them (idempotent — no-op if already seeded).
      await dashboard.FirebaseService.instance.seedOnboardingIfEmpty();
      // Seed every page's editable headings/subtitles/hero copy once, then pull
      // in any newly-added page fields on later launches (idempotent).
      await PageContentService.instance.seedIfEmpty();
      await PageContentService.instance.restoreMissingDefaults();

      // Dashboards created BEFORE the content-CMS links existed (Safety Guides,
      // Hand Signals, Women Safety, Panic Toolkit, Onboarding, Emergency Will)
      // won't show them, because seedDefaultStructure() no-ops once sections
      // exist. Run restoreMissingDefaults ONCE to pull in only the NEW folders/
      // items — existing (and admin-deleted) data is preserved, and the guard
      // flag stops deleted items from reappearing on every launch.
      try {
        if (prefs.getBool('structure_restore_cms_v4') != true) {
          await AppStructureService.instance.restoreMissingDefaults();
          await prefs.setBool('structure_restore_cms_v4', true);
        }
      } catch (_) {}

      // Earlier builds seeded Safety Guides / Tips / Panic tools with random doc
      // ids, so a startup race inserted each item 2–3× (visible as duplicates on
      // Child Safety, Driving Safety, etc.). Deduplicate once — later seeds use
      // deterministic ids and can't duplicate again. Runs whenever duplicates
      // are still present (the flag is only set after a clean pass).
      try {
        if (prefs.getBool('dedupe_seeded_v1') != true) {
          await dashboard.FirebaseService.instance.dedupeSeededContent();
          await prefs.setBool('dedupe_seeded_v1', true);
        }
      } catch (_) {}

      // Only mark verified when the pass ran while signed in — Firestore rules
      // reject writes from signed-out clients, so a pre-auth pass can't be
      // trusted to have actually written anything.
      if (FirebaseAuth.instance.currentUser != null) {
        await prefs.setInt(_seedCheckFlag,
            DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e, st) {
      debugPrint('Background seed error: $e\n$st');
    }
  }
}
