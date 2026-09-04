import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/models/models.dart';
import 'package:smartsafe/models/sos_history_entry.dart';
import 'package:smartsafe/services/presence_service.dart';
import 'package:smartsafe/utils/phone_utils.dart';
import 'package:smartsafe/services/location_service.dart';
import 'package:smartsafe/services/chat_service.dart';
import 'package:smartsafe/services/offline_sos_cache.dart';
/// App ↔ Dashboard shared Firestore data (contacts, SOS, notifications, tips).
class AppFirestoreService {
  static final AppFirestoreService instance = AppFirestoreService._internal();
  AppFirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get emergencyContacts =>
      _db.collection('emergency_contacts');
  CollectionReference<Map<String, dynamic>> get sosEvents =>
      _db.collection('sos_events');
  CollectionReference<Map<String, dynamic>> get appNotifications =>
      _db.collection('app_notifications');
  CollectionReference<Map<String, dynamic>> get safetyTips =>
      _db.collection('safety_tips');
  CollectionReference<Map<String, dynamic>> get incidentReports =>
      _db.collection('incident_reports');
  CollectionReference<Map<String, dynamic>> get dangerZones =>
      _db.collection('danger_zones');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // Cached per-user watch streams. The pages call these from build(), and a
  // fresh stream per call re-subscribed a new Firestore listener on EVERY
  // rebuild (home alone re-created 6+ listeners per setState). Firestore
  // `snapshots()` is broadcast, so one cached instance per key serves every
  // StreamBuilder; the SDK detaches the network listener when the last
  // subscriber cancels, so an unlistened cached stream costs nothing.
  final _contactsStreamByUid = <String, Stream<List<Contact>>>{};
  final _sosHistoryStreamByUid = <String, Stream<List<SosHistoryEntry>>>{};
  final _notifStreamByUid = <String, Stream<List<AppNotif>>>{};
  final _unreadCountStreamByUid = <String, Stream<int>>{};
  Stream<List<SafetyTip>>? _safetyTipsStream;

  Map<String, dynamic> _userMeta() {
    final user = FirebaseAuth.instance.currentUser;
    return {
      'userId': user?.uid ?? '',
      'userName': user?.displayName ?? '',
      'userEmail': user?.email ?? '',
    };
  }

  Future<Map<String, dynamic>> _userMetaWithProfile() async {
    final meta = _userMeta();
    final uid = meta['userId']?.toString();
    if (uid == null || uid.isEmpty) return meta;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final name = snap.data()?['name']?.toString();
      if (name != null && name.isNotEmpty) {
        meta['userName'] = name;
      }
    } catch (_) {}
    return meta;
  }

  // ── Emergency contacts ───────────────────────────────────────

  Stream<List<Contact>> watchMyEmergencyContacts() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    // One shared broadcast stream per user. isBroadcast makes Stream.multi
    // run its setup PER subscriber with a per-subscriber controller, so each
    // StreamBuilder gets its own Firestore/presence listeners and
    // controller.onCancel cleans them up on unsubscribe. (The explicit
    // Stream<List<Contact>> type is required: the ??= index-assignment
    // doesn't give inference enough context on its own.)
    return _contactsStreamByUid[uid] ??=
        Stream<List<Contact>>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? latestContacts;
      Map<String, bool> onlineByPhone = {};
      StreamSubscription? presenceSub;

      void emit() {
        if (latestContacts == null) return;
        controller.add(_mapContacts(latestContacts!, onlineByPhone));
      }

      void subscribeToPresence(List<String> phones) {
        presenceSub?.cancel();
        if (phones.isEmpty) {
          onlineByPhone = {};
          emit();
          return;
        }

        final queryPhones = phones.take(30).toList();
        presenceSub = PresenceService.instance.watchOnlineForPhones(queryPhones).listen((map) {
          onlineByPhone = map;
          emit();
        });
      }

      final contactSub = emergencyContacts
          .where('userId', isEqualTo: uid)
          .snapshots()
          .listen((snap) {
        latestContacts = snap;

        final List<String> phones = [];
        for (final doc in snap.docs) {
          final rawPhone = doc.data()['phone']?.toString() ?? '';
          final norm = normalizePhone(rawPhone);
          if (norm.isNotEmpty) phones.add(norm);
        }

        subscribeToPresence(phones);
        emit();

        // Warm the offline SOS cache so an emergency fired with NO internet can
        // still SIM-call / SIM-SMS these contacts.
        OfflineSosCache.saveContacts(
          snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList(),
        );
      });

      controller.onCancel = () {
        contactSub.cancel();
        presenceSub?.cancel();
      };
    }, isBroadcast: true);
  }

  Future<List<Contact>> getEmergencyContacts() async {
    final uid = _uid;
    if (uid == null) return [];

    final snap = await emergencyContacts.where('userId', isEqualTo: uid).get();
    
    // For single fetch, we might not need live online status, but let's just get the contacts
    // and default isOnline to false, or we can fetch it if really needed.
    return _mapContacts(snap, {});
  }

  List<Contact> _mapContacts(
    QuerySnapshot<Map<String, dynamic>> snap,
    Map<String, bool> onlineByPhone,
  ) {
    return snap.docs.map((doc) {
      final d = doc.data();
      final phone = d['phone']?.toString() ?? '';
      final phoneKey = (d['phoneNormalized']?.toString().isNotEmpty == true)
          ? d['phoneNormalized'].toString()
          : normalizePhone(phone);
      return Contact(
        id: doc.id,
        name: d['name']?.toString() ?? '',
        phone: phone,
        role: d['relationship']?.toString() ?? d['role']?.toString() ?? '',
        color: Color(d['colorHex'] as int? ?? 0xFF9B5DE5),
        isOnline: phoneKey.isNotEmpty && onlineByPhone[phoneKey] == true,
        smsAlert: d['smsAlert'] != false,
        pushAlert: d['pushAlert'] != false,
        callAlert: d['callAlert'] != false,
      );
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> addEmergencyContact({
    required String name,
    required String phone,
    String? email,
    required String relationship,
    required int colorHex,
    required bool smsAlert,
    required bool pushAlert,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Login required to save contacts');

    final meta = await _userMetaWithProfile();
    final phoneTrim = phone.trim();
    await emergencyContacts.add({
      ...meta,
      'name': name.trim(),
      'phone': phoneTrim,
      'email': email?.trim(),
      'phoneNormalized': normalizePhone(phoneTrim),
      'relationship': relationship,
      'colorHex': colorHex,
      'smsAlert': smsAlert,
      'pushAlert': pushAlert,
      'callAlert': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _notifyAdmin(
      title: 'New emergency contact',
      body: '${meta['userName'] ?? 'User'} added $name ($phone)',
      type: 'contact',
    );
  }

  Future<void> deleteEmergencyContact(String docId) async {
    await emergencyContacts.doc(docId).delete();
  }

  /// Toggle which channels a contact receives during an SOS (call / SMS / push).
  Future<void> updateContactChannel(String docId, String field, bool value) async {
    if (docId.isEmpty) return;
    await emergencyContacts.doc(docId).update({
      field: value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Picks the ONE contact to auto-call on SOS (a phone can only call one at a
  /// time). Sets callAlert=true for [docId] and false for all your others.
  Future<void> setCallContact(String docId) async {
    final uid = _uid;
    if (uid == null || docId.isEmpty) return;
    final snap = await emergencyContacts.where('userId', isEqualTo: uid).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {
        'callAlert': d.id == docId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // ── SOS events ─────────────────────────────────────────────

  Future<void> recordSosPress({
    required String source,
    String location = 'Location pending',
    String alertType = 'Critical SOS',
  }) async {
    final uid = _uid;
    if (uid == null) return;

    // ONE profile read (the old code fetched the same `users/{uid}` doc twice:
    // once via _userMetaWithProfile and once right below).
    String? profileName;
    String myPhone = '';
    try {
      final snap = await _db.collection('users').doc(uid).get();
      profileName = snap.data()?['name']?.toString();
      myPhone = snap.data()?['phone']?.toString() ?? '';
    } catch (_) {}
    final meta = _userMeta();
    final displayName = (profileName != null && profileName.isNotEmpty)
        ? profileName
        : (meta['userName']?.toString().isNotEmpty == true
            ? meta['userName']
            : meta['userEmail'] ?? 'User');

    // Try to get live location
    String finalLocation = location;
    if (LocationService.instance.isTracking) {
      try {
        final loc = await LocationService.instance.onLocationChanged.first.timeout(const Duration(seconds: 3));
        finalLocation = '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
      } catch (_) {
        // Fallback to the original location param if timeout
      }
    }

    // The SOS log + dashboard alert + admin ping are independent → run them
    // concurrently instead of one-after-another.
    await Future.wait([
      sosEvents.add({
        ...meta,
        'userName': displayName,
        'source': source,
        'location': finalLocation,
        'alertType': alertType,
        'status': 'Active',
        'createdAt': FieldValue.serverTimestamp(),
      }),
      _db.collection('alerts').add({
        'userId': uid,
        'userName': displayName,
        'alertType': alertType,
        'location': finalLocation,
        'status': 'Active',
        'time': DateTime.now().toString().substring(0, 16),
        'source': source,
      }),
      _notifyAdmin(
        title: 'SOS triggered',
        body: '$displayName pressed SOS ($source)',
        type: 'sos',
        userId: uid,
      ),
    ]);

    // Notify trusted contacts and send chat messages, trigger Twilio, etc.
    // Every contact's work runs IN PARALLEL (the old sequential loop turned N
    // contacts into N×(query + write + chat write) of end-to-end delay while
    // the user waited on the alert screen).
    try {
      final contactsSnap =
          await emergencyContacts.where('userId', isEqualTo: uid).get();
      await Future.wait(contactsSnap.docs.map((doc) async {
        final cPhone = doc.data()['phone']?.toString() ?? '';
        final cEmail = doc.data()['email']?.toString();

        // Resolve the contact's real uid so the alert lands in their feed.
        // Fall back to the sender's uid if the contact isn't a registered user.
        String targetUserId = uid;
        try {
          final normalized = normalizePhone(cPhone);
          if (normalized.isNotEmpty) {
            final userMatch = await _db
                .collection('users')
                .where('phoneNormalized', isEqualTo: normalized)
                .limit(1)
                .get();
            if (userMatch.docs.isNotEmpty) {
              targetUserId = userMatch.docs.first.id;
            }
          }
        } catch (_) {}

        await appNotifications.add({
          'userId': targetUserId,
          'contactPhone': cPhone,
          'contactEmail': cEmail, // Backend will use this to send email
          'title': 'Emergency Alert from $displayName',
          'body': '$displayName needs help! Location: $finalLocation',
          'type': 'sos',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Send a direct chat message
        if (myPhone.isNotEmpty && cPhone.isNotEmpty) {
          await ChatService.instance.sendMessage(
            myPhone: myPhone,
            otherPhone: cPhone,
            message: "🚨 I am not safe please help me. Location: $finalLocation",
            isOfflineSms: false,
          );
        }
      }));
    } catch (e) {
      debugPrint('Error notifying contacts: $e');
    }
  }

  /// Marks the user's most recent active SOS as cancelled and records it
  /// for the dashboard + the user's own notification feed.
  Future<void> recordSosCancel({String senderName = 'User'}) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      // Flip the latest Active SOS event to Cancelled.
      final activeSnap = await sosEvents
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'Active')
          .get();
      for (final doc in activeSnap.docs) {
        await doc.reference.update({
          'status': 'Cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      }

      // Mirror into the alerts collection used by the dashboard.
      final activeAlerts =
          await _db.collection('alerts').where('userId', isEqualTo: uid).where('status', isEqualTo: 'Active').get();
      for (final doc in activeAlerts.docs) {
        await doc.reference.update({'status': 'Cancelled'});
      }
    } catch (e) {
      print('recordSosCancel error: $e');
    }

    // Notify the user's own feed + the admin.
    await _notifyAdmin(
      title: 'SOS cancelled',
      body: '$senderName marked themselves safe',
      type: 'sos',
      userId: uid,
    );
  }

  Stream<List<SosHistoryEntry>> watchMySosHistory() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _sosHistoryStreamByUid[uid] ??=
        sosEvents.where('userId', isEqualTo: uid).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => SosHistoryEntry.fromFirestore(d.id, d.data()))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<int> getMySosPressCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    final snap = await sosEvents.where('userId', isEqualTo: uid).get();
    return snap.docs.length;
  }

  // ── App notifications (user feed) ──────────────────────────

  Future<void> _notifyAdmin({
    required String title,
    required String body,
    required String type,
    String? userId,
  }) async {
    await appNotifications.add({
      'userId': userId ?? _uid ?? '',
      'title': title,
      'body': body,
      'type': type,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Persists an incoming alert into the signed-in user's bell-tab feed.
  ///
  /// The realtime `notifications` docs that drive [CommunitySosWatcher] are
  /// transient (a heads-up dialog + system push) — once dismissed they vanish.
  /// This mirrors them into `app_notifications` so the user can still find the
  /// SOS later in the Notifications tab.
  ///
  /// [sourceId] is the originating `notifications` doc id; we derive a stable
  /// feed doc id from it so the same alert is never written twice (e.g. across
  /// app restarts when the unread doc re-triggers), and the read state set by
  /// the user is preserved.
  Future<void> saveToMyFeed({
    required String sourceId,
    required String title,
    required String body,
    String type = 'sos',
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final ref = appNotifications.doc('feed_$sourceId');
      if ((await ref.get()).exists) return; // already mirrored
      await ref.set({
        'userId': uid,
        'title': title,
        'body': body,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('saveToMyFeed error: $e');
    }
  }

  Stream<List<AppNotif>> watchMyNotifications() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    // Include both this user's own notifications AND admin broadcasts
    // ('userId' == 'all') — so every user, even one who registers later, sees
    // announcements the admin sent to everyone.
    return _notifStreamByUid[uid] ??= appNotifications
        .where('userId', whereIn: [uid, 'all'])
        .limit(50)
        .snapshots()
        .map((snap) => _mapNotifs(snap, uid));
  }

  Stream<List<AppNotif>> watchAllNotifications() {
    return appNotifications
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(_mapNotifs);
  }

  List<AppNotif> _mapNotifs(QuerySnapshot<Map<String, dynamic>> snap,
      [String? uid]) {
    return snap.docs.map((doc) {
      final d = doc.data();
      final ts = d['createdAt'];
      DateTime time = DateTime.now();
      if (ts is Timestamp) time = ts.toDate();
      // A broadcast ('userId' == 'all') is read PER USER via a readBy list, so
      // one person reading it doesn't mark it read for everyone else.
      final isBroadcast = d['userId'] == 'all';
      final readBy = (d['readBy'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      final isRead = isBroadcast
          ? (uid != null && readBy.contains(uid))
          : d['isRead'] == true;
      return AppNotif(
        id: doc.id,
        title: d['title']?.toString() ?? '',
        body: d['body']?.toString() ?? '',
        time: time,
        type: _parseAlertType(d['type']?.toString()),
        isRead: isRead,
      );
    }).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
  }

  Stream<int> watchUnreadNotificationCount() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _unreadCountStreamByUid[uid] ??= watchMyNotifications()
        .map((list) => list.where((n) => !n.isRead).length);
  }

  AlertType _parseAlertType(String? t) {
    switch (t) {
      case 'sos':
        return AlertType.sos;
      case 'crash':
        return AlertType.crash;
      case 'safe':
        return AlertType.safe;
      case 'gps':
        return AlertType.gps;
      case 'contact':
        return AlertType.contact;
      case 'route':
        return AlertType.route;
      default:
        return AlertType.sos;
    }
  }

  /// ADMIN — compose and send a notification to users.
  ///
  /// Writes one `app_notifications` doc per recipient, which is exactly the
  /// shape the app's Notifications page streams (`userId == me`), so recipients
  /// see it live. Pass [targetUserId] to send to one person, or leave it null to
  /// broadcast to every registered user.
  ///
  /// Returns how many users it was delivered to.
  Future<int> sendAdminNotification({
    required String title,
    required String body,
    String type = 'contact',
    String? targetUserId,
  }) async {
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty && b.isEmpty) return 0;

    // Broadcast to everyone → ONE doc (userId == 'all'), which EVERY user's
    // feed reads. This fixes two things at once:
    //  • the dashboard list no longer shows the same notification once per user
    //    (it's a single doc now), and
    //  • users who register LATER still receive it (the feed query includes
    //    'all'), not just the users who existed at send time.
    // Per-user read state lives in `readBy`.
    if (targetUserId == null || targetUserId.isEmpty) {
      await appNotifications.add({
        'userId': 'all',
        'title': t,
        'body': b,
        'type': type,
        'readBy': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'fromAdmin': true,
      });
      // Report an approximate reach for the admin's confirmation message.
      try {
        final users = await _db.collection('users').get();
        return users.docs.length;
      } catch (_) {
        return 1;
      }
    }

    // One specific user → a single targeted doc.
    await appNotifications.add({
      'userId': targetUserId,
      'title': t,
      'body': b,
      'type': type,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'fromAdmin': true,
    });
    return 1;
  }

  Future<void> markNotificationRead(String docId) async {
    final uid = _uid;
    final ref = appNotifications.doc(docId);
    final snap = await ref.get();
    // Broadcasts are marked read PER USER (readBy) — never a global isRead, or
    // it would look "read" for everyone else too.
    if (snap.data()?['userId'] == 'all') {
      if (uid != null) {
        await ref.update({'readBy': FieldValue.arrayUnion([uid])});
      }
      return;
    }
    await ref.update({'isRead': true});
  }

  Future<void> markAllNotificationsRead() async {
    final uid = _uid;
    if (uid == null) return;
    final snap =
        await appNotifications.where('userId', whereIn: [uid, 'all']).get();
    final batch = _db.batch();
    var count = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['userId'] == 'all') {
        final readBy = (d['readBy'] as List?) ?? const [];
        if (readBy.contains(uid)) continue;
        batch.update(doc.reference, {
          'readBy': FieldValue.arrayUnion([uid])
        });
        count++;
      } else {
        if (d['isRead'] == true) continue;
        batch.update(doc.reference, {'isRead': true});
        count++;
      }
    }
    if (count > 0) await batch.commit();
  }

  // ── Safety tips ──────────────────────────────────────────────

  Stream<List<SafetyTip>> watchSafetyTips() {
    return _safetyTipsStream ??= safetyTips.snapshots().map((snap) {
      if (snap.docs.isEmpty) return const <SafetyTip>[];
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final oa = (a.data()['sortOrder'] as int?) ?? 0;
          final ob = (b.data()['sortOrder'] as int?) ?? 0;
          return oa.compareTo(ob);
        });
      return docs.map((doc) {
        final d = doc.data();
        return SafetyTip(
          title: d['title']?.toString() ?? '',
          body: d['body']?.toString() ?? '',
          emoji: d['emoji']?.toString() ?? '💡',
          color: Color(d['colorHex'] as int? ?? 0xFF00B4D8),
        );
      }).toList();
    });
  }
  // ── Incident Reports (Danger Zones) ────────────────────────
  Future<void> addIncidentReport({
    required String incidentType,
    required String description,
    required String location,
    required String status,
    String? photoUrl,
    double? latitude,
    double? longitude,
  }) async {
    final meta = await _userMetaWithProfile();
    final displayName = meta['userName']?.toString().isNotEmpty == true
        ? meta['userName']
        : meta['userEmail'] ?? 'User';

    await incidentReports.add({
      'userId': meta['userId'] ?? '',
      'user': displayName, // Dashboard uses 'user' field
      'incidentType': incidentType,
      'description': description,
      'location': location,
      // Real GPS coordinates. Previously only a location STRING was stored, so
      // the dashboard could never map a report and any "location" shown had to
      // be re-parsed out of free text (which is what made it look wrong).
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'status': status,
      // Moderation: a user-submitted report is PENDING until an admin reviews
      // it in the dashboard. Only 'approved' reports appear in the public feed.
      'moderationStatus': 'pending',
      'priority': 'normal',
      if (photoUrl != null) 'photoUrl': photoUrl,
      'time': DateTime.now().toString().substring(0, 16),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> watchIncidentReports() {
    return incidentReports
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  /// Only APPROVED reports — used by the public Safety Feed so a report stays
  /// hidden until an admin accepts it. Filtered + sorted in memory to avoid a
  /// composite Firestore index. Reports with no moderationStatus (legacy) are
  /// treated as approved so existing data is never hidden.
  Stream<List<Map<String, dynamic>>> watchApprovedIncidentReports() {
    return incidentReports.snapshots().map((snap) {
      final list = snap.docs
          .map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          })
          .where((m) =>
              (m['moderationStatus']?.toString() ?? 'approved') == 'approved')
          .toList();
      list.sort((a, b) {
        final ta = a['createdAt'];
        final tb = b['createdAt'];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
        return 0;
      });
      return list;
    });
  }

  // ── Danger Zones (separate from incident reports) ──────────────
  // A user-reported danger zone goes to the `danger_zones` collection as
  // PENDING and only appears publicly once an admin approves it in the
  // dashboard's Danger Zones screen. Admin-created zones are approved on save.
  Future<void> addDangerZoneReport({
    required String incidentType,
    required String description,
    required String location,
    String riskLevel = 'Medium',
    double? latitude,
    double? longitude,
  }) async {
    final meta = await _userMetaWithProfile();
    final displayName = meta['userName']?.toString().isNotEmpty == true
        ? meta['userName']
        : meta['userEmail'] ?? 'User';
    final coordinates = (latitude != null && longitude != null)
        ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
        : location;

    await dangerZones.add({
      'userId': meta['userId'] ?? '',
      'user': displayName,
      // Dashboard "Danger Zones" table fields.
      'name': incidentType,
      'riskLevel': riskLevel,
      'coordinates': coordinates,
      'safetyAdvice': description,
      // App-list fields (kept so the app renders every zone uniformly).
      'incidentType': incidentType,
      'description': description,
      'location': location,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      // Moderation: pending until an admin approves in the dashboard.
      'moderationStatus': 'pending',
      'priority': 'normal',
      'time': DateTime.now().toString().substring(0, 16),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Only APPROVED danger zones — used by the app's Danger Zone page so a
  /// reported zone stays hidden until an admin accepts it. Filtered + sorted in
  /// memory to avoid a composite index. Zones with no moderationStatus (e.g.
  /// admin-seeded/legacy) are treated as approved so nothing is ever hidden.
  Stream<List<Map<String, dynamic>>> watchApprovedDangerZones() {
    return dangerZones.snapshots().map((snap) {
      final list = snap.docs
          .map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          })
          .where((m) =>
              (m['moderationStatus']?.toString() ?? 'approved') == 'approved')
          .toList();
      list.sort((a, b) {
        final ta = a['createdAt'];
        final tb = b['createdAt'];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
        return 0;
      });
      return list;
    });
  }

  // ── Safe Check-In ──────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get safeCheckins =>
      _db.collection('safe_checkins');

  Future<void> recordCheckIn({
    required int mins,
    required String status, // 'safe' | 'expired'
    String destination = '',
  }) async {
    final meta = _userMeta();
    await safeCheckins.add({
      ...meta,
      'mins': mins,
      'status': status,
      'destination': destination,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> watchMyCheckIns() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return safeCheckins
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList()
        ..sort((a, b) {
          final ta = a['createdAt'] as Timestamp?;
          final tb = b['createdAt'] as Timestamp?;
          if (ta == null || tb == null) return 0;
          return tb.compareTo(ta);
        });
      return list;
    });
  }
}
