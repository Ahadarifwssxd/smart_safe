import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/dashboard_activity_chart.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/dashboard_kpi_row.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/dashboard_pro_subscribers.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/dashboard_quick_access_grid.dart';
import 'package:flutter/material.dart';

import '../../constants.dart';
import 'components/header.dart';
import 'components/recent_files.dart';
import 'components/storage_details.dart';
import 'components/live_users_location.dart';
import 'components/recent_evidences.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Header(),
            const SizedBox(height: defaultPadding),
            const DashboardKpiRow(),
            const SizedBox(height: defaultPadding),

            // ── Live PRO Subscriptions Overview ───────────────────
            const DashboardProSubscribers(),
            const SizedBox(height: defaultPadding),

            if (Responsive.isMobile(context))
              const Column(
                children: [
                  StorageDetails(),
                  SizedBox(height: defaultPadding),
                  DashboardActivityChart(),
                ],
              )
            else
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: StorageDetails()),
                  SizedBox(width: defaultPadding),
                  Expanded(flex: 2, child: DashboardActivityChart()),
                ],
              ),
            const SizedBox(height: defaultPadding),
            const DashboardQuickAccessGrid(),
            const SizedBox(height: defaultPadding),
            const LiveUsersLocation(),
            const SizedBox(height: defaultPadding),
            const RecentEvidences(),
            const SizedBox(height: defaultPadding),
            const RecentFiles(),
          ],
        ),
      ),
    );
  }
}

