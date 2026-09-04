import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config/app_content_defaults.dart';

/// Live, admin-editable page text (headings, subtitles, hero copy, buttons).
///
/// One Firestore collection — `page_content` — holds one document per pageKey:
///   page_content/women_safety => { fields: { title: '...', subtitle: '...' } }
///
/// The app reads through here: whatever the admin typed in the dashboard wins,
/// falling back to [kPageContentDefaults] so the page is never blank (offline,
/// pre-seed, or unknown key). It's a [ChangeNotifier] so [DynText] rebuilds the
/// instant an admin edits a value.
class PageContentService extends ChangeNotifier {
  static final PageContentService instance = PageContentService._();
  PageContentService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('page_content');

  /// pageKey → (fieldKey → live value). Populated by [start].
  Map<String, Map<String, String>> _cache = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// Begins listening to Firestore. Safe to call more than once.
  void start() {
    if (_sub != null) return;
    _sub = _col.snapshots().listen((snap) {
      final next = <String, Map<String, String>>{};
      for (final doc in snap.docs) {
        final fields = doc.data()['fields'];
        if (fields is Map) {
          next[doc.id] = fields.map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
          );
        }
      }
      _cache = next;
      notifyListeners();
    }, onError: (e) => debugPrint('PageContentService stream error: $e'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Live value for a field, falling back to the built-in default then [fallback].
  String text(String page, String field, [String fallback = '']) {
    return _cache[page]?[field] ??
        kPageContentDefaults[page]?[field] ??
        fallback;
  }

  /// All fields for a page merged over defaults (used by the dashboard editor).
  Map<String, String> fieldsFor(String page) {
    return {
      ...?kPageContentDefaults[page],
      ...?_cache[page],
    };
  }

  // ── Dashboard writes ────────────────────────────────────────────────────
  Future<void> updateField(String page, String field, String value) async {
    await _col.doc(page).set({
      'fields': {field: value},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updatePage(String page, Map<String, String> fields) async {
    await _col.doc(page).set({
      'fields': fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Restores one page's fields back to the built-in defaults.
  Future<void> resetPage(String page) async {
    final defaults = kPageContentDefaults[page];
    if (defaults == null) return;
    await _col.doc(page).set({
      'fields': defaults,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Copies every default into Firestore once so the dashboard can edit it.
  /// Idempotent — merges missing pages/fields without clobbering admin edits.
  Future<void> seedIfEmpty() async {
    try {
      final existing = await _col.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      final batch = _db.batch();
      kPageContentDefaults.forEach((page, fields) {
        batch.set(_col.doc(page), {
          'fields': fields,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      await batch.commit();
    } catch (e) {
      debugPrint('PageContentService seed error: $e');
    }
  }

  /// Adds any pages/fields introduced after the first seed, without touching
  /// values the admin already changed. Safe to run on every launch.
  Future<void> restoreMissingDefaults() async {
    try {
      final snap = await _col.get();
      final present = {for (final d in snap.docs) d.id: d.data()};
      final batch = _db.batch();
      var writes = 0;
      kPageContentDefaults.forEach((page, defaults) {
        final existingFields =
            (present[page]?['fields'] as Map?)?.keys.map((k) => k.toString());
        final missing = <String, String>{};
        defaults.forEach((k, v) {
          if (existingFields == null || !existingFields.contains(k)) {
            missing[k] = v;
          }
        });
        if (missing.isNotEmpty) {
          batch.set(_col.doc(page), {
            'fields': missing,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          writes++;
        }
      });
      if (writes > 0) await batch.commit();
    } catch (e) {
      debugPrint('PageContentService restore error: $e');
    }
  }
}

/// Drop-in replacement for [Text] that shows admin-editable, live page content.
///
/// `DynText('women_safety', 'title', 'Women Safety', style: ...)` renders the
/// admin's value when set, otherwise the default/fallback — and rebuilds itself
/// the moment the value changes in Firestore.
class DynText extends StatelessWidget {
  final String page;
  final String field;
  final String fallback;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const DynText(
    this.page,
    this.field,
    this.fallback, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PageContentService.instance,
      builder: (context, _) => Text(
        PageContentService.instance.text(page, field, fallback),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// Convenience for reading a raw string outside a widget tree (no auto-rebuild).
extension PageContentContext on BuildContext {
  String pageText(String page, String field, [String fallback = '']) =>
      PageContentService.instance.text(page, field, fallback);
}
