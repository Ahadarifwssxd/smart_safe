import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartsafe/models/models.dart';
import 'package:smartsafe/models/app_structure.dart';
import 'package:smartsafe/models/sos_history_entry.dart';
import 'package:smartsafe/navigation/app_page_router.dart';
import 'package:smartsafe/services/app_firestore_service.dart';
import 'package:smartsafe/services/app_structure_service.dart';

class AppSearchResult {
  final String title;
  final String subtitle;
  final String type;
  final String routeKey;

  const AppSearchResult({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.routeKey,
  });
}

/// Instant, in-memory search over the app's menu, tips, contacts & SOS history.
///
/// The data is streamed ONCE and kept in memory, so [searchSync] filters
/// synchronously on every keystroke — results appear from the very first letter
/// with no per-keystroke Firestore round-trip and no loading spinner.
class AppSearchService {
  static final AppSearchService instance = AppSearchService._();
  AppSearchService._();

  // Cached, live snapshots (kept fresh by the subscriptions below).
  List<AppSection> _sections = const [];
  List<AppSectionItem> _items = const [];
  List<SafetyTip> _tips = const [];
  List<Contact> _contacts = const [];
  List<SosHistoryEntry> _sos = const [];

  final List<StreamSubscription> _subs = [];
  bool _started = false;

  /// Subscribe once and keep the caches warm. Safe to call repeatedly; call it
  /// early (e.g. when the search bar is created) so the first search is instant.
  void start() {
    if (_started) return;
    _started = true;
    try {
      _subs.add(AppStructureService.instance
          .watchSections(contextFilter: 'app')
          .listen((v) => _sections = v, onError: (_) {}));
      _subs.add(AppStructureService.instance
          .watchItems(contextFilter: 'app')
          .listen((v) => _items = v, onError: (_) {}));
      _subs.add(AppFirestoreService.instance
          .watchSafetyTips()
          .listen((v) => _tips = v, onError: (_) {}));
      _subs.add(AppFirestoreService.instance
          .watchMyEmergencyContacts()
          .listen((v) => _contacts = v, onError: (_) {}));
      _subs.add(AppFirestoreService.instance
          .watchMySosHistory()
          .listen((v) => _sos = v, onError: (_) {}));
    } catch (_) {}
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _started = false;
  }

  /// Synchronous filter over the cached data — instant, from the first letter.
  List<AppSearchResult> searchSync(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final results = <AppSearchResult>[];
    final seen = <String>{};

    void add(AppSearchResult r) {
      final key = '${r.routeKey}|${r.title}|${r.type}';
      if (seen.add(key)) results.add(r);
    }

    bool match(String? s) => s != null && s.toLowerCase().contains(q);

    // Menu features
    for (final item in _items) {
      var sectionTitle = '';
      for (final s in _sections) {
        if (s.id == item.sectionId) {
          sectionTitle = s.title;
          break;
        }
      }
      if (match(item.label) ||
          match(item.subtitle) ||
          match(item.buttonText) ||
          match(item.routeKey) ||
          match(sectionTitle)) {
        add(AppSearchResult(
          title: item.label,
          subtitle: [
            if (sectionTitle.isNotEmpty) sectionTitle,
            if (item.subtitle.isNotEmpty) item.subtitle,
          ].join(' · '),
          type: 'Feature',
          routeKey: item.routeKey,
        ));
      }
    }

    // Safety tips
    for (final tip in _tips) {
      if (match(tip.title) || match(tip.body)) {
        add(AppSearchResult(
          title: tip.title,
          subtitle:
              tip.body.length > 60 ? '${tip.body.substring(0, 60)}…' : tip.body,
          type: 'Safety Tip',
          routeKey: '',
        ));
      }
    }

    if (FirebaseAuth.instance.currentUser != null) {
      for (final c in _contacts) {
        if (match(c.name) || match(c.phone) || match(c.relation)) {
          add(AppSearchResult(
            title: c.name,
            subtitle: '${c.phone} · ${c.relation}',
            type: 'Contact',
            routeKey: 'contacts_page',
          ));
        }
      }
      for (final e in _sos) {
        if (match(e.location) ||
            match(e.source) ||
            match(e.alertType) ||
            match(e.formattedDate)) {
          add(AppSearchResult(
            title: 'SOS ${e.formattedDate} ${e.formattedTime}',
            subtitle: e.location,
            type: 'SOS History',
            routeKey: 'my_sos_history',
          ));
        }
      }
    }

    // Always-available quick destinations
    const extras = [
      ('My SOS History', 'How many times SOS was pressed', 'my_sos_history'),
      ('Community SOS', 'Alert nearby users', 'community_sos'),
      ('Emergency Contacts', 'Trusted circle', 'contacts_page'),
      ('Women Safety', 'Safety tools', 'women_safety'),
      ('Safe Route', 'Plan safe path', 'safe_route'),
      ('Panic Toolkit', 'Flashlight & alarm', 'panic_toolkit'),
    ];
    for (final e in extras) {
      if (match(e.$1) || match(e.$2)) {
        add(AppSearchResult(
            title: e.$1, subtitle: e.$2, type: 'Quick', routeKey: e.$3));
      }
    }

    return results.take(25).toList();
  }

  /// Async wrapper kept for backward compatibility — resolves instantly from
  /// the in-memory cache.
  Future<List<AppSearchResult>> search(String query) async =>
      searchSync(query);

  static void openResult(
    BuildContext context,
    AppSearchResult result, {
    VoidCallback? onSOSTap,
  }) {
    if (result.routeKey.isEmpty) return;
    if (result.routeKey == 'contacts_page') {
      AppPageRouter.open(context, 'contacts_page', onSOSTap: onSOSTap);
      return;
    }
    AppPageRouter.open(context, result.routeKey, onSOSTap: onSOSTap);
  }
}
