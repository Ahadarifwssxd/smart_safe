import 'package:flutter/material.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../constants.dart';

class RecentFiles extends StatelessWidget {
  const RecentFiles({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(defaultPadding),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Recent SOS Alerts",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: defaultPadding),
          SizedBox(
            width: double.infinity,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getAlertsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        "No SOS Alerts triggered yet.",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  );
                }

                // Take the 5 most recent alerts
                final recentDocs = docs.take(5).toList();

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                  columnSpacing: dataTableColumnSpacing(context),
                  columns: const [
                    DataColumn(label: Text("User")),
                    DataColumn(label: Text("Alert Type")),
                    DataColumn(label: Text("Time")),
                    DataColumn(label: Text("Status")),
                  ],
                  rows: recentDocs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final userName = data['userName'] ?? 'Unknown User';
                    final alertType = data['alertType'] ?? 'SOS Alert';
                    final time = data['time'] ?? '';
                    final status = data['status'] ?? 'Active';
                    final isResolved = status == 'Resolved';

                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              Icon(
                                isResolved ? Icons.check_circle_rounded : Icons.warning_rounded,
                                color: isResolved ? C.success : C.accent,
                                size: 20,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
                                child: Text(userName, style: const TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                        DataCell(Text(alertType, style: const TextStyle(color: Colors.white70))),
                        DataCell(Text(time, style: const TextStyle(color: Colors.white70))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isResolved ? C.success.withValues(alpha: 0.1) : C.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: isResolved ? C.success : C.accentLight,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ));
              },
            ),
          ),
        ],
      ),
    );
  }
}
