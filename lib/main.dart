// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'providers/expense_provider.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/notification_service.dart';
import 'utils/app_theme.dart';
import 'widgets/loading_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const LoadingScreen()));
  try {
    await NotificationService.init();
  } catch (_) {
    // Keep the app usable if notification setup is unavailable on a device.
  }
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } catch (_) {
    // SQLite remains the source of truth if cloud sync is unavailable.
  }

  // Lock to portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.bgCard,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Check if onboarding has been completed
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

  runApp(ExpenseTrackerApp(
    showOnboarding: !onboardingDone,
    isLoggedIn: isLoggedIn,
  ));
}

class ExpenseTrackerApp extends StatelessWidget {
  final bool showOnboarding;
  final bool isLoggedIn;
  const ExpenseTrackerApp({
    super.key,
    this.showOnboarding = false,
    this.isLoggedIn = false,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
      ],
      child: Consumer<ExpenseProvider>(
          builder: (context, preferences, _) => MaterialApp(
                title: 'Spendly',
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: preferences.colorTheme == 'Dark'
                    ? ThemeMode.dark
                    : preferences.colorTheme == 'System'
                        ? ThemeMode.system
                        : ThemeMode.light,
                debugShowCheckedModeBanner: false,
                builder: (context, child) {
                  final light =
                      Theme.of(context).brightness == Brightness.light;
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness:
                          light ? Brightness.dark : Brightness.light,
                      systemNavigationBarColor: AppPalette.of(context).bgCard,
                      systemNavigationBarIconBrightness:
                          light ? Brightness.dark : Brightness.light,
                    ),
                    child: child!,
                  );
                },
                home: showOnboarding
                    ? const OnboardingScreen()
                    : const LoginScreen(),
              )),
    );
  }
}
