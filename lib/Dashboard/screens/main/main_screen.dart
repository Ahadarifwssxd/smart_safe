import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartsafe/Dashboard/controllers/menu_app_controller.dart';
import 'package:smartsafe/Dashboard/navigation/dashboard_router.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/screens/login/admin_login_screen.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';

import 'components/side_menu.dart';

class MainScreen extends StatefulWidget {
  final bool initialAuthenticated;
  const MainScreen({Key? key, this.initialAuthenticated = false}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late bool _isAuthenticated;

  @override
  void initState() {
    super.initState();
    _isAuthenticated = widget.initialAuthenticated;
    _checkFirebaseAdmin();
  }

  Future<void> _checkFirebaseAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (user.email?.trim().toLowerCase() == 'donnaevo073@gmail.com') {
      if (mounted) setState(() => _isAuthenticated = true);
      return;
    }
    final isAdmin = await FirebaseService.instance.userHasAdminRole(user.uid);
    if (isAdmin && mounted) setState(() => _isAuthenticated = true);
  }

  void _onLogout(MenuAppController menuController) async {
    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
    setState(() {
      _isAuthenticated = false;
      menuController.setSelectedRoute('dashboard');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return AdminLoginScreen(
        onLoginSuccess: () => setState(() => _isAuthenticated = true),
      );
    }

    final showSidebar = !Responsive.isMobile(context);

    return Scaffold(
      key: context.read<MenuAppController>().scaffoldKey,
      drawer: showSidebar ? null : const SideMenu(permanent: false),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSidebar) const SideMenu(permanent: true),
            Expanded(
              child: Consumer<MenuAppController>(
                builder: (context, menuController, child) {
                  return DashboardRouter.screenForRoute(
                    menuController.selectedRouteKey,
                    onLogout: () => _onLogout(menuController),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
