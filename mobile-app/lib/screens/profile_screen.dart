import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'fasting_screen.dart';
import 'favorites_screen.dart';
import 'health_calculator_screen.dart';
import 'health_info_screen.dart';
import 'login_screen.dart';
import 'manual_food_screen.dart';
import 'weight_tracking_screen.dart';

class ProfileScreen extends StatelessWidget {
  final bool embedded;
  const ProfileScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // Avatar
              Center(
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: AppColors.lightGreen,
                  child: const Icon(Icons.person,
                      size: 60, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  user?.displayName ?? 'User',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  user?.email ?? '',
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.hintGreen),
                ),
              ),
              const SizedBox(height: 28),

              // ── Account section ──────────────────────────────────────────
              _SectionLabel('Account'),
              _ProfileButton(
                icon: Icons.person_outline,
                label: 'Edit Profile',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EditProfileScreen())),
              ),
              _ProfileButton(
                icon: Icons.lock_outline,
                label: 'Change Password',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen())),
              ),

              const SizedBox(height: 16),

              // ── Tools section ─────────────────────────────────────────────
              _SectionLabel('Tools'),
              _ProfileButton(
                icon: Icons.calculate_outlined,
                label: 'Health Calculator (BMI / TDEE)',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const HealthCalculatorScreen())),
              ),
              _ProfileButton(
                icon: Icons.monitor_weight_outlined,
                label: 'Weight Tracking',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const WeightTrackingScreen())),
              ),
              _ProfileButton(
                icon: Icons.favorite_outline,
                label: 'Favorite Foods',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FavoritesScreen())),
              ),
              _ProfileButton(
                icon: Icons.edit_note_outlined,
                label: 'Manual Food Entry',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ManualFoodScreen())),
              ),
              _ProfileButton(
                icon: Icons.timer_outlined,
                label: 'Intermittent Fasting',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FastingScreen())),
              ),
              _ProfileButton(
                icon: Icons.health_and_safety_outlined,
                label: 'Health Information',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const HealthInfoScreen())),
              ),

              const SizedBox(height: 16),

              // ── Preferences section ───────────────────────────────────────
              _SectionLabel('Preferences'),
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.dark_mode_outlined,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Dark Mode',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                    ),
                    Switch(
                      value: theme.isDark,
                      onChanged: (_) => theme.toggle(),
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Sign out ──────────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: () async {
                  final authProvider = context.read<AuthProvider>();
                  final navigator = Navigator.of(context);
                  await NotificationService.cancelWaterReminders();
                  await NotificationService.cancelEndOfDaySummary();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('water_reminders_enabled', false);
                  await prefs.setBool('end_of_day_scheduled', false);
                  await authProvider.signOut();
                  navigator.pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
                      (_) => false);
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.hintGreen)),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.hintGreen),
            ],
          ),
        ),
      ),
    );
  }
}
