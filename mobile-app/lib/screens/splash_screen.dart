import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showTagline = false;

  @override
  void initState() {
    super.initState();
    // Delay tagline so typewriter starts after logo entrance completes
    Future.delayed(const Duration(milliseconds: 750),
        () { if (mounted) setState(() => _showTagline = true); });
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    while (authProvider.status == AuthStatus.unknown) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    if (!mounted) return;

    Widget destination;
    if (!authProvider.isAuthenticated) {
      destination = const LoginScreen();
    } else {
      final prefs = await SharedPreferences.getInstance();
      final onboardingDone = prefs.getBool('onboarding_complete') ?? false;
      destination =
          onboardingDone ? const HomeScreen() : const OnboardingScreen();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),

            // Icon with elastic bounce
            const Icon(Icons.restaurant_menu_rounded,
                    size: 72, color: Colors.white)
                .animate()
                .scale(
                  begin: const Offset(0.0, 0.0),
                  end: const Offset(1.0, 1.0),
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                )
                .fade(begin: 0, end: 1, duration: 300.ms),

            const SizedBox(height: 20),

            // App name — scale + fade
            const Text(
              'NutriScan',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1,
              ),
            )
                .animate()
                .fade(begin: 0, end: 1, duration: 500.ms, delay: 200.ms)
                .scale(
                  begin: const Offset(0.75, 0.75),
                  end: const Offset(1.0, 1.0),
                  duration: 500.ms,
                  delay: 200.ms,
                  curve: Curves.easeOut,
                ),

            const SizedBox(height: 12),

            // Tagline — typewriter, added to tree at 750ms
            SizedBox(
              height: 24,
              child: _showTagline
                  ? AnimatedTextKit(
                      isRepeatingAnimation: false,
                      animatedTexts: [
                        TypewriterAnimatedText(
                          'AI Food Recognition & Nutrition',
                          textStyle: const TextStyle(
                              fontSize: 15, color: Colors.white70),
                          speed: const Duration(milliseconds: 42),
                          cursor: '',
                        ),
                      ],
                    ).animate().fade(begin: 0, end: 1, duration: 300.ms)
                  : const SizedBox.shrink(),
            ),

            const Spacer(),

            const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5)
                .animate(delay: 900.ms)
                .fade(begin: 0, end: 1, duration: 400.ms),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
