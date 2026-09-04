import 'dart:async';

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/services/cloudinary_service.dart';
import 'package:smartsafe/models/safety_guide.dart';
import 'package:smartsafe/models/hand_signal.dart';
import 'package:smartsafe/models/women_safety_item.dart';
import 'package:smartsafe/models/panic_tool.dart';
import 'package:smartsafe/models/onboarding_slide.dart';
import 'package:smartsafe/models/user_roles.dart';
import 'package:smartsafe/utils/phone_utils.dart';
class FirebaseService {
  static final FirebaseService instance = FirebaseService._internal();
  FirebaseService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stable, content-derived document id. Seeding with a deterministic id means
  /// a repeated seed OVERWRITES the same doc instead of adding a duplicate — so
  /// the seed can never triple-up, even if two seed passes race at startup.
  static String _seedId(String raw) {
    final s = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'item' : s;
  }

  /// Removes duplicate seeded documents that earlier builds created (each item
  /// showed 2–3×). Groups every doc by its content key and keeps just one,
  /// deleting the rest. Safe to run repeatedly — a no-op once deduped.
  Future<void> _dedupeByKey(
      CollectionReference col, String Function(Map<String, dynamic>) keyOf) async {
    try {
      final snap = await col.get();
      final docs = snap.docs.toList()
        ..sort((a, b) => a.id.compareTo(b.id)); // stable: keep the first id
      final seen = <String>{};
      final batch = _db.batch();
      var deletes = 0;
      for (final d in docs) {
        final data = d.data() as Map<String, dynamic>;
        final key = keyOf(data);
        if (seen.add(key)) continue; // first time → keep
        batch.delete(d.reference);
        deletes++;
      }
      if (deletes > 0) await batch.commit();
    } catch (e) {
      debugPrint('dedupe error on ${col.path}: $e');
    }
  }

  /// One-time cleanup of the duplicate seeded content visible on Safety Guides
  /// (Child Safety / Driving Safety / First Aid), Safety Tips and Panic Toolkit.
  Future<void> dedupeSeededContent() async {
    await _dedupeByKey(safetyGuidesCollection,
        (d) => '${d['category']}|${d['title']}');
    await _dedupeByKey(safetyTipsCollection, (d) => '${d['title']}');
    await _dedupeByKey(panicToolsCollection,
        (d) => '${d['category']}|${d['title']}');
  }

  // Collection references
  CollectionReference get usersCollection => _db.collection('users');
  CollectionReference get alertsCollection => _db.collection('alerts');
  CollectionReference get contactsCollection => _db.collection('contacts');
  CollectionReference get dangerZonesCollection => _db.collection('danger_zones');
  CollectionReference get incidentReportsCollection => _db.collection('incident_reports');
  CollectionReference get configCollection => _db.collection('admin_config');
  CollectionReference get emergencyContactsCollection => _db.collection('emergency_contacts');
  CollectionReference get sosEventsCollection => _db.collection('sos_events');
  CollectionReference get appNotificationsCollection => _db.collection('app_notifications');
  CollectionReference get safetyTipsCollection => _db.collection('safety_tips');
  CollectionReference get emergencyNumbersCollection => _db.collection('emergency_numbers');
  // Private "Emergency Will / Info" each user fills in the app. Admin-only view.
  CollectionReference get emergencyInfoCollection => _db.collection('emergency_info');
  // Admin-managed Emergency Will FIELD DEFINITIONS (section + label + key), so
  // the app renders the will form dynamically from what the admin configures.
  CollectionReference get willFieldsCollection =>
      _db.collection('emergency_will_fields');
  // Admin-managed safety guides shown on Driving / Child / First-Aid pages.
  CollectionReference get safetyGuidesCollection => _db.collection('safety_guides');
  // Admin-managed "Hand Signals for Help" shown on the Women Safety page.
  CollectionReference get handSignalsCollection => _db.collection('hand_signals');
  // Admin-managed Women Safety resources (all 6 sections of the page).
  CollectionReference get womenSafetyCollection =>
      _db.collection('women_safety_items');
  // Admin-managed informational Panic Toolkit cards (guidance text — not the
  // interactive hardware tools which stay wired in the app).
  CollectionReference get panicToolsCollection =>
      _db.collection('panic_tools');
  // Admin-managed onboarding slides shown on the app's first-run walkthrough.
  CollectionReference get onboardingCollection =>
      _db.collection('onboarding_slides');

  // Create user profile (signup — full write)
  Future<void> createUserProfile({
    required String uid,
    required String name,
    required String email,
    required String phone,
    String? gender,
    String? bloodGroup,
    String role = UserRoles.user,
    bool phoneVerified = false,
  }) async {
    try {
      await usersCollection.doc(uid).set({
        'name': name,
        'email': email,
        'phone': phone,
        'phoneNormalized': normalizePhone(phone),
        'phoneVerified': phoneVerified,
        'gender': gender ?? '',
        'bloodGroup': bloodGroup ?? '',
        'role': UserRoles.normalize(role),
        'photoUrl': '',
        'isOnline': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error creating user profile: $e");
      rethrow;
    }
  }

  // Create profile from auth if missing (login / Google — no overwrite)
  Future<void> ensureUserProfileFromAuth(User user) async {
    try {
      final doc = await usersCollection.doc(user.uid).get();
      if (doc.exists) return;

      final phone = user.phoneNumber ?? '';
      await usersCollection.doc(user.uid).set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        'phone': phone,
        'phoneNormalized': normalizePhone(phone),
        'phoneVerified': false,
        'gender': '',
        'bloodGroup': '',
        'role': UserRoles.user,
        'photoUrl': '',
        'isOnline': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error ensuring user profile: $e");
    }
  }

  Stream<QuerySnapshot> getAppUsersStream() {
    return usersCollection.snapshots();
  }

  Future<void> updateUserRole(String uid, String role) async {
    final normalized = UserRoles.isAdminRole(role) ? UserRoles.admin : UserRoles.user;
    try {
      await usersCollection.doc(uid).set({
        'role': normalized,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error updating user role: $e");
      rethrow;
    }
  }

  Future<bool> userHasAdminRole(String uid) async {
    final data = await getUserProfile(uid);
    return UserRoles.isAdminRole(data?['role']?.toString());
  }

  Future<void> updateAdminDisplayProfile({
    required String name,
    String? photoUrl,
  }) async {
    final updates = <String, dynamic>{
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    await configCollection.doc('admin_profile').set(updates, SetOptions(merge: true));
  }

  Future<String> uploadUserAvatar(String uid, Uint8List bytes) async {
    // Free media storage via Cloudinary (no Firebase Storage / Blaze needed).
    return CloudinaryService.instance
        .uploadBytes(bytes, '$uid.jpg', type: 'image', folder: 'user_avatars');
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final doc = await usersCollection.doc(uid).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
    }
    return null;
  }

  Stream<Map<String, dynamic>?> getUserProfileStream(String uid) {
    return usersCollection.doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return snap.data() as Map<String, dynamic>?;
    });
  }

  Future<void> updateUserProfile({
    required String uid,
    required String name,
    required String email,
    required String phone,
    String? gender,
    String? bloodGroup,
    String? photoUrl,
    bool? phoneVerified,
  }) async {
    try {
      final updates = <String, dynamic>{
        'name': name,
        'email': email,
        'phone': phone,
        'phoneNormalized': normalizePhone(phone),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (phoneVerified != null) updates['phoneVerified'] = phoneVerified;
      if (gender != null) updates['gender'] = gender;
      if (bloodGroup != null) updates['bloodGroup'] = bloodGroup;
      if (photoUrl != null) updates['photoUrl'] = photoUrl;
      await usersCollection
          .doc(uid)
          .set(updates, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw Exception('Profile save timed out. Check your connection.');
    } catch (e) {
      debugPrint("Error updating user profile: $e");
      rethrow;
    }
  }

  // Seed default admin credentials on startup if not present
  Future<void> seedDefaultAdminConfig() async {
    try {
      final doc = await configCollection.doc('admin_profile').get();
      if (!doc.exists) {
        await configCollection.doc('admin_profile').set({
          'email': 'admin@smartsafe.com',
          'phone': '03001234567',
          'password': 'adminpassword123',
          'name': 'SmartSafe Admin',
          'photoUrl': '',
          'highAlertMode': false,
          'smsBackupEnabled': true,
        });
        debugPrint("Default admin profile seeded to Firebase successfully!");
      }
    } catch (e) {
      debugPrint("Error seeding default admin config: $e");
    }
  }

  // Validate admin login credentials against Firestore
  Future<bool> validateAdminCredentials(String emailOrPhone, String password) async {
    try {
      final doc = await configCollection.doc('admin_profile').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final storedEmail = data['email']?.toString().toLowerCase().trim();
          final storedPhone = data['phone']?.toString().toLowerCase().trim();
          final storedPassword = data['password']?.toString();

          final input = emailOrPhone.toLowerCase().trim();

          if ((input == storedEmail || input == storedPhone) && password == storedPassword) {
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint("Error validating credentials: $e");
    }
    return false;
  }

  // Fetch admin profile
  Future<Map<String, dynamic>?> getAdminProfile() async {
    try {
      final doc = await configCollection.doc('admin_profile').get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("Error fetching admin profile: $e");
    }
    return null;
  }

  // Update admin credentials
  Future<void> updateAdminCredentials(String email, String phone, String password) async {
    await configCollection.doc('admin_profile').update({
      'email': email.trim(),
      'phone': phone.trim(),
      'password': password,
    });
  }

  // Get admin config stream (for real-time settings updating)
  Stream<DocumentSnapshot> getAdminConfigStream() {
    return configCollection.doc('admin_profile').snapshots();
  }

  // Update specific admin config settings
  Future<void> updateAdminConfig({bool? highAlertMode, bool? smsBackupEnabled}) async {
    final Map<String, dynamic> updates = {};
    if (highAlertMode != null) updates['highAlertMode'] = highAlertMode;
    if (smsBackupEnabled != null) updates['smsBackupEnabled'] = smsBackupEnabled;
    if (updates.isNotEmpty) {
      await configCollection.doc('admin_profile').update(updates);
    }
  }

  // ── SOS Alerts CRUD ──────────────────────────────────────────
  Stream<QuerySnapshot> getAlertsStream() {
    return alertsCollection.orderBy('time', descending: true).snapshots();
  }

  Future<void> triggerAlert({required String userName, required String alertType, required String location, required String status}) async {
    await alertsCollection.add({
      'userName': userName,
      'alertType': alertType,
      'location': location,
      'status': status,
      'time': DateTime.now().toString().substring(0, 16),
    });
  }

  Future<void> updateAlertStatus(String docId, String status) async {
    await alertsCollection.doc(docId).update({'status': status});
  }

  Future<void> updateAlertDetails(String docId, {required String userName, required String alertType, required String location, required String status}) async {
    await alertsCollection.doc(docId).update({
      'userName': userName,
      'alertType': alertType,
      'location': location,
      'status': status,
    });
  }

  Future<void> deleteAlert(String docId) async {
    await alertsCollection.doc(docId).delete();
  }

  // ── Contacts CRUD ─────────────────────────────────────────────
  Stream<QuerySnapshot> getContactsStream() {
    return contactsCollection.snapshots();
  }

  Future<void> addContact({
    required String name,
    required String phone,
    required String role,
    required int colorHex,
    required bool isOnline,
    required bool smsAlert,
    required bool pushAlert,
  }) async {
    await contactsCollection.add({
      'name': name,
      'phone': phone,
      'role': role,
      'colorHex': colorHex,
      'isOnline': isOnline,
      'smsAlert': smsAlert,
      'pushAlert': pushAlert,
    });
  }

  Future<void> updateContact(
    String docId, {
    required String name,
    required String phone,
    required String role,
    required int colorHex,
    required bool isOnline,
    required bool smsAlert,
    required bool pushAlert,
  }) async {
    await contactsCollection.doc(docId).update({
      'name': name,
      'phone': phone,
      'role': role,
      'colorHex': colorHex,
      'isOnline': isOnline,
      'smsAlert': smsAlert,
      'pushAlert': pushAlert,
    });
  }

  Future<void> deleteContact(String docId) async {
    await contactsCollection.doc(docId).delete();
  }

  // ── Danger Zones CRUD ─────────────────────────────────────────
  Stream<QuerySnapshot> getDangerZonesStream() {
    return dangerZonesCollection.snapshots();
  }

  Future<void> addDangerZone({
    required String name,
    required String riskLevel,
    required String coordinates,
    required String safetyAdvice,
  }) async {
    await dangerZonesCollection.add({
      'name': name,
      'riskLevel': riskLevel,
      'coordinates': coordinates,
      'safetyAdvice': safetyAdvice,
      // Also mirror to app-list fields so admin-created zones render in the app.
      'incidentType': name,
      'location': coordinates,
      'description': safetyAdvice,
      // Admin-created zones are pre-approved (they came from the admin).
      'moderationStatus': 'approved',
      'priority': 'normal',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin accepts a pending user-reported danger zone → it now shows in the app.
  Future<void> approveDangerZone(String docId,
      {String priority = 'normal'}) async {
    await dangerZonesCollection.doc(docId).set({
      'moderationStatus': 'approved',
      'priority': priority,
      'reviewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Admin rejects a pending danger zone → it stays hidden from the app.
  Future<void> rejectDangerZone(String docId) async {
    await dangerZonesCollection.doc(docId).set({
      'moderationStatus': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateDangerZone(
    String docId, {
    required String name,
    required String riskLevel,
    required String coordinates,
    required String safetyAdvice,
  }) async {
    await dangerZonesCollection.doc(docId).update({
      'name': name,
      'riskLevel': riskLevel,
      'coordinates': coordinates,
      'safetyAdvice': safetyAdvice,
    });
  }

  Future<void> deleteDangerZone(String docId) async {
    await dangerZonesCollection.doc(docId).delete();
  }

  // ── Incident Reports CRUD ──────────────────────────────────────
  Stream<QuerySnapshot> getIncidentReportsStream() {
    return incidentReportsCollection.snapshots();
  }

  Future<void> addIncidentReport({
    required String user,
    required String incidentType,
    required String description,
    required String location,
    required String status,
  }) async {
    await incidentReportsCollection.add({
      'user': user,
      'incidentType': incidentType,
      'description': description,
      'location': location,
      'status': status,
      // Admin-created reports are pre-approved (they came from the admin).
      'moderationStatus': 'approved',
      'priority': 'normal',
      'time': DateTime.now().toString().substring(0, 16),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin accepts a pending user report → it now shows in the public app feed.
  /// [priority] is 'urgent' | 'high' | 'normal' so the admin can flag severity.
  Future<void> approveIncidentReport(String docId,
      {String priority = 'normal'}) async {
    await incidentReportsCollection.doc(docId).set({
      'moderationStatus': 'approved',
      'priority': priority,
      'reviewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Admin rejects a pending report → it stays hidden from the app.
  Future<void> rejectIncidentReport(String docId) async {
    await incidentReportsCollection.doc(docId).set({
      'moderationStatus': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateIncidentReport(
    String docId, {
    required String user,
    required String incidentType,
    required String description,
    required String location,
    required String status,
  }) async {
    await incidentReportsCollection.doc(docId).update({
      'user': user,
      'incidentType': incidentType,
      'description': description,
      'location': location,
      'status': status,
    });
  }

  Future<void> updateIncidentStatus(String docId, String status) async {
    await incidentReportsCollection.doc(docId).update({'status': status});
  }

  Future<void> deleteIncidentReport(String docId) async {
    await incidentReportsCollection.doc(docId).delete();
  }

  Stream<QuerySnapshot> getEmergencyContactsStream() =>
      emergencyContactsCollection.snapshots();

  Stream<QuerySnapshot> getSosEventsStream() => sosEventsCollection.snapshots();

  Stream<QuerySnapshot> getAppNotificationsStream() =>
      appNotificationsCollection.snapshots();

  Stream<QuerySnapshot> getSafetyTipsStream() => safetyTipsCollection.snapshots();

  Future<void> addSafetyTip({
    required String title,
    required String body,
    required String emoji,
    required int colorHex,
    int sortOrder = 0,
    String category = 'general', // 'general' | 'women'
  }) async {
    await safetyTipsCollection.add({
      'title': title,
      'body': body,
      'emoji': emoji,
      'colorHex': colorHex,
      'sortOrder': sortOrder,
      'category': category,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSafetyTip(
    String docId, {
    required String title,
    required String body,
    required String emoji,
    required int colorHex,
    String? category,
  }) async {
    await safetyTipsCollection.doc(docId).update({
      'title': title,
      'body': body,
      'emoji': emoji,
      'colorHex': colorHex,
      if (category != null) 'category': category,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteSafetyTip(String docId) async {
    await safetyTipsCollection.doc(docId).delete();
  }

  // ── Emergency Numbers (admin-managed, shown on the app's Emergency Dial) ──
  Stream<QuerySnapshot> getEmergencyNumbersStream() =>
      emergencyNumbersCollection.snapshots();

  Future<void> addEmergencyNumber({
    required String label,
    required String number,
    required String description,
    String iconKey = 'phone', // mapped to a fixed icon set in the app
    int colorHex = 0xFFE63946,
    int sortOrder = 0,
  }) async {
    await emergencyNumbersCollection.add({
      'label': label,
      'number': number,
      'description': description,
      'iconKey': iconKey,
      'colorHex': colorHex,
      'sortOrder': sortOrder,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateEmergencyNumber(
    String docId, {
    required String label,
    required String number,
    required String description,
    String? iconKey,
    int? colorHex,
    int? sortOrder,
  }) async {
    await emergencyNumbersCollection.doc(docId).update({
      'label': label,
      'number': number,
      'description': description,
      if (iconKey != null) 'iconKey': iconKey,
      if (colorHex != null) 'colorHex': colorHex,
      if (sortOrder != null) 'sortOrder': sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteEmergencyNumber(String docId) async {
    await emergencyNumbersCollection.doc(docId).delete();
  }

  // ── Emergency Will / Info (private user data — admin dashboard view only) ──
  Stream<QuerySnapshot> getEmergencyInfoStream() =>
      emergencyInfoCollection.snapshots();

  // ── Emergency Will FIELD DEFINITIONS (admin add/update/delete) ────────────
  Stream<QuerySnapshot> getWillFieldsStream() =>
      willFieldsCollection.snapshots();

  Future<void> addWillField({
    required String section,
    required int sectionOrder,
    required String label,
    required String fieldKey,
    required int order,
  }) async {
    await willFieldsCollection.add({
      'section': section,
      'sectionOrder': sectionOrder,
      'label': label,
      'fieldKey': fieldKey,
      'order': order,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateWillField(
    String docId, {
    required String section,
    required int sectionOrder,
    required String label,
    required String fieldKey,
    required int order,
  }) async {
    await willFieldsCollection.doc(docId).set({
      'section': section,
      'sectionOrder': sectionOrder,
      'label': label,
      'fieldKey': fieldKey,
      'order': order,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteWillField(String docId) async {
    await willFieldsCollection.doc(docId).delete();
  }

  /// Seeds the default Emergency Will fields once, so admins have something to
  /// edit and the app shows the standard form from day one.
  Future<void> seedWillFieldsIfEmpty() async {
    try {
      final existing = await willFieldsCollection.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      // section, sectionOrder, [ [key,label], ... ]
      const defaults = <List<dynamic>>[
        ['Personal Identity', 0, [
          ['name', 'Full Name'], ['cnic', 'CNIC'],
          ['blood', 'Blood Group'], ['dob', 'Date of Birth'],
        ]],
        ['Medical Info', 1, [
          ['allergies', 'Allergies'], ['medications', 'Medications'],
          ['conditions', 'Conditions'], ['doctor', 'Doctor'],
        ]],
        ['Financial Access', 2, [
          ['bank', 'Bank'], ['insurance', 'Insurance'],
          ['wallet', 'Mobile Wallet'],
        ]],
        ['Legal & Next of Kin', 3, [
          ['kin', 'Next of Kin'], ['property', 'Property'],
        ]],
        ['Last Wishes', 4, [
          ['message', 'Message'],
        ]],
      ];
      final batch = _db.batch();
      for (final sec in defaults) {
        final section = sec[0] as String;
        final sectionOrder = sec[1] as int;
        final fields = sec[2] as List;
        for (var i = 0; i < fields.length; i++) {
          final f = fields[i] as List;
          batch.set(willFieldsCollection.doc(), {
            'section': section,
            'sectionOrder': sectionOrder,
            'fieldKey': f[0],
            'label': f[1],
            'order': i,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('seedWillFieldsIfEmpty error: $e');
    }
  }

  // ── Safety Guides (admin-managed: Driving / Child / First-Aid pages) ──────
  // category: 'driving' | 'child' | 'first_aid'
  Stream<QuerySnapshot> getSafetyGuidesStream() =>
      safetyGuidesCollection.snapshots();

  Future<void> addSafetyGuide({
    required String category,
    required String title,
    String emoji = '📌',
    String detail = '',
    List<String> steps = const [],
    int colorHex = 0xFF00B4D8,
    bool urgent = false,
    int sortOrder = 0,
  }) async {
    await safetyGuidesCollection.add({
      'category': category,
      'title': title,
      'emoji': emoji,
      'detail': detail,
      'steps': steps,
      'colorHex': colorHex,
      'urgent': urgent,
      'sortOrder': sortOrder,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSafetyGuide(
    String docId, {
    required String category,
    required String title,
    required String emoji,
    required String detail,
    required List<String> steps,
    required int colorHex,
    required bool urgent,
    int? sortOrder,
  }) async {
    await safetyGuidesCollection.doc(docId).update({
      'category': category,
      'title': title,
      'emoji': emoji,
      'detail': detail,
      'steps': steps,
      'colorHex': colorHex,
      'urgent': urgent,
      if (sortOrder != null) 'sortOrder': sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteSafetyGuide(String docId) async {
    await safetyGuidesCollection.doc(docId).delete();
  }

  /// Seeds the built-in Driving/Child/First-Aid content into Firestore once, so
  /// admins can edit it and the app shows real guides from day one. No-op if the
  /// collection already has documents.
  Future<void> seedSafetyGuidesIfEmpty() async {
    try {
      final existing = await safetyGuidesCollection.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      final batch = _db.batch();
      for (final g in defaultSafetyGuides) {
        final ref = safetyGuidesCollection.doc(_seedId('${g.category}_${g.title}'));
        batch.set(ref, {
          'category': g.category,
          'title': g.title,
          'emoji': g.emoji,
          'detail': g.detail,
          'steps': g.steps,
          'colorHex': g.colorHex,
          'urgent': g.urgent,
          'sortOrder': g.sortOrder,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error seeding safety guides: $e');
    }
  }

  // ── Hand Signals (admin-managed: Women Safety "Hand Signals for Help") ────
  Stream<QuerySnapshot> getHandSignalsStream() =>
      handSignalsCollection.snapshots();

  Future<void> addHandSignal(HandSignal signal) async {
    await handSignalsCollection.add({
      'emoji': signal.emoji,
      'titleEn': signal.titleEn,
      'titleUr': signal.titleUr,
      'descEn': signal.descEn,
      'descUr': signal.descUr,
      'speakEn': signal.speakEn,
      'speakUr': signal.speakUr,
      'motion': signal.motion,
      'sortOrder': signal.sortOrder,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateHandSignal(String docId, HandSignal signal) async {
    await handSignalsCollection.doc(docId).update({
      'emoji': signal.emoji,
      'titleEn': signal.titleEn,
      'titleUr': signal.titleUr,
      'descEn': signal.descEn,
      'descUr': signal.descUr,
      'speakEn': signal.speakEn,
      'speakUr': signal.speakUr,
      'motion': signal.motion,
      'sortOrder': signal.sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteHandSignal(String docId) async {
    await handSignalsCollection.doc(docId).delete();
  }

  /// Seeds the built-in 5 hand signals into Firestore once, so admins can edit
  /// them and the app shows real content from day one. No-op if the collection
  /// already has documents.
  Future<void> seedHandSignalsIfEmpty() async {
    try {
      final existing = await handSignalsCollection.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      final batch = _db.batch();
      for (final s in defaultHandSignals) {
        final ref = handSignalsCollection.doc();
        batch.set(ref, {
          'emoji': s.emoji,
          'titleEn': s.titleEn,
          'titleUr': s.titleUr,
          'descEn': s.descEn,
          'descUr': s.descUr,
          'speakEn': s.speakEn,
          'speakUr': s.speakUr,
          'motion': s.motion,
          'sortOrder': s.sortOrder,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error seeding hand signals: $e');
    }
  }

  // ── Women Safety (admin-managed: all 6 sections of the Women Safety page) ──
  Stream<QuerySnapshot> getWomenSafetyStream() =>
      womenSafetyCollection.snapshots();

  Future<void> addWomenSafetyItem(WomenSafetyItem item) async {
    await womenSafetyCollection.add({
      'category': item.category,
      'title': item.title,
      'subtitle': item.subtitle,
      'items': item.items,
      'emoji': item.emoji,
      'iconName': item.iconName,
      'number': item.number,
      'colorHex': item.colorHex,
      'sortOrder': item.sortOrder,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateWomenSafetyItem(String docId, WomenSafetyItem item) async {
    // Use set(merge) instead of update(): update() throws if the doc doesn't
    // exist (e.g. editing a default item that was never written to Firestore),
    // which made "Save" silently fail. set(merge) always works.
    await womenSafetyCollection.doc(docId).set({
      'category': item.category,
      'title': item.title,
      'subtitle': item.subtitle,
      'items': item.items,
      'emoji': item.emoji,
      'iconName': item.iconName,
      'number': item.number,
      'colorHex': item.colorHex,
      'sortOrder': item.sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteWomenSafetyItem(String docId) async {
    await womenSafetyCollection.doc(docId).delete();
  }

  /// Seeds the built-in Women Safety content into Firestore once, so admins can
  /// edit it and the app shows real content from day one. No-op if the
  /// collection already has documents.
  Future<void> seedWomenSafetyIfEmpty() async {
    try {
      final existing = await womenSafetyCollection.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      final batch = _db.batch();
      for (final w in defaultWomenSafetyItems) {
        final ref = womenSafetyCollection.doc();
        batch.set(ref, {
          'category': w.category,
          'title': w.title,
          'subtitle': w.subtitle,
          'items': w.items,
          'emoji': w.emoji,
          'iconName': w.iconName,
          'number': w.number,
          'colorHex': w.colorHex,
          'sortOrder': w.sortOrder,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error seeding women safety items: $e');
    }
  }

  // ── Panic Toolkit (admin-managed: informational cards on the Panic page) ───
  Stream<QuerySnapshot> getPanicToolsStream() =>
      panicToolsCollection.snapshots();

  Future<void> addPanicTool(PanicTool tool) async {
    await panicToolsCollection.add({
      'category': tool.category,
      'title': tool.title,
      'description': tool.description,
      'steps': tool.steps,
      'emoji': tool.emoji,
      'iconName': tool.iconName,
      'colorHex': tool.colorHex,
      'sortOrder': tool.sortOrder,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePanicTool(String docId, PanicTool tool) async {
    await panicToolsCollection.doc(docId).update({
      'category': tool.category,
      'title': tool.title,
      'description': tool.description,
      'steps': tool.steps,
      'emoji': tool.emoji,
      'iconName': tool.iconName,
      'colorHex': tool.colorHex,
      'sortOrder': tool.sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deletePanicTool(String docId) async {
    await panicToolsCollection.doc(docId).delete();
  }

  /// Seeds the built-in Panic Toolkit guidance into Firestore once, so admins
  /// can edit it and the app shows real content from day one. No-op if the
  /// collection already has documents.
  Future<void> seedPanicToolsIfEmpty() async {
    try {
      final existing = await panicToolsCollection.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      final batch = _db.batch();
      for (final t in defaultPanicTools) {
        final ref = panicToolsCollection.doc(_seedId('${t.category}_${t.title}'));
        batch.set(ref, {
          'category': t.category,
          'title': t.title,
          'description': t.description,
          'steps': t.steps,
          'emoji': t.emoji,
          'iconName': t.iconName,
          'colorHex': t.colorHex,
          'sortOrder': t.sortOrder,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error seeding panic tools: $e');
    }
  }

  /// The Home screen's "Safety Tips" list reads `safety_tips`, which was only
  /// ever populated by the dashboard DEMO seeder — so a real install showed
  /// "No safety tips available yet". Seed them once (idempotent: a no-op when
  /// the collection already has documents, so admin edits/deletions stick).
  Future<void> seedSafetyTipsIfEmpty() async {
    try {
      final existing = await safetyTipsCollection.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      const tips = [
        {'title': 'Night travel', 'body': 'Avoid isolated roads after 10 PM. Share your route with family before leaving.', 'emoji': '🌙', 'color': 0xFFF4A261, 'order': 0},
        {'title': 'Silent SOS', 'body': 'Enable Silent SOS mode so your screen stays dark while sending alerts.', 'emoji': '📱', 'color': 0xFF00B4D8, 'order': 1},
        {'title': 'Driving safely', 'body': 'Keep crash detection ON while driving. The app monitors your phone automatically.', 'emoji': '🚗', 'color': 0xFF06D6A0, 'order': 2},
        {'title': 'Trusted circle', 'body': 'Add at least 3 contacts. Make sure they have SmartSafe installed for push alerts.', 'emoji': '👥', 'color': 0xFF9B5DE5, 'order': 3},
        {'title': 'Shake for help', 'body': 'Shake your phone 3× rapidly to fire an SOS instantly — no need to unlock or open the app.', 'emoji': '🆘', 'color': 0xFFE63946, 'order': 4},
        {'title': 'GPS always on', 'body': 'Enable background location access so real-time tracking works when it matters.', 'emoji': '📍', 'color': 0xFF00B4D8, 'order': 5},
        {'title': 'Battery life', 'body': 'Keep your phone charged above 20% so emergency services stay reachable.', 'emoji': '🔋', 'color': 0xFFF4A261, 'order': 6},
        {'title': 'Trust your instinct', 'body': 'If a place or person feels wrong, leave. Do not wait for proof — walk toward people and light.', 'emoji': '⚠️', 'color': 0xFFE63946, 'order': 7},
      ];
      final batch = _db.batch();
      for (final t in tips) {
        batch.set(safetyTipsCollection.doc(_seedId(t['title'].toString())), {
          'title': t['title'],
          'body': t['body'],
          'emoji': t['emoji'],
          'colorHex': t['color'],
          'sortOrder': t['order'],
          'category': 'general',
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error seeding safety tips: $e');
    }
  }

  // ── Onboarding (admin-managed: the app's first-run walkthrough slides) ─────
  Stream<QuerySnapshot> getOnboardingStream() =>
      onboardingCollection.snapshots();

  Future<void> addOnboardingSlide(OnboardingSlide slide) async {
    await onboardingCollection.add({
      'emoji': slide.emoji,
      'title': slide.title,
      'subtitle': slide.subtitle,
      'colorHex': slide.colorHex,
      'sortOrder': slide.sortOrder,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateOnboardingSlide(String docId, OnboardingSlide slide) async {
    await onboardingCollection.doc(docId).update({
      'emoji': slide.emoji,
      'title': slide.title,
      'subtitle': slide.subtitle,
      'colorHex': slide.colorHex,
      'sortOrder': slide.sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteOnboardingSlide(String docId) async {
    await onboardingCollection.doc(docId).delete();
  }

  /// Seeds the built-in onboarding slides into Firestore once, so admins can
  /// edit them and the walkthrough shows real content from day one. No-op if the
  /// collection already has documents.
  Future<void> seedOnboardingIfEmpty() async {
    try {
      final existing = await onboardingCollection.limit(1).get();
      if (existing.docs.isNotEmpty) return;
      final batch = _db.batch();
      for (final s in defaultOnboardingSlides) {
        final ref = onboardingCollection.doc();
        batch.set(ref, {
          'emoji': s.emoji,
          'title': s.title,
          'subtitle': s.subtitle,
          'colorHex': s.colorHex,
          'sortOrder': s.sortOrder,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error seeding onboarding slides: $e');
    }
  }

  Future<void> markAppNotificationRead(String docId) async {
    await appNotificationsCollection.doc(docId).update({'isRead': true});
  }

  Future<void> deleteAppNotification(String docId) async {
    await appNotificationsCollection.doc(docId).delete();
  }

  // Pre-seed some default demo data for first launch if Firestore collections are empty
  Future<void> seedInitialDemoData() async {
    try {
      final snapshots = await Future.wait([
        alertsCollection.limit(1).get(),
        contactsCollection.limit(1).get(),
        dangerZonesCollection.limit(1).get(),
        incidentReportsCollection.limit(1).get(),
        safetyTipsCollection.limit(1).get(),
        emergencyNumbersCollection.limit(1).get(),
      ]);

      // 1. Seed Alerts
      if (snapshots[0].docs.isEmpty) {
        await triggerAlert(userName: "Amina Khan", alertType: "Critical SOS", location: "33.6844, 73.0479 (Sector G-9)", status: "Active");
        await triggerAlert(userName: "Zainab Malik", alertType: "Crash Detected", location: "33.7116, 73.0588 (Blue Area)", status: "Active");
        await triggerAlert(userName: "Sara Khan", alertType: "Silent SOS", location: "33.6215, 73.0901 (Highway Rd)", status: "Resolved");
      }

      // 2. Seed Contacts
      if (snapshots[1].docs.isEmpty) {
        await addContact(name: "Mama", phone: "0300-1234567", role: "Primary emergency contact", colorHex: 0xFFE63946, isOnline: true, smsAlert: true, pushAlert: true);
        await addContact(name: "Bhai Ahmed", phone: "0321-9876543", role: "Family — brother", colorHex: 0xFF00B4D8, isOnline: true, smsAlert: true, pushAlert: true);
        await addContact(name: "Sara (Friend)", phone: "0333-5551234", role: "Close friend", colorHex: 0xFF9B5DE5, isOnline: false, smsAlert: true, pushAlert: false);
      }

      // 3. Seed Danger Zones
      if (snapshots[2].docs.isEmpty) {
        await addDangerZone(name: "G-9 Markaz Back Alley", riskLevel: "High", coordinates: "33.6855, 73.0490", safetyAdvice: "Avoid isolated walking after 10 PM. Patrol cars active nearby.");
        await addDangerZone(name: "I-8 Dark Sector underpass", riskLevel: "Medium", coordinates: "33.6620, 73.0850", safetyAdvice: " streetlight malfunction. Keep your doors locked.");
        await addDangerZone(name: "Rawal Lake side loop road", riskLevel: "Low", coordinates: "33.7020, 73.1250", safetyAdvice: "Low visibility during fog. Drive carefully.");
      }

      // 4. Seed Incident Reports
      if (snapshots[3].docs.isEmpty) {
        await addIncidentReport(user: "Zahid Ahmed", incidentType: "Theft", location: "Underpass G-8/4", description: "Streetlight malfunction, high danger of theft.", status: "Reviewing");
        await addIncidentReport(user: "Kashif Ali", incidentType: "Other", location: "Sector F-10/2", description: "Suspicious Vehicle Spotted: Black tinted sedan without plates roaming.", status: "Investigating");
        await addIncidentReport(user: "Aisha Rehman", incidentType: "Theft", location: "Blue Area Mall Parking", description: "Snatching Incident: Mobile snatching at gunpoint.", status: "Resolved");
      }

      // 5. Seed Safety Tips (synced with mobile app)
      if (snapshots[4].docs.isEmpty) {
        const tips = [
          {'title': 'Night travel', 'body': 'Avoid isolated roads after 10 PM. Share your route with family before leaving.', 'emoji': '🌙', 'color': 0xFFF4A261, 'order': 0},
          {'title': 'Silent SOS', 'body': 'Enable Silent SOS mode so your screen stays dark while sending alerts.', 'emoji': '📱', 'color': 0xFF00B4D8, 'order': 1},
          {'title': 'Driving safely', 'body': 'Keep crash detection ON while driving. App monitors your phone automatically.', 'emoji': '🚗', 'color': 0xFF06D6A0, 'order': 2},
          {'title': 'Trusted circle', 'body': 'Add at least 3 contacts. Make sure they have SmartSafe installed for push alerts.', 'emoji': '👥', 'color': 0xFF9B5DE5, 'order': 3},
          {'title': 'GPS always on', 'body': 'Enable background location access for real-time tracking to work at all times.', 'emoji': '📍', 'color': 0xFFE63946, 'order': 4},
          {'title': 'Battery life', 'body': 'Keep your phone charged above 20% for emergency services to always be accessible.', 'emoji': '🔋', 'color': 0xFFF4A261, 'order': 5},
        ];
        for (final t in tips) {
          await addSafetyTip(
            title: t['title'] as String,
            body: t['body'] as String,
            emoji: t['emoji'] as String,
            colorHex: t['color'] as int,
            sortOrder: t['order'] as int,
          );
        }
      }

      // 6. Seed Emergency Numbers (admin-managed, shown on the app dial page)
      if (snapshots[5].docs.isEmpty) {
        const numbers = [
          {'label': 'Ambulance', 'number': '1122', 'desc': 'Rescue & Emergency Service', 'icon': 'hospital', 'color': 0xFFE63946, 'order': 0},
          {'label': 'Police', 'number': '15', 'desc': 'Pakistan Police Emergency', 'icon': 'police', 'color': 0xFF00B4D8, 'order': 1},
          {'label': 'Madadgar', 'number': '1099', 'desc': 'Women & Child Safety Helpline', 'icon': 'support', 'color': 0xFF9B5DE5, 'order': 2},
          {'label': 'Edhi Foundation', 'number': '115', 'desc': 'Free ambulance nationwide', 'icon': 'emergency', 'color': 0xFF06D6A0, 'order': 3},
          {'label': 'Child Helpline', 'number': '1121', 'desc': 'Child abuse & protection', 'icon': 'child', 'color': 0xFFF4A261, 'order': 4},
          {'label': 'Fire Brigade', 'number': '16', 'desc': 'Fire emergency', 'icon': 'fire', 'color': 0xFFE63946, 'order': 5},
          {'label': 'Rozan Counseling', 'number': '0800-22444', 'desc': 'Free counseling & support', 'icon': 'support', 'color': 0xFF00B4D8, 'order': 6},
          {'label': 'CPLC', 'number': '021-35662000', 'desc': 'Crime reporting Karachi', 'icon': 'security', 'color': 0xFF9B5DE5, 'order': 7},
        ];
        for (final n in numbers) {
          await addEmergencyNumber(
            label: n['label'] as String,
            number: n['number'] as String,
            description: n['desc'] as String,
            iconKey: n['icon'] as String,
            colorHex: n['color'] as int,
            sortOrder: n['order'] as int,
          );
        }
      }
    } catch (e) {
      debugPrint("Error seeding initial data: $e");
    }
  }
}
