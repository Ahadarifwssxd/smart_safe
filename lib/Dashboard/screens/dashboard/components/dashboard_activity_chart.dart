import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/theme/colors.dart';

/// Last 7 days SOS activity bar chart.
class DashboardActivityChart extends StatelessWidget {
  const DashboardActivityChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(defaultPadding),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SOS Activity (7 days)',
            style: TextStyle(color: C.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: defaultPadding),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('sos_events').snapshots(),
            builder: (context, snap) {
              final counts = List<int>.filled(7, 0);
              final labels = <String>[];
              final now = DateTime.now();
              for (var i = 6; i >= 0; i--) {
                final d = now.subtract(Duration(days: i));
                labels.add(_dayLabel(d));
              }

              if (snap.hasData) {
                for (final doc in snap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data == null) continue;
                  final ts = data['createdAt'];
                  DateTime? dt;
                  if (ts is Timestamp) dt = ts.toDate();
                  if (dt == null) continue;
                  final diff = now.difference(DateTime(dt.year, dt.month, dt.day)).inDays;
                  if (diff >= 0 && diff < 7) {
                    counts[6 - diff]++;
                  }
                }
              }

              final max = counts.reduce((a, b) => a > b ? a : b);
              final peak = max == 0 ? 1 : max;

              return SizedBox(
                height: 160,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (i) {
                    final h = (counts[i] / peak) * 120;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${counts[i]}',
                              style: TextStyle(color: C.textMuted, fontSize: 10),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: h.clamp(4.0, 120.0),
                              decoration: BoxDecoration(
                                color: C.accent.withValues(alpha: 0.85),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              labels[i],
                              style: TextStyle(color: C.textMuted, fontSize: 9),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _dayLabel(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }
}
