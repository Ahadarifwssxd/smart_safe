import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/services/app_firestore_service.dart';
import 'package:smartsafe/theme/colors.dart';

class AppNotificationsScreen extends StatelessWidget {
  const AppNotificationsScreen({super.key});

  String _formatTime(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('dd MMM, HH:mm').format(ts.toDate());
    }
    return '';
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'sos':
        return C.accent;
      case 'crash':
        return C.warning;
      case 'safe':
        return C.success;
      case 'contact':
        return C.accent;
      default:
        return C.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(defaultPadding),
            child: Header(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
            child: PageHeaderBar(
              icon: Icons.notifications_active_rounded,
              title: 'App Notifications',
              subtitle: 'SOS, contacts aur alerts — mobile app se sync',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _SendNotificationDialog(),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send Notification'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getAppNotificationsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: C.accent));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(child: Text('No notifications yet', style: TextStyle(color: C.textMuted)));
                }

                final sorted = List<DocumentSnapshot>.from(docs);
                sorted.sort((a, b) {
                  final ta = (a.data() as Map?)?['createdAt'];
                  final tb = (b.data() as Map?)?['createdAt'];
                  if (ta is Timestamp && tb is Timestamp) {
                    return tb.compareTo(ta);
                  }
                  return 0;
                });

                // Collapse duplicates: a broadcast used to be written once PER
                // user, so the same message appeared many times. Show each
                // unique notification (same title+body+type near the same time)
                // only ONCE.
                final seen = <String>{};
                final unique = <DocumentSnapshot>[];
                for (final doc in sorted) {
                  final d = doc.data() as Map<String, dynamic>;
                  final ts = d['createdAt'];
                  final minute = ts is Timestamp
                      ? (ts.millisecondsSinceEpoch ~/ 60000).toString()
                      : '';
                  final key =
                      '${d['title']}|${d['body']}|${d['type']}|$minute';
                  if (seen.add(key)) unique.add(doc);
                }

                return ListView.builder(
                  cacheExtent: 500,
                  padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
                  itemCount: unique.length,
                  itemBuilder: (context, i) {
                    final doc = unique[i];
                    final d = doc.data() as Map<String, dynamic>;
                    final type = d['type']?.toString();
                    final isRead = d['isRead'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: secondaryColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isRead ? C.border.withValues(alpha: 0.3) : _typeColor(type).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.circle, size: 10, color: isRead ? C.textMuted : _typeColor(type)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['title']?.toString() ?? 'Notification',
                                  style: TextStyle(
                                    color: C.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  d['body']?.toString() ?? '',
                                  style: TextStyle(color: C.textMuted, fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatTime(d['createdAt']),
                                  style: TextStyle(color: C.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (!isRead)
                            IconButton(
                              icon: Icon(Icons.done_all, color: C.accent, size: 20),
                              onPressed: () => FirebaseService.instance.markAppNotificationRead(doc.id),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin composer: send a notification to every user, or to one user by uid.
/// Writes an `app_notifications` doc per recipient — exactly what the mobile
/// app's Notifications page streams — so it appears on their phone live.
class _SendNotificationDialog extends StatefulWidget {
  const _SendNotificationDialog();

  @override
  State<_SendNotificationDialog> createState() =>
      _SendNotificationDialogState();
}

class _SendNotificationDialogState extends State<_SendNotificationDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  /// uid of the chosen recipient when not broadcasting (picked from a dropdown
  /// of real users — an admin never knows a raw Firebase UID).
  String? _targetUid;
  String _type = 'contact';
  bool _toAll = true;
  bool _sending = false;

  static const _types = ['sos', 'crash', 'safe', 'gps', 'contact', 'route'];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title or a message first.')),
      );
      return;
    }
    if (!_toAll && (_targetUid == null || _targetUid!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a user to send to.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final count = await AppFirestoreService.instance.sendAdminNotification(
        title: _title.text,
        body: _body.text,
        type: _type,
        targetUserId: _toAll ? null : _targetUid,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: C.success,
          content: Text('Notification sent to $count user(s).'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: C.accent, content: Text('Send failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: C.textMuted),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: C.border)),
          focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: C.accent)),
        );

    return AlertDialog(
      backgroundColor: C.bg2,
      title: Text('Send notification',
          style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                style: TextStyle(color: C.textPrimary),
                decoration: dec('Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                maxLines: 3,
                style: TextStyle(color: C.textPrimary),
                decoration: dec('Message'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                dropdownColor: C.bg2,
                style: TextStyle(color: C.textPrimary),
                decoration: dec('Type'),
                items: _types
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? 'contact'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _toAll,
                onChanged: (v) => setState(() => _toAll = v),
                title: Text('Send to all users',
                    style: TextStyle(color: C.textPrimary, fontSize: 14)),
                subtitle: Text(
                    _toAll ? 'Every registered user' : 'One specific user',
                    style: TextStyle(color: C.textMuted, fontSize: 12)),
                activeThumbColor: C.accent,
              ),
              // Pick the recipient from the real user list — an admin never
              // knows a raw Firebase UID, so we show name + email and send to
              // the uid behind it.
              if (!_toAll)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseService.instance.usersCollection.snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: C.accent),
                          ),
                          const SizedBox(width: 10),
                          Text('Loading users…',
                              style:
                                  TextStyle(color: C.textMuted, fontSize: 13)),
                        ]),
                      );
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return Text('No users found.',
                          style: TextStyle(color: C.textMuted, fontSize: 13));
                    }
                    // Drop a stale selection if that user vanished.
                    if (_targetUid != null &&
                        !docs.any((d) => d.id == _targetUid)) {
                      _targetUid = null;
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: _targetUid,
                      isExpanded: true,
                      dropdownColor: C.bg2,
                      style: TextStyle(color: C.textPrimary),
                      decoration: dec('Send to which user?'),
                      hint: Text('Choose a user',
                          style: TextStyle(color: C.textMuted)),
                      items: docs.map((d) {
                        final m = d.data() as Map<String, dynamic>;
                        final name =
                            (m['name']?.toString().trim().isNotEmpty ?? false)
                                ? m['name'].toString()
                                : 'Unnamed';
                        final email = m['email']?.toString() ?? '';
                        return DropdownMenuItem(
                          value: d.id,
                          child: Text(
                            email.isEmpty ? name : '$name  ·  $email',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _targetUid = v),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: C.textMuted)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: C.accent, foregroundColor: Colors.white),
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_sending ? 'Sending…' : 'Send'),
        ),
      ],
    );
  }
}
