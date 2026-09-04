import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/services/evidence_service.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';

import '../../../constants.dart';

class RecentEvidences extends StatelessWidget {
  const RecentEvidences({
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
            "Recent Evidence Vault",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: defaultPadding),
          SizedBox(
            width: double.infinity,
            child: StreamBuilder<QuerySnapshot>(
              stream: EvidenceService.instance.getAllEvidencesStream(),
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
                        "No evidence has been recorded yet.",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  );
                }

                // Take the 5 most recent evidences
                final recentDocs = docs.take(5).toList();

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: dataTableColumnSpacing(context),
                    columns: const [
                      DataColumn(label: Text("User")),
                      DataColumn(label: Text("Type")),
                      DataColumn(label: Text("Location")),
                      DataColumn(label: Text("Note / Detail")),
                      DataColumn(label: Text("Size")),
                    ],
                    rows: recentDocs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final userName = data['userName'] ?? 'Unknown';
                      final type = data['type'] ?? 'unknown';
                      final location = data['location'] ?? 'Unknown Location';
                      final note = data['note'] ?? '';
                      final size = data['size'] ?? '—';
                  
                      IconData icon;
                      Color color;
                      if (type == 'photo') {
                        icon = Icons.image_rounded; color = C.accent;
                      } else if (type == 'video') {
                        icon = Icons.videocam_rounded; color = C.red;
                      } else if (type == 'audio') {
                        icon = Icons.mic_rounded; color = C.success;
                      } else if (type == 'note') {
                        icon = Icons.edit_note_rounded; color = C.warning;
                      } else {
                        icon = Icons.file_present_rounded; color = Colors.white54;
                      }
                  
                      return DataRow(
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                Icon(icon, color: color, size: 20),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
                                  child: Text(userName, style: const TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                          DataCell(Text(type.toUpperCase(), style: const TextStyle(color: Colors.white70))),
                          DataCell(Text(location, style: const TextStyle(color: Colors.white70))),
                          DataCell(
                            SizedBox(
                              width: Responsive.isMobile(context) ? 120 : 150,
                              child: Text(note, style: const TextStyle(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                            )
                          ),
                          DataCell(Text(size, style: const TextStyle(color: Colors.white70))),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
