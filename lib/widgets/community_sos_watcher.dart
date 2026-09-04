import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/helper_response_page.dart';
import '../services/app_firestore_service.dart';
import '../services/local_notification_service.dart';
import '../theme/colors.dart';

/// Always-on watcher that surfaces incoming Community-SOS alerts addressed to
/// the signed-in user. Wrap the logged-in app with this so that whenever a
/// nearby person raises a community SOS, this user sees a real heads-up
/// notification + an in-app dialog they can tap to respond as a helper.
///
/// Previously the app WROTE `notifications` docs for nearby users but nothing
/// listened to them, so no one ever saw a community SOS.
class CommunitySosWatcher extends StatefulWidget {
  final Widget child;
  const CommunitySosWatcher({super.key, required this.child});

  @override
  State<CommunitySosWatcher> createState() => _CommunitySosWatcherState();
}

class _CommunitySosWatcherState extends State<CommunitySosWatcher> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  // Alerts whose response DIALOG has been shown (so we don't re-prompt).
  final _handled = <String>{};
  // Alerts whose heads-up NOTIFICATION has fired (deduped separately, so a
  // dialog deferred because another was open can still surface later).
  final _notified = <String>{};
  final _claimedHandled = <String>{};
  // SOS senders we've already accepted ("I'm coming") — never prompt us again
  // for the same emergency, even if a stray/duplicate notification arrives.
  final _respondedSos = <String>{};
  bool _dialogOpen = false;
  String? _activeNotifId;
  BuildContext? _activeDialogContext;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // IMPORTANT: a single-field equality query needs NO composite index. The
    // earlier 3-filter query (targetUserId + type whereIn + read) required a
    // composite index that was never created, so Firestore rejected it and the
    // listener silently failed — which is why incoming SOS alerts never showed.
    // We now filter type + read in memory (see _onAlerts) instead.
    _sub = FirebaseFirestore.instance
        .collection('notifications')
        .where('targetUserId', isEqualTo: uid)
        .snapshots()
        .listen(_onAlerts, onError: (e) {
      debugPrint('[CommunitySosWatcher] $e');
    });
  }

  Future<void> _onAlerts(QuerySnapshot<Map<String, dynamic>> snap) async {
    for (final change in snap.docChanges) {
      final doc = change.doc;
      final data = doc.data() ?? {};

      // If this is the active dialog we are showing, and it has been read, resolved, or claimed
      if (_activeNotifId == doc.id && _dialogOpen && _activeDialogContext != null) {
        final isRead = data['read'] == true;
        final isResolved = data['status'] == 'resolved';
        final isClaimed = data['claimed'] == true;

        if (isRead || isResolved || isClaimed || change.type == DocumentChangeType.removed) {
          // Programmatically dismiss the dialog
          if (Navigator.canPop(_activeDialogContext!)) {
            Navigator.pop(_activeDialogContext!);
          }
          _dialogOpen = false;
          _activeNotifId = null;
          _activeDialogContext = null;
        }
      }

      if (change.type == DocumentChangeType.removed) continue;
      final type = data['type']?.toString() ?? '';
      // In-memory replacement for the removed where('type'…)/where('read'…)
      // filters: only react to SOS alerts addressed to us, and skip read ones.
      if (type != 'sos_alert' && type != 'sos_personal') continue;
      if (data['read'] == true) continue;
      if (data['status'] == 'resolved') continue;

      // Ignore STALE alerts — an SOS raised a while ago must NOT pop up every
      // time the app is reopened. Only react to alerts from the last 15 min;
      // older ones are silently marked read so they never resurface.
      final ts = (data['timestamp'] as Timestamp?)?.toDate();
      if (ts != null &&
          DateTime.now().difference(ts) > const Duration(minutes: 15)) {
        await _markRead(doc.id);
        continue;
      }
      final senderName = data['senderName']?.toString() ?? 'Someone nearby';
      final claimed = data['claimed'] == true;
      final responderName = data['responderName']?.toString() ?? '';
      final sosUserId = data['sosUserId']?.toString() ?? '';

      // We already accepted this person's SOS → never show the prompt again,
      // and make sure this notification is marked read so it stops recurring.
      if (type == 'sos_alert' &&
          sosUserId.isNotEmpty &&
          _respondedSos.contains(sosUserId)) {
        if (data['read'] != true) await _markRead(doc.id);
        continue;
      }

      // PERSONAL SOS — this is from someone whose emergency contact YOU are
      // (family/friend). Show a strong direct alert (no "respond as helper").
      if (type == 'sos_personal') {
        if (_handled.contains(doc.id)) continue;
        _handled.add(doc.id);
        await LocalNotificationService.instance.show(
          id: 2000 + (doc.id.hashCode % 1000),
          title: '🆘 $senderName needs help!',
          body: 'Your emergency contact triggered an SOS. Tap to see details.',
          fullScreen: true,
        );
        // Keep a copy in the bell-tab feed so it's not lost once dismissed.
        await AppFirestoreService.instance.saveToMyFeed(
          sourceId: doc.id,
          title: '🆘 $senderName needs help',
          body: 'Your emergency contact triggered an SOS.',
        );
        if (mounted && !_dialogOpen) {
          _showPersonalDialog(
            doc.id,
            senderName,
            data['message']?.toString() ?? '',
            data['locationLink']?.toString() ?? '',
          );
        }
        continue;
      }

      // Claimed by another helper (even if we already saw the original alert) →
      // ride-hailing style: inform that help is on the way ONCE, then mark read
      // so the response dialog no longer applies.
      if (claimed) {
        if (_claimedHandled.contains(doc.id)) continue;
        _claimedHandled.add(doc.id);
        await LocalNotificationService.instance.show(
          id: 2000 + (doc.id.hashCode % 1000),
          title: '✅ Help is on the way',
          body:
              '${responderName.isNotEmpty ? responderName : 'A helper'} is responding to the nearby SOS.',
        );
        await _markRead(doc.id);
        continue;
      }

      // Already prompted for this exact alert → skip.
      if (_handled.contains(doc.id)) continue;

      // Heads-up notification + feed copy — ONCE per alert (deduped on
      // `_notified`, not `_handled`, so a dialog we couldn't show yet isn't
      // permanently suppressed).
      if (!_notified.contains(doc.id)) {
        _notified.add(doc.id);
        await LocalNotificationService.instance.show(
          id: 2000 + (doc.id.hashCode % 1000),
          title: '🆘 Community SOS — $senderName needs help',
          body: 'Someone in the community needs help. Tap to respond.',
          fullScreen: true,
        );
        await AppFirestoreService.instance.saveToMyFeed(
          sourceId: doc.id,
          title: '🆘 Community SOS — $senderName',
          body: 'Someone in the community needs help.',
        );
      }

      // Only mark fully handled when the dialog is ACTUALLY shown. If another
      // dialog is open we leave it un-handled so a later snapshot can surface
      // it (a second concurrent SOS is no longer silently dropped).
      if (mounted && !_dialogOpen) {
        _handled.add(doc.id);
        _showDialog(doc.id, data['sosUserId']?.toString() ?? '', senderName);
      }
    }
  }

  Future<void> _markRead(String notifId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notifId)
        .update({'read': true}).catchError((_) {});
  }

  void _showDialog(String notifId, String sosUserId, String senderName) {
    _dialogOpen = true;
    _activeNotifId = notifId;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _activeDialogContext = ctx;
        return AlertDialog(
          backgroundColor: C.bg2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.sos_rounded, color: C.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Community SOS',
                    style: TextStyle(
                        color: C.textPrimary, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          content: Text(
            '$senderName nearby has raised an emergency SOS and needs help. '
            'Can you respond?',
            style: TextStyle(color: C.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _markRead(notifId);
                Navigator.pop(ctx);
              },
              child: Text('Dismiss', style: TextStyle(color: C.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                // Remember we've accepted this SOS so it never prompts us again.
                if (sosUserId.isNotEmpty) _respondedSos.add(sosUserId);
                _markRead(notifId);
                Navigator.pop(ctx);
                // Open the live helper view — it registers us as a helper and
                // shows the victim's live location + address on a map.
                if (mounted && sosUserId.isNotEmpty) {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => HelperResponsePage(
                      sosUserId: sosUserId,
                      victimName: senderName,
                    ),
                  ));
                }
              },
              child: const Text("I'm coming to help"),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _dialogOpen = false;
      if (_activeNotifId == notifId) {
        _activeNotifId = null;
        _activeDialogContext = null;
      }
    });
  }

  /// Pulls the first http(s) URL out of a raw SOS message, used as a fallback
  /// so "View location" still works when no explicit locationLink was stored.
  static String _extractUrl(String text) {
    final match =
        RegExp(r'https?://\S+').firstMatch(text.replaceAll('\n', ' '));
    return match?.group(0)?.trim() ?? '';
  }

  /// Personal SOS from someone whose emergency contact you are — shows their
  /// message and a button to open their live location. No "respond as helper".
  void _showPersonalDialog(
      String notifId, String senderName, String message, String locationLink) {
    _dialogOpen = true;
    _activeNotifId = notifId;
    // Prefer the explicit link; otherwise try to recover one from the message
    // so the primary action never dead-ends. (Functionality preserved.)
    final link = locationLink.startsWith('http')
        ? locationLink
        : _extractUrl(message);
    final hasLink = link.startsWith('http');
    final body = message.isNotEmpty
        ? message
        : '$senderName triggered an emergency SOS and needs your help.';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _activeDialogContext = ctx;
        final media = MediaQuery.of(ctx);
        return Dialog(
          backgroundColor: C.bg2,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            side: BorderSide(color: C.border),
          ),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header: SOS badge + bold title ──────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: C.accent.withValues(alpha: 0.14),
                            border: Border.all(
                                color: C.accent.withValues(alpha: 0.45)),
                          ),
                          child: Icon(Icons.sos_rounded,
                              color: C.accent, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'EMERGENCY SOS',
                                style: TextStyle(
                                  color: C.accent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$senderName needs help',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: C.border),
                  // ── Scrollable message body (never clips) ───────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            body,
                            style: TextStyle(
                              color: C.textMuted,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          if (hasLink) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: C.bg3.withValues(alpha: 0.6),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusMd),
                                border: Border.all(
                                    color: C.border.withValues(alpha: 0.7)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      color: C.accent, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      link,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: C.textDim,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: C.border),
                  // ── Actions: primary "View location" + secondary Dismiss ─
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasLink)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: C.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                              onPressed: () {
                                _markRead(notifId);
                                Navigator.pop(ctx);
                                try {
                                  launchUrl(Uri.parse(link),
                                      mode: LaunchMode.externalApplication);
                                } catch (_) {}
                              },
                              icon:
                                  const Icon(Icons.location_on_rounded, size: 20),
                              label: const Text('View location'),
                            ),
                          ),
                        if (hasLink) const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: C.textMuted,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              _markRead(notifId);
                              Navigator.pop(ctx);
                            },
                            child: const Text('Dismiss'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _dialogOpen = false;
      if (_activeNotifId == notifId) {
        _activeNotifId = null;
        _activeDialogContext = null;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
