import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/app_firestore_service.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../widgets/widgets.dart';
import '22_incident_report_page.dart';

class _FeedItem {
  final String cat, title, loc;
  final DateTime time;
  final String severity; // high | medium
  _FeedItem(this.cat, this.title, this.loc, this.time, this.severity);
}

class SafetyFeedPage extends StatefulWidget {
  const SafetyFeedPage({super.key});
  @override State<SafetyFeedPage> createState() => _SafetyFeedPageState();
}

class _SafetyFeedPageState extends State<SafetyFeedPage> {
  String _filter = 'All';
  final _filters = ['All', 'Crime', 'Accident', 'Road Block', 'Other'];

  String _category(String type) {
    final t = type.toLowerCase();
    if (t.contains('robber') || t.contains('harass') || t.contains('theft') ||
        t.contains('snatch') || t.contains('stalk') || t.contains('assault') ||
        t.contains('crime')) {
      return 'Crime';
    }
    if (t.contains('accident') || t.contains('crash')) return 'Accident';
    if (t.contains('block') || t.contains('road') || t.contains('protest')) {
      return 'Road Block';
    }
    return 'Other';
  }

  IconData _icon(String cat) => cat == 'Crime'
      ? Icons.warning_amber_rounded
      : cat == 'Accident'
          ? Icons.car_crash_rounded
          : cat == 'Road Block'
              ? Icons.block_rounded
              : Icons.report_problem_rounded;

  Color _catColor(String cat) =>
      cat == 'Accident' || cat == 'Road Block' ? C.warning : C.accent;

  String _severityLabel(String s) =>
      s == 'high' ? 'High Risk' : s == 'medium' ? 'Caution' : 'Safe';
  Color _severityColor(String s) =>
      s == 'high' ? C.red : s == 'medium' ? C.warning : C.success;

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('route_hazards').snapshots(),
        builder: (context, hazSnap) {
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: AppFirestoreService.instance.watchApprovedIncidentReports(),
            builder: (context, incSnap) {
              final items = <_FeedItem>[];
              // Community hazard reports
              for (final d in hazSnap.data?.docs ?? []) {
                final m = d.data();
                final type = m['type']?.toString() ?? 'other';
                final cat = _category(type);
                final risk = (m['riskLevel']?.toString() ?? 'High').toLowerCase();
                items.add(_FeedItem(
                  cat,
                  (m['description']?.toString().isNotEmpty == true)
                      ? m['description'].toString()
                      : '${type[0].toUpperCase()}${type.substring(1)} reported',
                  m['locationName']?.toString() ?? 'Nearby',
                  (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                  risk == 'high' ? 'high' : 'medium',
                ));
              }
              // User incident reports (ONLY admin-approved ones — see the
              // watchApprovedIncidentReports stream below). The admin-set
              // priority drives how urgent the feed card looks.
              for (final m in incSnap.data ?? []) {
                final type = m['incidentType']?.toString() ?? 'Incident';
                final priority = m['priority']?.toString() ?? 'normal';
                final sev = priority == 'urgent' || priority == 'high'
                    ? 'high'
                    : 'medium';
                items.add(_FeedItem(
                  _category(type),
                  type,
                  m['location']?.toString() ?? 'Nearby',
                  (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                  sev,
                ));
              }
              items.sort((a, b) => b.time.compareTo(a.time));

              final filtered =
                  _filter == 'All' ? items : items.where((f) => f.cat == _filter).toList();
              final crime = items.where((f) => f.cat == 'Crime').length;
              final accident = items.where((f) => f.cat == 'Accident').length;
              final block = items.where((f) => f.cat == 'Road Block').length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        responsiveHInset(context), 16, responsiveHInset(context), 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(children: [
                            if (Navigator.canPop(context)) ...[
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
                              ),
                              const SizedBox(width: 12),
                            ],
                            DynText('safety_feed', 'title', 'Safety Feed', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                          ]),
                          Row(children: [
                            BlinkDot(color: C.accent),
                            const SizedBox(width: 6),
                            Text('LIVE', style: TextStyle(color: C.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        ]),
                        const SizedBox(height: 4),
                        Text('Live community alerts from SmartSafe users', style: TextStyle(color: C.textMuted, fontSize: 12)),
                        const SizedBox(height: 16),
                        Row(children: [
                          _StatPill(value: '$crime', label: 'Crime alerts', color: C.accent),
                          const SizedBox(width: 8),
                          _StatPill(value: '$accident', label: 'Accidents', color: C.warning),
                          const SizedBox(width: 8),
                          _StatPill(value: '$block', label: 'Road blocks', color: C.warning),
                        ]),
                        const SizedBox(height: 16),
                        SizedBox(height: 34, child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _filters.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final f = _filters[i]; final sel = f == _filter;
                            return GestureDetector(onTap: () => setState(() => _filter = f),
                              child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(color: sel ? C.accent : C.bg2, borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: sel ? C.accent : C.textDim)),
                                child: Center(child: Text(f,
                                  style: TextStyle(color: sel ? Colors.white : C.textMuted, fontSize: 12,
                                    fontWeight: sel ? FontWeight.w700 : FontWeight.normal)))));
                          },
                        )),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.shield_outlined, color: C.textMuted, size: 44),
                              const SizedBox(height: 12),
                              Text('No alerts nearby right now',
                                  style: TextStyle(color: C.textMuted, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text('Community reports will appear here in real time.',
                                  style: TextStyle(color: C.textDim, fontSize: 12),
                                  textAlign: TextAlign.center),
                            ]),
                          ))
                        : ListView.separated(
                            padding: EdgeInsets.symmetric(horizontal: responsiveHInset(context)),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final item = filtered[i];
                              final color = _catColor(item.cat);
                              return SlideUpFade(delay: Duration(milliseconds: i * 40),
                                child: DCard(child: Row(children: [
                                  Container(width: 40, height: 40,
                                    decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
                                    child: Icon(_icon(item.cat), color: color, size: 20)),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(item.title, style: TextStyle(color: C.textPrimary, fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text(item.loc, style: TextStyle(color: C.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ])),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    StatusChip(label: _severityLabel(item.severity), color: _severityColor(item.severity)),
                                    const SizedBox(height: 4),
                                    Text(_timeAgo(item.time), style: TextStyle(color: C.textMuted, fontSize: 10)),
                                  ]),
                                ])));
                            },
                          ),
                  ),
                  Padding(padding: const EdgeInsets.all(16),
                    child: BigBtn(label: '+ Report Incident', color: C.accent, icon: Icons.add_alert_rounded, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IncidentReportPage())))),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}

class _StatPill extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatPill({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .3))),
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(color: C.textMuted, fontSize: 9), textAlign: TextAlign.center),
    ])));
}