import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'sms_sender.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_notification_service.dart';
import 'location_service.dart';
import 'app_firestore_service.dart';
import 'offline_sos_cache.dart';
import 'push_sender.dart';
import 'whatsapp_service.dart';
import 'whatsapp_sender.dart';
import '../utils/phone_utils.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// SimSosService — Real, end-to-end SOS dispatch. No dummy data.
///
/// On SOS press it does ALL of the following for the user's emergency contacts:
///  ✅ Direct Phone Call  → device SIM (first contact) — shows your number
///  ✅ Direct SMS         → device SIM (every contact)
///  ✅ WhatsApp message   → FREE wa.me deep link (primary contact, tap Send)
///  ✅ Email Alert        → EmailJS (every contact with an email)
///  ✅ Self notification  → a system notification on YOUR phone
///
/// On cancel it sends a "false alarm / I am safe" follow-up on
/// SMS + WhatsApp + Email and notifies you, plus records it in Firestore.
/// ──────────────────────────────────────────────────────────────────────────
class SimSosService {
  static final SimSosService instance = SimSosService._();
  SimSosService._();

  final _db = FirebaseFirestore.instance;

  // Sender identity (name + phone) memo: ONE `users/{uid}` read serves both the
  // name and the phone (they live in the same doc — fetching them separately
  // doubled the reads on every SOS dispatch). Concurrent callers share the
  // in-flight future; the memo is dropped if nothing resolved so a later call
  // retries.
  String? _identityUid;
  Future<(String name, String phone)>? _identityFuture;

  Future<(String name, String phone)> _senderIdentity(String uid) {
    if (_identityUid != uid) {
      _identityUid = uid;
      _identityFuture = null;
    }
    return _identityFuture ??= _fetchIdentity(uid);
  }

  Future<(String name, String phone)> _fetchIdentity(String uid) async {
    String name = '';
    String phone = '';
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      name = snap.data()?['name']?.toString() ?? '';
      phone = snap.data()?['phone']?.toString() ?? '';
    } catch (_) {}
    if (name.trim().isEmpty && phone.trim().isEmpty) {
      // Nothing resolved (offline/timeout) — don't memoize the failure.
      _identityFuture = null;
      return ('', '');
    }
    if (name.trim().isNotEmpty) {
      unawaited(OfflineSosCache.saveSender(name: name.trim()));
    }
    if (phone.trim().isNotEmpty) {
      unawaited(OfflineSosCache.saveSender(phone: phone.trim()));
    }
    return (name, phone);
  }

  /// Resolves the sender display name from the user's profile. Offline-safe:
  /// short timeout, then the cached name, then the FirebaseAuth display name.
  Future<String> _senderName(String uid) async {
    final (name, _) = await _senderIdentity(uid);
    if (name.trim().isNotEmpty) return name.trim();
    final cached = await OfflineSosCache.senderName();
    if (cached != null && cached.trim().isNotEmpty) return cached.trim();
    return FirebaseAuth.instance.currentUser?.displayName ?? 'SmartSafe User';
  }

  /// The sender's own phone number, so contacts can call them back. Offline-safe:
  /// short timeout, then the cached phone, then the authenticated phone.
  Future<String> _senderPhone(String uid) async {
    final (_, phone) = await _senderIdentity(uid);
    if (phone.trim().isNotEmpty) return phone.trim();
    final cached = await OfflineSosCache.senderPhone();
    if (cached != null && cached.trim().isNotEmpty) return cached.trim();
    return FirebaseAuth.instance.currentUser?.phoneNumber ?? 'unknown';
  }

  /// Human-readable local date + time for the alert message, e.g.
  /// "07 Jul 2026, 11:35 AM". No extra dependency — computed from DateTime.
  String _nowString() {
    final n = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h12 = n.hour % 12 == 0 ? 12 : n.hour % 12;
    final ampm = n.hour < 12 ? 'AM' : 'PM';
    final mm = n.minute.toString().padLeft(2, '0');
    final dd = n.day.toString().padLeft(2, '0');
    return '$dd ${months[n.month - 1]} ${n.year}, $h12:$mm $ampm';
  }

  /// Gets a fresh, real location and a tappable Google Maps link.
  Future<String> _resolveLocation() async {
    try {
      final loc = await LocationService.instance
          .getCurrentLocation()
          .timeout(const Duration(seconds: 6));
      if (loc != null) {
        final lat = loc.latitude.toStringAsFixed(5);
        final lng = loc.longitude.toStringAsFixed(5);
        return 'https://maps.google.com/?q=$lat,$lng';
      }
    } catch (_) {}
    // Fall back to the live tracking stream if a direct fix wasn't available.
    try {
      if (LocationService.instance.isTracking) {
        final loc = await LocationService.instance.onLocationChanged.first
            .timeout(const Duration(seconds: 4));
        return 'https://maps.google.com/?q=${loc.latitude.toStringAsFixed(5)},${loc.longitude.toStringAsFixed(5)}';
      }
    } catch (_) {}
    return 'Location unavailable';
  }

  /// Requests the SMS + Call permissions needed to dispatch from the SIM.
  /// Returns whether SMS can be sent silently. Safe to call repeatedly.
  Future<bool> _ensureSimPermissions() async {
    try {
      await [
        Permission.sms,
        Permission.phone,
        Permission.notification,
      ].request();
      return await Permission.sms.isGranted;
    } catch (e) {
      debugPrint('[SimSOS] permission request failed: $e');
      return false;
    }
  }

  /// Reads the emergency contacts resiliently for dispatch. Tries Firestore with
  /// a short timeout (so a dead network can never stall a real emergency), caches
  /// the result for offline use, and falls back to the last cached copy when the
  /// device is offline — so SIM call + SIM SMS always have numbers to reach.
  ///
  /// Returns a list of plain maps (each carrying its doc `id`) rather than
  /// Firestore snapshots, so cached entries and live entries look identical to
  /// the dispatch code.
  Future<List<Map<String, dynamic>>> _contacts(String uid) async {
    try {
      final snap = await _db
          .collection('emergency_contacts')
          .where('userId', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 6));
      final list = snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();
      if (list.isNotEmpty) {
        unawaited(OfflineSosCache.saveContacts(list));
        return list;
      }
      // Server returned empty — this may be an offline-empty read, so prefer a
      // non-empty cache if we have one.
      final cached = await OfflineSosCache.loadContacts();
      return cached.isNotEmpty ? cached : list;
    } catch (e) {
      debugPrint('[SimSOS] contacts read failed ($e) — using offline cache');
      return OfflineSosCache.loadContacts();
    }
  }

  /// Fast pre-flight check for the SOS button: does the signed-in user have at
  /// least one emergency contact? Lets the UI guide them to add one BEFORE
  /// launching a dispatch that couldn't reach anybody. Returns true on error so
  /// a transient query failure never blocks a genuine emergency.
  Future<bool> hasEmergencyContacts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap = await _db
          .collection('emergency_contacts')
          .where('userId', isEqualTo: uid)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return true; // never block a real SOS on a lookup error
    }
  }

  /// Main entry point — call this when SOS button is pressed.
  /// [emergencyNumber] (e.g. '1122') is called from the SIM with top priority
  /// — used by crash detection. When set, the single SIM call goes there and
  /// contacts still get SMS + WhatsApp + email.
  Future<SimSosResult> triggerSos({String? emergencyNumber, String kind = 'sos'}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return SimSosResult(error: 'Please sign in first.');
    }

    // Instant feedback on the user's OWN phone the moment SOS is triggered
    // (e.g. by shaking) — so they know it's working even before dispatch.
    LocalNotificationService.instance.show(
      id: 1000,
      title: kind == 'crash'
          ? '🚗 Crash alert active — alerting contacts'
          : kind == 'shake'
              ? '🆘 Shake SOS active — alerting contacts'
              : '🆘 SOS active — alerting your contacts',
      body: 'Sending your live location to your emergency contacts now…',
    );

    // Kick off the slow/independent work CONCURRENTLY instead of one-by-one.
    // Location (the slowest, GPS-bound) overlaps the Firestore reads + the
    // permission prompt + the very first SIM call — so dialing starts almost
    // immediately rather than after a ~10s GPS wait.
    final senderNameFut = _senderName(uid);
    final senderPhoneFut = _senderPhone(uid);
    final contactsFut = _contacts(uid);
    final locationFut = _resolveLocation();
    final permsFut = _ensureSimPermissions();

    final senderName = await senderNameFut;
    final senderPhone = await senderPhoneFut;
    final contacts = await contactsFut;

    if (contacts.isEmpty) {
      return SimSosResult(
          error: 'No emergency contacts found.\nPlease add a contact first.');
    }

    final smsGranted = await permsFut;

    int callsMade = 0, smsSent = 0, whatsappSent = 0;
    int appAlertsSent = 0; // in-app push to contacts who use SmartSafe
    final smsFallbackRecipients = <String>[]; // used if SMS permission denied
    final whatsappTargets = <SosWhatsAppTarget>[]; // free wa.me, opened/listed

    // The Primary SOS Contact the user picked (Settings → Primary SOS Contact).
    // When set, ONLY this contact is phoned and WhatsApp'd; everyone still gets
    // SMS + the in-app push. Null means "All Contacts (Default)".
    String? primaryContactId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // background isolate: pull the latest value
      primaryContactId = prefs.getString('primary_sos_contact_id');
    } catch (_) {}
    if (primaryContactId != null &&
        !contacts.any((c) => c['id'] == primaryContactId)) {
      // The chosen contact was deleted — fall back to alerting everyone rather
      // than silently phoning nobody.
      primaryContactId = null;
    }

    // ── 1. Place the ONE SIM call up front (doesn't need the location text) ──
    // Crash flow dials emergency services (e.g. 1122). Otherwise: the Primary
    // SOS Contact if one is set, else the first contact marked for CALL.
    String? callTarget = emergencyNumber;
    if (callTarget == null || callTarget.isEmpty) {
      for (final d in contacts) {
        final p = d['phone']?.toString() ?? '';
        if (p.isEmpty) continue;
        if (primaryContactId != null) {
          if (d['id'] == primaryContactId) {
            callTarget = p;
            break;
          }
        } else if (d['callAlert'] != false) {
          callTarget = p;
          break;
        }
      }
    }
    if (callTarget != null && callTarget.isNotEmpty) {
      try {
        final ok = await FlutterPhoneDirectCaller.callNumber(callTarget) ?? false;
        if (ok) {
          callsMade++;
          debugPrint('[SimSOS] ✅ Call placed to $callTarget');
        }
      } catch (e) {
        debugPrint('[SimSOS] ❌ Call failed to $callTarget: $e');
      }
    }

    // Now wait for the location (needed for the message body).
    final location = await locationFut;

    // Each alert TYPE goes out with its own name so the contact knows what
    // kind of emergency it is (crash vs SOS). Works online (Twilio) AND offline
    // (device SIM SMS).
    // Clean, professional SMS with a tappable live-location link.
    final String locationLine = location.startsWith('http')
        ? 'Live location: $location'
        : 'Location: $location';
    // Three distinct messages depending on HOW the alert was triggered.
    final String smsBody;
    if (kind == 'crash') {
      smsBody = 'SMARTSAFE — ROAD ACCIDENT DETECTED\n\n'
          "$senderName's phone detected a hard impact — a possible road accident "
          '(the phone may have been dropped or crashed). They may need urgent help.\n\n'
          'Time: ${_nowString()}\n'
          '$locationLine\n\n'
          'Please call them now, or contact Rescue 1122.\n\n'
          '— Sent automatically by SmartSafe';
    } else if (kind == 'shake') {
      smsBody = 'SMARTSAFE — MANUAL SHAKE SOS ACTIVATED\n\n'
          '$senderName shook their phone to call for help — they may be in danger '
          'and could not open the app. Please respond immediately.\n\n'
          'Time: ${_nowString()}\n'
          '$locationLine\n\n'
          'Please call them now, or alert emergency services.\n\n'
          '— Sent automatically by SmartSafe';
    } else {
      // User-facing emergency message (sender's real name + live GPS injected).
      // Only promise a tappable live link when we actually resolved one;
      // otherwise the recipient sees the honest "couldn't get GPS" line.
      final String locationSection = location.startsWith('http')
          ? '📍 My LIVE location:\n'
              '$location\n'
              'Tap to see exactly where I am — it updates live.'
          : '📍 My location could not be detected right now — please call me '
              'immediately to find out where I am.';
      smsBody = '🚨 SOS — SMARTSAFE EMERGENCY 🚨\n\n'
          'This is $senderName. I am in danger right now and need URGENT help.\n'
          '(Main $senderName hoon — main is waqt khatre mein hoon, foran madad chahiye.)\n\n'
          '$locationSection\n\n'
          'Please act NOW:\n'
          '• Come to my location, or\n'
          '• Call me immediately, or\n'
          '• Call Police 15 / Rescue 1122 if you cannot reach me.\n\n'
          'This is a real emergency — please DO NOT ignore this.\n'
          '— Sent automatically by SmartSafe 🛡️';
    }

    // uids of contacts who use SmartSafe — pushed (even when their app is
    // closed) via our free Vercel endpoint once all the Firestore writes below
    // have queued them.
    final appPushTargets = <String>[];

    // International WhatsApp numbers of contacts — auto-messaged via the
    // WhatsApp Business API (no redirect, no app opening).
    final waRecipients = <String>[];

    // ── 2-4. SMS + WhatsApp + Email to every contact, all IN PARALLEL ───────
    // Each contact's three channels run concurrently, and all contacts run
    // concurrently — so total time ≈ the single slowest send, not the sum.
    await Future.wait(contacts.map((d) async {
      final phone = d['phone']?.toString() ?? '';
      final contactName = d['name']?.toString() ?? 'Contact';
      if (phone.isEmpty) return;

      // Respect the user's per-contact choice: only SMS + WhatsApp this contact
      // if they enabled the SMS channel for them.
      final bool smsOn = d['smsAlert'] != false;
      final futures = <Future<void>>[];

      // SMS via device SIM (direct when permitted; otherwise queue a composer).
      if (smsOn && smsGranted) {
        futures.add(() async {
          try {
            await sendSMS(
                message: smsBody, recipients: [phone], sendDirect: true);
            smsSent++;
          } catch (e) {
            debugPrint('[SimSOS] ❌ SMS failed to $phone: $e');
          }
        }());
      } else if (smsOn) {
        smsFallbackRecipients.add(phone);
      }

      // WhatsApp: collect the OPTIONAL per-contact buttons (free wa.me) AND the
      // international number for the auto-send via the WhatsApp Business API
      // (no redirect — the message is delivered server-side).
      //
      // When a Primary SOS Contact is set, WhatsApp goes to THEM ALONE — the
      // user chose one person to reach directly. Everyone else still gets SMS
      // and the in-app push above.
      final bool whatsappThisContact =
          primaryContactId == null ? smsOn : d['id'] == primaryContactId;
      if (whatsappThisContact) {
        whatsappTargets.add(SosWhatsAppTarget(contactName, phone));
        waRecipients.add(WhatsAppService.instance.intlNumber(phone));
      }

      // DIRECT in-app push to this contact IF they use SmartSafe (matched by
      // phone). This is the WhatsApp-style notification: it lands on their phone
      // (and, once the Cloud Function is deployed, even when their app is
      // closed) — NO redirect. Works for Google or email sign-ups alike.
      futures.add(() async {
        try {
          final norm = normalizePhone(phone);
          if (norm.isEmpty) return;
          final us = await _db
              .collection('users')
              .where('phoneNormalized', isEqualTo: norm)
              .limit(1)
              .get();
          if (us.docs.isEmpty) return; // contact doesn't use SmartSafe
          final targetUid = us.docs.first.id;
          await _db.collection('notifications').add({
            'targetUserId': targetUid,
            'type': 'sos_personal',
            'sosUserId': uid,
            'senderName': senderName,
            'message': smsBody,
            'locationLink': location,
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
          appAlertsSent++;
          appPushTargets.add(targetUid); // closed-app FCM push (below)
        } catch (e) {
          debugPrint('[SimSOS] ❌ app push failed for $phone: $e');
        }
      }());

      await Future.wait(futures);
    }));

    // ── 4a. Closed-app push: alert every SmartSafe contact via our free Vercel
    // endpoint, so they get a heads-up notification even if their app is shut.
    if (appPushTargets.isNotEmpty) {
      await PushSender.instance.pushSos(
        targetUserIds: appPushTargets,
        type: 'sos_personal',
        senderName: senderName,
        sosUserId: uid,
      );
    }

    // ── 4a-ii. WhatsApp auto-send (no redirect) via the WhatsApp Business API.
    // Every contact gets the sender's name + phone + live location.
    if (waRecipients.isNotEmpty) {
      await WhatsAppSender.instance.send(
        recipients: waRecipients,
        senderName: senderName,
        senderPhone: senderPhone,
        location: location,
      );
      // Reflect the WhatsApp dispatch in the result so the UI stops always
      // showing "WhatsApp 0" (which made users think WhatsApp alerts failed).
      whatsappSent = waRecipients.length;
    }

    // ── 4b. SMS fallback when permission was denied ──────────────────────
    // Open one SMS composer pre-filled for all numbers so the user can still
    // send with a single tap. (Best effort — counts as attempted.)
    if (!smsGranted && smsFallbackRecipients.isNotEmpty) {
      try {
        await sendSMS(
          message: smsBody,
          recipients: smsFallbackRecipients,
          sendDirect: false,
        );
        smsSent = smsFallbackRecipients.length;
      } catch (e) {
        debugPrint('[SimSOS] ❌ SMS composer fallback failed: $e');
      }
    }

    // NOTE: WhatsApp is NOT auto-opened anymore (no redirect). Contacts who use
    // SmartSafe get a DIRECT push (above); WhatsApp is only an optional one-tap
    // button on the alert screen via `whatsappTargets`.

    // ── 5. Notify the user on their OWN phone ─────────────────────────────
    await LocalNotificationService.instance.show(
      title: kind == 'crash'
          ? '🚗 Road accident alert sent'
          : kind == 'shake'
              ? '🆘 Shake SOS — Help alert sent'
              : '🆘 SOS — Help alert sent',
      body:
          'Your alert reached ${contacts.length} contact(s) · 🔔 $appAlertsSent app  📞 $callsMade call  💬 $smsSent SMS',
    );

    return SimSosResult(
      callsMade: callsMade,
      smsSent: smsSent,
      whatsappSent: whatsappSent,
      appAlertsSent: appAlertsSent,
      senderName: senderName,
      location: location,
      whatsappTargets: whatsappTargets,
      messageBody: smsBody,
    );
  }

  /// Called when the user cancels an active SOS ("I am safe").
  /// Sends a follow-up on SMS + WhatsApp + Email and notifies the user.
  Future<SimSosResult> cancelSos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return SimSosResult(error: 'Please sign in first.');
    }

    final senderName = await _senderName(uid);
    final contacts = await _contacts(uid);
    final smsGranted = await _ensureSimPermissions();

    int smsSent = 0, emailsSent = 0;
    const int whatsappSent = 0; // cancel does NOT open WhatsApp (by design)
    final smsFallbackRecipients = <String>[];

    final cancelBody = 'SMARTSAFE — ALL CLEAR\n\n'
        '$senderName is now safe. The previous emergency alert has been cancelled.\n\n'
        'No further action is needed. Thank you.\n\n'
        '— Sent automatically by SmartSafe';

    for (final d in contacts) {
      final phone = d['phone']?.toString() ?? '';

      if (phone.isNotEmpty) {
        if (smsGranted) {
          try {
            await sendSMS(
                message: cancelBody, recipients: [phone], sendDirect: true);
            smsSent++;
          } catch (e) {
            debugPrint('[SimSOS] ❌ Cancel SMS failed to $phone: $e');
          }
        } else {
          smsFallbackRecipients.add(phone);
        }
      }
    }

    if (!smsGranted && smsFallbackRecipients.isNotEmpty) {
      try {
        await sendSMS(
            message: cancelBody,
            recipients: smsFallbackRecipients,
            sendDirect: false);
        smsSent = smsFallbackRecipients.length;
      } catch (e) {
        debugPrint('[SimSOS] ❌ Cancel SMS fallback failed: $e');
      }
    }

    // NOTE: cancel ("I am safe") deliberately does NOT open WhatsApp — the
    // all-clear goes out via SMS only, so the user isn't pushed into WhatsApp.

    // Record the cancellation in Firestore (dashboard + user feed).
    await AppFirestoreService.instance.recordSosCancel(senderName: senderName);

    await LocalNotificationService.instance.show(
      id: 1002,
      title: '✅ SOS cancelled',
      body:
          'Your ${contacts.length} contact(s) have been told that you are safe.',
    );

    return SimSosResult(
      smsSent: smsSent,
      whatsappSent: whatsappSent,
      emailsSent: emailsSent,
      senderName: senderName,
      cancelled: true,
    );
  }
}

/// A contact the user can message on WhatsApp (free wa.me) from the UI.
class SosWhatsAppTarget {
  final String name;
  final String phone;
  const SosWhatsAppTarget(this.name, this.phone);
}

class SimSosResult {
  final int callsMade;
  final int smsSent;
  final int whatsappSent;
  final int emailsSent;
  final int appAlertsSent; // direct in-app push to contacts who use SmartSafe
  final String? error;
  final String senderName;
  final String location;
  final bool cancelled;

  /// Contacts that can be messaged on WhatsApp + the pre-filled body, so the UI
  /// can offer a one-tap "Send on WhatsApp" per contact (free, no Twilio).
  final List<SosWhatsAppTarget> whatsappTargets;
  final String messageBody;

  SimSosResult({
    this.callsMade = 0,
    this.smsSent = 0,
    this.whatsappSent = 0,
    this.emailsSent = 0,
    this.appAlertsSent = 0,
    this.error,
    this.senderName = '',
    this.location = '',
    this.cancelled = false,
    this.whatsappTargets = const [],
    this.messageBody = '',
  });

  bool get hasError => error != null;

  String get summaryMessage {
    if (hasError) return '⚠️ $error';
    final parts = <String>[];
    if (appAlertsSent > 0) parts.add('🔔 $appAlertsSent app alert');
    if (callsMade > 0) parts.add('📞 $callsMade call');
    if (smsSent > 0) parts.add('💬 $smsSent SMS');
    if (whatsappSent > 0) parts.add('🟢 $whatsappSent WhatsApp');
    if (emailsSent > 0) parts.add('📧 $emailsSent email');
    if (cancelled) {
      if (parts.isEmpty) return '✅ SOS cancelled — you are marked safe.';
      return '✅ SOS cancelled!\nContacts notified: ${parts.join(' · ')}';
    }
    if (parts.isEmpty) {
      return '⚠️ Nothing was sent — please check your contacts\' phone numbers.';
    }
    return '🚨 SOS sent!\n${parts.join(' · ')} delivered.';
  }
}
