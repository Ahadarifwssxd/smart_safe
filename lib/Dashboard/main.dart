import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartsafe/bootstrap/app_bootstrap.dart';
import 'package:smartsafe/Dashboard/controllers/menu_app_controller.dart';
import 'package:smartsafe/Dashboard/screens/main/main_screen.dart';
import 'package:smartsafe/theme/colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppBootstrap.ensureFirebase();
    AppBootstrap.scheduleBackgroundSeeding(includeDashboardDemo: true);
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeNotifier,
      builder: (context, mode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SmartSafe Admin Dashboard',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (context) => MenuAppController(),
              ),
            ],
            child: const MainScreen(),
          ),
        );
      },
    );
  }
}
