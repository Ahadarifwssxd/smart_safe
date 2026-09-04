import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/theme/colors.dart';

/// Dashboard widget that fetches and displays active PRO subscribers
/// in real time from Firestore `users` collection.
class DashboardProSubscribers extends StatelessWidget {
  const DashboardProSubscribers({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(defaultPadding),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.amber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRO Subscriptions & Live Members',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: C.textPrimary,
                            ),
                      ),
                      Text(
                        'Real-time Firestore sync of active premium users',
                        style: TextStyle(color: C.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.greenAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'SYNCED',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: defaultPadding),

          // StreamBuilder watching Firestore users with plan == 'premium'
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('plan', isEqualTo: 'premium')
                .limit(10)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: Colors.amber),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: C.bg2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.workspace_premium_outlined,
                            color: C.textMuted, size: 36),
                        const SizedBox(height: 10),
                        Text(
                          'No Active PRO Subscribers Found',
                          style: TextStyle(
                            color: C.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'When users purchase PRO via Card, JazzCash, or EasyPaisa in the app, their details will appear here instantly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: C.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      horizontalMargin: 0,
                      columnSpacing: 18,
                      columns: const [
                        DataColumn(
                            label: Text('USER',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                        DataColumn(
                            label: Text('PLAN',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                        DataColumn(
                            label: Text('PAYMENT METHOD',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                        DataColumn(
                            label: Text('STATUS',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                        DataColumn(
                            label: Text('VALID UNTIL',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                      ],
                      rows: docs.map((doc) {
                        final data = doc.data();
                        final name = data['name'] as String? ??
                            data['displayName'] as String? ??
                            data['email'] as String? ??
                            'SmartSafe User';
                        final email = data['email'] as String? ?? doc.id;
                        final planName =
                            data['planName'] as String? ?? 'SmartSafe PRO';
                        final method = data['paymentMethod'] as String? ??
                            'Mock Gateway';
                        final rawExpiry = data['planExpiresAt'];
                        String expiryFormatted = 'Active';
                        if (rawExpiry is String) {
                          final dt = DateTime.tryParse(rawExpiry);
                          if (dt != null) {
                            expiryFormatted =
                                DateFormat('dd MMM yyyy').format(dt);
                          }
                        }

                        return DataRow(
                          cells: [
                            DataCell(
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor:
                                        Colors.amber.withValues(alpha: 0.2),
                                    child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          color: C.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        email,
                                        style: TextStyle(
                                            color: C.textMuted, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  planName,
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  const Icon(Icons.payment_rounded,
                                      size: 14, color: Colors.greenAccent),
                                  const SizedBox(width: 6),
                                  Text(
                                    method,
                                    style: TextStyle(
                                        color: C.textPrimary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: C.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: C.success,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                expiryFormatted,
                                style: TextStyle(
                                    color: C.textMuted, fontSize: 11),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
