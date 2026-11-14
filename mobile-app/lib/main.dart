import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/meal_provider.dart';
import 'providers/nutrition_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // Notifications
  await NotificationService.init();
  await NotificationService.requestPermissions();

  // Schedule meal reminders + show welcome on first launch
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('notifications_scheduled') != true) {
    await NotificationService.scheduleMealReminders();
    await NotificationService.showWelcomeNotification();
    await prefs.setBool('notifications_scheduled', true);
  }

  // Re-schedule water reminders on restart if user had them enabled
  if (prefs.getBool('water_reminders_enabled') == true) {
    await NotificationService.scheduleWaterReminders();
  }

  // Re-schedule end-of-day summary on restart if it was previously set
  if (prefs.getBool('end_of_day_scheduled') == true) {
    await NotificationService.scheduleEndOfDaySummary();
  }

  // Re-schedule contextual lunch/dinner reminders every app open (one-shot)
  await NotificationService.scheduleLunchReminder();
  await NotificationService.scheduleDinnerReminder();

  runApp(const NutriScanApp());
}

class NutriScanApp extends StatelessWidget {
  const NutriScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => MealProvider()),
        ChangeNotifierProvider(
          create: (_) => NutritionProvider()..loadFromPrefs(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'NutriScan',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.theme,
          darkTheme: AppTheme.darkTheme,
          themeMode:
              themeProvider.isDark ? ThemeMode.dark : ThemeMode.light,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
