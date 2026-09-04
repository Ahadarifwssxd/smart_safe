import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';

/// Admin view of user ratings + feedback submitted from the app
/// (Settings → Send Feedback). Reads the `app_feedback` collection.
class FeedbackScreen extends StatelessWidget {
  const FeedbackScreen({super.key});

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
              icon: Icons.star_rounded,
              iconColor: C.warning,
              title: 'User Feedback & Ratings',
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('app_feedback')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(color: C.accent));
                }
                final docs =
                    List<DocumentSnapshot>.from(snapshot.data?.docs ?? []);
                // Newest first.
                docs.sort((a, b) {
                  final ta =
                      (a.data() as Map?)?['createdAt'] as Timestamp?;
                  final tb =
                      (b.data() as Map?)?['createdAt'] as Timestamp?;
                  return (tb?.millisecondsSinceEpoch ?? 0)
                      .compareTo(ta?.millisecondsSinceEpoch ?? 0);
                });

                if (docs.isEmpty) {
                  return Center(
                      child: Text('No feedback yet',
                          style: TextStyle(color: C.textMuted)));
                }

                // Average rating.
                final ratings = docs
                    .map((d) =>
                        ((d.data() as Map?)?['rating'] as num?)?.toDouble() ??
                        0)
                    .where((r) => r > 0)
                    .toList();
                final avg = ratings.isEmpty
                    ? 0.0
                    : ratings.reduce((a, b) => a + b) / ratings.length;

                return Column(
                  children: [
                    // Summary bar.
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: defaultPadding),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: secondaryColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: C.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Text(avg.toStringAsFixed(1),
                              style: TextStyle(
                                  color: C.warning,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: List.generate(5, (i) {
                                  return Icon(
                                    i < avg.round()
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    color: C.warning,
                                    size: 18,
                                  );
                                }),
                              ),
                              const SizedBox(height: 4),
                              Text('${docs.length} review(s)',
                                  style: TextStyle(
                                      color: C.textMuted, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        cacheExtent: 500,
                        padding: const EdgeInsets.symmetric(
                            horizontal: defaultPadding),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final rating = (d['rating'] as num?)?.toInt() ?? 0;
                          final name = (d['name']?.toString().isNotEmpty ?? false)
                              ? d['name'].toString()
                              : (d['email']?.toString() ?? 'Anonymous');
                          final message = d['message']?.toString() ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: secondaryColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(name,
                                          style: TextStyle(
                                              color: C.textPrimary,
                                              fontWeight: FontWeight.w700),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    Row(
                                      children: List.generate(5, (s) {
                                        return Icon(
                                          s < rating
                                              ? Icons.star_rounded
                                              : Icons.star_outline_rounded,
                                          color: C.warning,
                                          size: 15,
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                                if (message.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(message,
                                      style: TextStyle(
                                          color: C.textMuted, fontSize: 13)),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
