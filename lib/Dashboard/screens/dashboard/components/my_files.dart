import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/models/my_files.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../constants.dart';
import 'file_info_card.dart';

class MyFiles extends StatelessWidget {
  const MyFiles({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "My Files",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ElevatedButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: defaultPadding * 1.5,
                  vertical:
                      defaultPadding / (Responsive.isMobile(context) ? 2 : 1),
                ),
              ),
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text("Add New"),
            ),
          ],
        ),
        const SizedBox(height: defaultPadding),
        Responsive(
          mobile: FileInfoCardGridView(
            crossAxisCount: size.width < 650 ? 2 : 4,
            childAspectRatio: size.width < 650 ? 1.3 : 1,
          ),
          tablet: const FileInfoCardGridView(),
          desktop: FileInfoCardGridView(
            childAspectRatio: size.width < 1400 ? 1.1 : 1.4,
          ),
        ),
      ],
    );
  }
}

class FileInfoCardGridView extends StatelessWidget {
  const FileInfoCardGridView({
    Key? key,
    this.crossAxisCount = 4,
    this.childAspectRatio = 1,
  }) : super(key: key);

  final int crossAxisCount;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: defaultPadding,
        mainAxisSpacing: defaultPadding,
        childAspectRatio: childAspectRatio,
      ),
      children: [
        // Grid item 0: Active SOS Alerts
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.instance.getAlertsStream(),
          builder: (context, snapshot) {
            int activeCount = 0;
            if (snapshot.hasData) {
              activeCount = snapshot.data!.docs
                  .where((doc) {
                    final data = doc.data() as Map<String, dynamic>?;
                    return data != null && data['status'] == 'Active';
                  })
                  .length;
            }
            final info = CloudStorageInfo(
              title: "Active SOS Alerts",
              numOfFiles: activeCount,
              totalStorage: "$activeCount Active",
              color: const Color(0xFFFF3B4F),
              percentage: activeCount > 0 ? (activeCount * 25).clamp(5, 100) : 0,
              icon: Icons.warning_amber_rounded,
            );
            return FileInfoCard(info: info);
          },
        ),
        // Grid item 1: Trusted Contacts
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.instance.getContactsStream(),
          builder: (context, snapshot) {
            int count = 0;
            if (snapshot.hasData) {
              count = snapshot.data!.docs.length;
            }
            final info = CloudStorageInfo(
              title: "Trusted Contacts",
              numOfFiles: count,
              totalStorage: "$count Contacts",
              color: const Color(0xFF4D9FFF),
              percentage: count > 0 ? (count * 20).clamp(5, 100) : 0,
              icon: Icons.people_rounded,
            );
            return FileInfoCard(info: info);
          },
        ),
        // Grid item 2: Danger Zones
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.instance.getDangerZonesStream(),
          builder: (context, snapshot) {
            int count = 0;
            if (snapshot.hasData) {
              count = snapshot.data!.docs.length;
            }
            final info = CloudStorageInfo(
              title: "Danger Zones",
              numOfFiles: count,
              totalStorage: "$count Zones",
              color: const Color(0xFFFFB347),
              percentage: count > 0 ? (count * 15).clamp(5, 100) : 0,
              icon: Icons.dangerous_rounded,
            );
            return FileInfoCard(info: info);
          },
        ),
        // Grid item 3: Incident Reports
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.instance.getIncidentReportsStream(),
          builder: (context, snapshot) {
            int count = 0;
            if (snapshot.hasData) {
              count = snapshot.data!.docs.length;
            }
            final info = CloudStorageInfo(
              title: "Incident Reports",
              numOfFiles: count,
              totalStorage: "$count Reports",
              color: const Color(0xFF00E5C8),
              percentage: count > 0 ? (count * 10).clamp(5, 100) : 0,
              icon: Icons.report_rounded,
            );
            return FileInfoCard(info: info);
          },
        ),
      ],
    );
  }
}
