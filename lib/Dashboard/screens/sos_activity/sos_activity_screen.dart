import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';

class SosActivityScreen extends StatelessWidget {
  const SosActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(defaultPadding),
            child: Header(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: defaultPadding),
            child: PageHeaderBar(
              icon: Icons.sos_rounded,
              title: 'User SOS Activity',
              subtitle: 'Kitni dafa har user ne SOS press kiya — app se live sync',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getSosEventsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: C.accent));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('No SOS presses yet', style: TextStyle(color: C.textMuted)),
                  );
                }

                final byUser = <String, _UserSosSummary>{};
                for (final doc in snapshot.data!.docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  final uid = d['userId']?.toString() ?? 'unknown';
                  final name = d['userName']?.toString().isNotEmpty == true
                      ? d['userName'].toString()
                      : d['userEmail']?.toString() ?? 'Unknown user';
                  final email = d['userEmail']?.toString() ?? '';
                  byUser.putIfAbsent(
                    uid,
                    () => _UserSosSummary(userId: uid, userName: name, userEmail: email, events: []),
                  );
                  byUser[uid]!.events.add(_SosEventRow(id: doc.id, data: d));
                }

                final summaries = byUser.values.toList()
                  ..sort((a, b) => b.events.length.compareTo(a.events.length));

                return ListView.builder(
                  cacheExtent: 500,
                  padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
                  itemCount: summaries.length,
                  itemBuilder: (context, i) {
                    final s = summaries[i];
                    return _UserSosCard(summary: s);
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

class _UserSosSummary {
  final String userId;
  final String userName;
  final String userEmail;
  final List<_SosEventRow> events;
  _UserSosSummary({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.events,
  });
}

class _SosEventRow {
  final String id;
  final Map<String, dynamic> data;
  _SosEventRow({required this.id, required this.data});
}

class _UserSosCard extends StatelessWidget {
  final _UserSosSummary summary;
  const _UserSosCard({required this.summary});

  String _formatTime(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('dd MMM yyyy, HH:mm').format(ts.toDate());
    }
    return ts?.toString() ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border.withValues(alpha: 0.4)),
      ),
      child: ExpansionTile(
        iconColor: C.accent,
        collapsedIconColor: C.textMuted,
        title: Text(summary.userName, style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700)),
        subtitle: Text(
          summary.userEmail.isNotEmpty ? summary.userEmail : summary.userId,
          style: TextStyle(color: C.textMuted, fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: C.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${summary.events.length}× SOS',
            style: TextStyle(color: C.accent, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        children: summary.events.map((e) {
          final d = e.data;
          return ListTile(
            dense: true,
            leading: Icon(Icons.warning_amber_rounded, color: C.accent, size: 20),
            title: Text(
              '${d['alertType'] ?? 'SOS'} · ${d['source'] ?? 'app'}',
              style: TextStyle(color: C.textMuted, fontSize: 13),
            ),
            subtitle: Text(
              '${d['location'] ?? ''}\n${_formatTime(d['createdAt'])}',
              style: TextStyle(color: C.textMuted, fontSize: 11),
            ),
            isThreeLine: true,
          );
        }).toList(),
      ),
    );
  }
}
