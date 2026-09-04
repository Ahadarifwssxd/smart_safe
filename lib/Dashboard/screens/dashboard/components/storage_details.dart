import 'package:flutter/material.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../constants.dart';
import 'chart.dart';
import 'storage_info_card.dart';

class StorageDetails extends StatelessWidget {
  const StorageDetails({
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
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.instance.getAlertsStream(),
        builder: (context, snapshot) {
          int critical = 0;
          int silent = 0;
          int crash = 0;
          int medical = 0;

          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data != null) {
                final type = data['alertType']?.toString() ?? '';
                if (type == 'Critical SOS') {
                  critical++;
                } else if (type == 'Silent SOS') {
                  silent++;
                } else if (type == 'Crash Detected') {
                  crash++;
                } else if (type == 'Medical Emergency') {
                  medical++;
                }
              }
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Alerts Breakdown",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: defaultPadding),
              Chart(
                critical: critical,
                silent: silent,
                crash: crash,
                medical: medical,
              ),
              StorageInfoCard(
                icon: Icons.error_rounded,
                iconColor: C.accent,
                title: "Critical SOS",
                amountOfFiles: "$critical Alerts",
                numOfFiles: critical,
              ),
              StorageInfoCard(
                icon: Icons.notifications_off_rounded,
                iconColor: C.warning,
                title: "Silent SOS",
                amountOfFiles: "$silent Alerts",
                numOfFiles: silent,
              ),
              StorageInfoCard(
                icon: Icons.car_crash_rounded,
                iconColor: C.accent,
                title: "Road Crashes",
                amountOfFiles: "$crash Incidents",
                numOfFiles: crash,
              ),
              StorageInfoCard(
                icon: Icons.medical_services_rounded,
                iconColor: C.success,
                title: "Medical Requests",
                amountOfFiles: "$medical Alerts",
                numOfFiles: medical,
              ),
            ],
          );
        },
      ),
    );
  }
}
