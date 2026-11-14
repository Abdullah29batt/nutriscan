import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_model.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/meal_provider.dart';
import '../providers/nutrition_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'camera_screen.dart';
import 'favorites_screen.dart';
import 'health_calculator_screen.dart';
import 'history_screen.dart';
import 'manual_food_screen.dart';
import 'meal_plan_screen.dart';
import 'profile_screen.dart';
import 'weight_tracking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0; // 0=Home 1=History 2=Progress 3=Profile
  final _screenshotCtrl = ScreenshotController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<AuthProvider>().user;
      if (user != null) {
        context.read<MealProvider>().loadMeals(user.uid);
        context.read<MealProvider>().loadFavorites(user.uid);
        context.read<MealProvider>().loadFrequentFoods();
        context.read<NutritionProvider>().loadFromFirestore(user.uid);
      }
      // Schedule water reminders on first login (persists across restarts)
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('water_reminders_enabled') != true) {
        await NotificationService.scheduleWaterReminders();
        await prefs.setBool('water_reminders_enabled', true);
      }
      // Schedule daily 9 PM health summary
      if (prefs.getBool('end_of_day_scheduled') != true) {
        await NotificationService.scheduleEndOfDaySummary();
        await prefs.setBool('end_of_day_scheduled', true);
      }
    });
  }

  // Nav index maps 5 bottom items → 4 actual page indices
  // 0=Home 1=History  2=Scan(special) 3=Progress 4=Profile
  int get _navIndex => _tabIndex < 2 ? _tabIndex : _tabIndex + 1;

  void _onNavTap(int nav) {
    if (nav == 2) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const CameraScreen()));
      return;
    }
    setState(() => _tabIndex = nav < 2 ? nav : nav - 1);
  }

  @override
  Widget build(BuildContext context) {
    // Reconnect banner (Feature 3)
    final connectivity = context.watch<ConnectivityProvider>();
    if (connectivity.showReconnectBanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.wifi, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('🌐 Back online! Syncing your data...'),
            ]),
            backgroundColor: AppColors.primary,
            duration: Duration(seconds: 3),
          ),
        );
        context.read<ConnectivityProvider>().clearReconnectBanner();
        final user = context.read<AuthProvider>().user;
        if (user != null) {
          context.read<MealProvider>().loadMeals(user.uid);
          context.read<NutritionProvider>().loadFromFirestore(user.uid);
        }
      });
    }

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _DashboardTab(screenshotCtrl: _screenshotCtrl),
          const HistoryScreen(embedded: true),
          _ProgressTab(screenshotCtrl: _screenshotCtrl),
          const _ProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: _onNavTap,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: 'Home'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(
            icon: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withAlpha(100),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              child:
                  const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
            ),
            label: 'Scan',
          ),
          const BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded), label: 'Progress'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// DASHBOARD TAB
// ─────────────────────────────────────────────
class _DashboardTab extends StatelessWidget {
  final ScreenshotController screenshotCtrl;
  const _DashboardTab({required this.screenshotCtrl});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final meals = context.watch<MealProvider>();
    final nutrition = context.watch<NutritionProvider>();
    final connectivity = context.watch<ConnectivityProvider>();
    final user = auth.user;
    final uid = user?.uid;

    final goal = nutrition.dailyCalorieGoal;
    final consumed = meals.todayCalories;
    final remaining = (goal - consumed).clamp(0.0, double.infinity);
    final progress = (goal > 0 ? consumed / goal : 0.0).clamp(0.0, 1.0);

    final today = DateFormat('EEEE, MMM d').format(DateTime.now());
    final name = user?.displayName?.split(' ').first ?? 'there';

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: CircleAvatar(
              backgroundColor: AppColors.lightGreen,
              child: const Icon(Icons.person, color: AppColors.primary),
            ),
          ),
        ),
        title: Column(
          children: [
            Text('${_greeting()}, $name',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(today,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.hintGreen,
                    fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          if (connectivity.isOffline)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: _EdgeAIPill(
                  onTap: () => _showOfflineInfo(context),
                ),
              ),
            ),
          if (nutrition.streakDays > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '🔥 ${nutrition.streakDays}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          if (uid != null) {
            final mealProv = context.read<MealProvider>();
            final nutritionProv = context.read<NutritionProvider>();
            await mealProv.loadMeals(uid);
            await nutritionProv.loadFromFirestore(uid);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Calorie ring ─────────────────────────────────────────────
              _Card(
                staggerIndex: 0,
                child: Row(
                  children: [
                    CircularPercentIndicator(
                      radius: 70,
                      lineWidth: 10,
                      percent: progress,
                      animation: true,
                      center: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(consumed.toStringAsFixed(0),
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary)),
                          const Text('kcal',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.hintGreen)),
                        ],
                      ),
                      progressColor: progress >= 1.0
                          ? AppColors.error
                          : AppColors.primary,
                      backgroundColor: AppColors.lightGreen,
                      circularStrokeCap: CircularStrokeCap.round,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatRow(
                              icon: Icons.flag_outlined,
                              label: 'Goal',
                              value:
                                  '${goal.toStringAsFixed(0)} kcal'),
                          const SizedBox(height: 8),
                          _StatRow(
                              icon: Icons.restaurant_outlined,
                              label: 'Consumed',
                              value:
                                  '${consumed.toStringAsFixed(0)} kcal'),
                          const SizedBox(height: 8),
                          _StatRow(
                              icon: Icons.battery_charging_full,
                              label: 'Remaining',
                              value:
                                  '${remaining.toStringAsFixed(0)} kcal',
                              highlight: true),
                          const SizedBox(height: 8),
                          _StatRow(
                              icon: Icons.fastfood_outlined,
                              label: 'Meals',
                              value:
                                  '${meals.todayMealCount} today'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Health status alerts ──────────────────────────────────────
              const _HealthStatusCard(),

              const SizedBox(height: 12),

              // ── Macro progress bars ───────────────────────────────────────
              _Card(
                staggerIndex: 1,
                title: 'Macros',
                child: Column(
                  children: [
                    _MacroBar(
                        label: 'Protein',
                        consumed: meals.todayProtein,
                        goal: nutrition.proteinGoal,
                        color: Colors.blue),
                    const SizedBox(height: 10),
                    _MacroBar(
                        label: 'Carbs',
                        consumed: meals.todayCarbs,
                        goal: nutrition.carbsGoal,
                        color: Colors.amber.shade700),
                    const SizedBox(height: 10),
                    _MacroBar(
                        label: 'Fat',
                        consumed: meals.todayFat,
                        goal: nutrition.fatGoal,
                        color: Colors.red),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Water tracker ─────────────────────────────────────────────
              _Card(
                staggerIndex: 2,
                title: 'Water  💧',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: List.generate(
                                nutrition.waterGoal.clamp(1, 12), (i) {
                              final filled = i < nutrition.waterIntake;
                              return Icon(
                                filled
                                    ? Icons.water_drop
                                    : Icons.water_drop_outlined,
                                color: filled
                                    ? AppColors.primary
                                    : AppColors.hintGreen,
                                size: 26,
                              );
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            _CircleBtn(
                              icon: Icons.add,
                              onTap: () => nutrition.addWater(uid: uid),
                            ),
                            const SizedBox(height: 4),
                            _CircleBtn(
                              icon: Icons.remove,
                              onTap: () => nutrition.removeWater(uid: uid),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${nutrition.waterIntake} / ${nutrition.waterGoal} glasses',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.hintGreen),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Weekly bar chart ──────────────────────────────────────────
              _Card(
                staggerIndex: 3,
                title: 'Weekly Calories',
                child: SizedBox(
                  height: 140,
                  child: _WeeklyChart(data: meals.last7DaysCalories),
                ),
              ),

              const SizedBox(height: 12),

              // ── Quick Log (Feature 4) ─────────────────────────────────────
              if (meals.frequentFoods.isNotEmpty)
                _Card(
                  staggerIndex: 4,
                  title: '⚡ Quick Log',
                  child: SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: meals.frequentFoods.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final food = meals.frequentFoods[i];
                        final name = food['foodName'] as String;
                        final nutrition =
                            food['nutrition'] as NutritionInfo;
                        final cal = nutrition.calories
                            .toStringAsFixed(0);
                        return GestureDetector(
                          onTap: () async {
                            if (uid == null) return;
                            await meals.quickLogFood(name, uid,
                                nutrition: nutrition);
                            await meals.loadFrequentFoods();
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('✅ $name logged!'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      AppColors.primary.withAlpha(50)),
                            ),
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                                const SizedBox(height: 2),
                                Text('$cal kcal',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.hintGreen)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // ── Quick actions ─────────────────────────────────────────────
              _Card(
                staggerIndex: 4,
                title: 'Quick Actions',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _QuickAction(
                      icon: Icons.camera_alt_outlined,
                      label: 'Scan Food',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const CameraScreen())),
                    ),
                    _QuickAction(
                      icon: Icons.edit_outlined,
                      label: 'Manual Entry',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ManualFoodScreen())),
                    ),
                    _QuickAction(
                      icon: Icons.favorite_outline,
                      label: 'Favorites',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const FavoritesScreen())),
                    ),
                    _QuickAction(
                      icon: Icons.calendar_month_outlined,
                      label: 'Meal Plan',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const MealPlanScreen())),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Recent meals (with Log again) ─────────────────────────────
              if (meals.todayMeals.isNotEmpty)
                _Card(
                  staggerIndex: 5,
                  title: "Today's Meals",
                  child: Column(
                    children: meals.todayMeals.take(3).map((m) {
                      return _RecentMealTile(
                        meal: m,
                        onLogAgain: uid == null
                            ? null
                            : () async {
                                await meals.quickLogFood(
                                  m.foodName,
                                  uid,
                                  nutrition: m.nutrition,
                                );
                                await meals.loadFrequentFoods();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '✅ ${m.foodName} logged again!'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PROGRESS TAB
// ─────────────────────────────────────────────
class _ProgressTab extends StatefulWidget {
  final ScreenshotController screenshotCtrl;
  const _ProgressTab({required this.screenshotCtrl});

  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab> {
  final _weightCtrl = TextEditingController();

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    try {
      final Uint8List? img = await widget.screenshotCtrl.capture();
      if (img == null || !mounted) return;
      final xFile =
          XFile.fromData(img, mimeType: 'image/png', name: 'progress.png');
      await Share.shareXFiles([xFile], text: 'My NutriScan Progress');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealProvider>();
    final nutrition = context.watch<NutritionProvider>();
    final today = DateTime.now();
    final dayLabels = List.generate(
        7,
        (i) => DateFormat('E')
            .format(today.subtract(Duration(days: 6 - i))));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        actions: [
          IconButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const WeightTrackingScreen())),
              icon: const Icon(Icons.monitor_weight_outlined)),
          IconButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const HealthCalculatorScreen())),
              icon: const Icon(Icons.calculate_outlined)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          children: [
            Screenshot(
              controller: widget.screenshotCtrl,
              child: Column(
                children: [
                  // Weekly bar chart
                  _Card(
                    title: 'Weekly Calories',
                    child: SizedBox(
                      height: 180,
                      child: BarChart(
                        BarChartData(
                          maxY: (meals.last7DaysCalories.isEmpty
                                  ? 2500
                                  : meals.last7DaysCalories
                                          .reduce(max) +
                                      300)
                              .toDouble(),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) {
                                  final i = v.toInt();
                                  if (i < 0 || i >= dayLabels.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return Text(dayLabels[i],
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.hintGreen));
                                },
                              ),
                            ),
                          ),
                          barGroups: List.generate(7, (i) {
                            final cal = i < meals.last7DaysCalories.length
                                ? meals.last7DaysCalories[i]
                                : 0.0;
                            return BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: cal,
                                color: AppColors.primary,
                                width: 18,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ]);
                          }),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Macro pie chart
                  _Card(
                    title: "Today's Macros",
                    child: meals.todayCalories == 0
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'Start scanning food to see your progress!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.hintGreen),
                              ),
                            ),
                          )
                        : SizedBox(
                            height: 200,
                            child: Row(
                              children: [
                                Expanded(
                                  child: PieChart(PieChartData(
                                    centerSpaceRadius: 40,
                                    sections: [
                                      PieChartSectionData(
                                          value: meals.todayProtein,
                                          color: Colors.blue,
                                          title: '',
                                          radius: 55),
                                      PieChartSectionData(
                                          value: meals.todayCarbs,
                                          color: Colors.amber,
                                          title: '',
                                          radius: 55),
                                      PieChartSectionData(
                                          value: meals.todayFat,
                                          color: Colors.red,
                                          title: '',
                                          radius: 55),
                                    ],
                                  )),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _LegendDot(
                                        color: Colors.blue,
                                        label:
                                            'Protein ${meals.todayProtein.toStringAsFixed(1)}g'),
                                    const SizedBox(height: 8),
                                    _LegendDot(
                                        color: Colors.amber,
                                        label:
                                            'Carbs ${meals.todayCarbs.toStringAsFixed(1)}g'),
                                    const SizedBox(height: 8),
                                    _LegendDot(
                                        color: Colors.red,
                                        label:
                                            'Fat ${meals.todayFat.toStringAsFixed(1)}g'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Water intake card
                  _Card(
                    title: 'Water Intake',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${nutrition.waterIntake}/${nutrition.waterGoal} glasses',
                            style: const TextStyle(
                                color: AppColors.hintGreen, fontSize: 13)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(
                              nutrition.waterGoal.clamp(1, 12), (i) {
                            final f = i < nutrition.waterIntake;
                            return Icon(
                              f
                                  ? Icons.water_drop
                                  : Icons.water_drop_outlined,
                              color:
                                  f ? AppColors.primary : AppColors.hintGreen,
                              size: 28,
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: const Text('Share Progress'),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PROFILE TAB (wrapper so ProfileScreen has context)
// ─────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) => const ProfileScreen(embedded: true);
}

// ─────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String? title;
  final Widget child;
  final int staggerIndex;
  const _Card({this.title, required this.child, this.staggerIndex = -1});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightGreen,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(isDark ? 8 : 20),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.primary)),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
    if (staggerIndex >= 0) {
      card = card
          .animate(delay: (staggerIndex * 90).ms)
          .fadeIn(duration: 350.ms, curve: Curves.easeOut)
          .slideY(begin: 0.04, end: 0, curve: Curves.easeOut);
    }
    return card;
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  const _StatRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.hintGreen),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.hintGreen)),
        ),
        const SizedBox(width: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: highlight ? AppColors.accent : AppColors.primary)),
        ),
      ],
    );
  }
}

class _MacroBar extends StatelessWidget {
  final String label;
  final double consumed;
  final double goal;
  final Color color;
  const _MacroBar(
      {required this.label,
      required this.consumed,
      required this.goal,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = goal > 0 ? (consumed / goal).clamp(0.0, 1.0) : 0.0;
    final barColor =
        pct >= 1.0 ? AppColors.error : pct >= 0.9 ? AppColors.orange : color;
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.hintGreen)),
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: pct),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            builder: (_, value, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: color.withAlpha(30),
                color: barColor,
                minHeight: 8,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${consumed.toStringAsFixed(0)}/${goal.toStringAsFixed(0)}g',
          style: const TextStyle(fontSize: 11, color: AppColors.hintGreen),
        ),
      ],
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _WeeklyChart extends StatefulWidget {
  final List<double> data;
  const _WeeklyChart({required this.data});

  @override
  State<_WeeklyChart> createState() => _WeeklyChartState();
}

class _WeeklyChartState extends State<_WeeklyChart> {
  late List<double> _displayed;

  @override
  void initState() {
    super.initState();
    // Start from zero so BarChart animates bars up on first display
    _displayed = List.filled(widget.data.length, 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _displayed = widget.data);
    });
  }

  @override
  void didUpdateWidget(_WeeklyChart old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) {
      setState(() => _displayed = widget.data);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.every((d) => d == 0)) {
      return const Center(
        child: Text('Start scanning food to see your progress!',
            style: TextStyle(color: AppColors.hintGreen, fontSize: 13)),
      );
    }
    final maxY = widget.data.reduce(max) + 300;
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: List.generate(_displayed.length, (i) {
          return BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: _displayed[i],
              color: AppColors.primary,
              width: 14,
              borderRadius: BorderRadius.circular(3),
            ),
          ]);
        }),
      ),
      swapAnimationDuration: const Duration(milliseconds: 700),
      swapAnimationCurve: Curves.easeOut,
    );
  }
}

class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: (MediaQuery.of(context).size.width - 64) / 2,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(_pressed ? 20 : 12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withAlpha(40)),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentMealTile extends StatelessWidget {
  final MealModel meal;
  final VoidCallback? onLogAgain;
  const _RecentMealTile({required this.meal, this.onLogAgain});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(meal.timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.restaurant, color: AppColors.hintGreen, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.foodName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('$timeStr · ${meal.nutrition.calories.toStringAsFixed(0)} kcal',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.hintGreen)),
              ],
            ),
          ),
          if (onLogAgain != null)
            TextButton(
              onPressed: onLogAgain,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.primary,
              ),
              child: const Text('Log again',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style:
              const TextStyle(fontSize: 12, color: AppColors.primary)),
    ]);
  }
}

// ─────────────────────────────────────────────
// HEALTH STATUS CARD
// ─────────────────────────────────────────────

class _HealthStatusCard extends StatelessWidget {
  const _HealthStatusCard();

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealProvider>();
    final nutrition = context.watch<NutritionProvider>();
    final hour = DateTime.now().hour;
    final alerts = _buildAlerts(meals, nutrition, hour);

    // Nothing to show before user logs any meals on a fresh early morning
    if (alerts.isEmpty && meals.todayMealCount == 0 && hour < 10) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: alerts.isEmpty
          ? [
              _AlertRow(
                icon: Icons.check_circle_outline,
                color: AppColors.primary,
                message: 'All goals on track today! Keep it up.',
              ),
            ]
          : alerts
              .map((a) =>
                  _AlertRow(icon: a.icon, color: a.color, message: a.message))
              .toList(),
    );
  }

  List<({IconData icon, Color color, String message})> _buildAlerts(
    MealProvider meals,
    NutritionProvider nutrition,
    int hour,
  ) {
    final list = <({IconData icon, Color color, String message})>[];

    // ── Calories ──────────────────────────────────────────────────────────────
    final cal = meals.todayCalories;
    final calGoal = nutrition.dailyCalorieGoal;
    final calPct = calGoal > 0 ? cal / calGoal : 0.0;

    if (calPct > 1.0) {
      list.add((
        icon: Icons.warning_amber_rounded,
        color: AppColors.error,
        message:
            'Calorie goal exceeded by ${(cal - calGoal).toStringAsFixed(0)} kcal!',
      ));
    } else if (calPct > 0.9) {
      list.add((
        icon: Icons.info_outline,
        color: AppColors.orange,
        message:
            'Almost at calorie goal — ${(calGoal - cal).toStringAsFixed(0)} kcal remaining',
      ));
    } else if (hour >= 14 && meals.todayMealCount == 0) {
      list.add((
        icon: Icons.restaurant_outlined,
        color: const Color(0xFFFFCA28),
        message: 'No meals logged yet — don\'t forget to eat!',
      ));
    } else if (calPct < 0.3 && hour >= 14 && meals.todayMealCount > 0) {
      list.add((
        icon: Icons.battery_alert,
        color: const Color(0xFFFFCA28),
        message:
            'Low calorie intake — only ${(calPct * 100).toStringAsFixed(0)}% of daily goal logged',
      ));
    }

    // ── Protein ───────────────────────────────────────────────────────────────
    final protein = meals.todayProtein;
    final proteinGoal = nutrition.proteinGoal;
    final proteinPct = proteinGoal > 0 ? protein / proteinGoal : 0.0;

    if (proteinPct > 1.2) {
      list.add((
        icon: Icons.fitness_center,
        color: AppColors.error,
        message:
            'High protein: ${protein.toStringAsFixed(0)}g — ${((proteinPct - 1) * 100).toStringAsFixed(0)}% over goal',
      ));
    } else if (proteinPct >= 1.0) {
      list.add((
        icon: Icons.check_circle_outline,
        color: AppColors.primary,
        message:
            'Protein goal met! ${protein.toStringAsFixed(0)}g / ${proteinGoal.toStringAsFixed(0)}g',
      ));
    } else if (proteinPct < 0.4 && hour >= 14 && meals.todayMealCount > 0) {
      list.add((
        icon: Icons.fitness_center,
        color: const Color(0xFFFFCA28),
        message:
            'Low protein: ${protein.toStringAsFixed(0)}g of ${proteinGoal.toStringAsFixed(0)}g goal',
      ));
    }

    // ── Fat ───────────────────────────────────────────────────────────────────
    final fat = meals.todayFat;
    final fatGoal = nutrition.fatGoal;
    final fatPct = fatGoal > 0 ? fat / fatGoal : 0.0;

    if (fatPct > 1.2) {
      list.add((
        icon: Icons.opacity,
        color: AppColors.error,
        message:
            'High fat: ${fat.toStringAsFixed(0)}g — ${((fatPct - 1) * 100).toStringAsFixed(0)}% over daily limit',
      ));
    }

    // ── Carbs ─────────────────────────────────────────────────────────────────
    final carbs = meals.todayCarbs;
    final carbsGoal = nutrition.carbsGoal;
    final carbsPct = carbsGoal > 0 ? carbs / carbsGoal : 0.0;

    if (carbsPct > 1.2) {
      list.add((
        icon: Icons.grain,
        color: AppColors.error,
        message:
            'High carb intake: ${carbs.toStringAsFixed(0)}g — ${((carbsPct - 1) * 100).toStringAsFixed(0)}% over goal',
      ));
    }

    // ── Water ─────────────────────────────────────────────────────────────────
    final water = nutrition.waterIntake;
    final waterGoal = nutrition.waterGoal;

    if (water >= waterGoal) {
      list.add((
        icon: Icons.water_drop,
        color: AppColors.primary,
        message: 'Water goal met! $water/$waterGoal glasses 💧',
      ));
    } else if (water == 0 && hour >= 10) {
      list.add((
        icon: Icons.water_drop_outlined,
        color: AppColors.error,
        message: 'No water logged yet today — stay hydrated!',
      ));
    } else if (hour >= 19) {
      final needed = waterGoal - water;
      list.add((
        icon: Icons.water_drop_outlined,
        color: AppColors.orange,
        message:
            'Drink $needed more glass${needed > 1 ? 'es' : ''} to reach your water goal',
      ));
    } else if (hour >= 13 && water < waterGoal ~/ 2) {
      list.add((
        icon: Icons.water_drop_outlined,
        color: const Color(0xFFFFCA28),
        message: 'Low water intake — $water of $waterGoal glasses so far',
      ));
    }

    return list;
  }
}

class _AlertRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _AlertRow(
      {required this.icon, required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feature 3: Edge AI pill + offline info bottom sheet ──────────────────────

class _EdgeAIPill extends StatefulWidget {
  final VoidCallback onTap;
  const _EdgeAIPill({required this.onTap});

  @override
  State<_EdgeAIPill> createState() => _EdgeAIPillState();
}

class _EdgeAIPillState extends State<_EdgeAIPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B5E3B), Color(0xFF2E7D52)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            const Text(
              'Edge AI Mode',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Opacity(
                opacity: _pulse.value,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF69F0AE),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showOfflineInfo(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E3B), Color(0xFF2E7D52)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'NutriScan Edge AI Mode',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primary),
          ),
          const SizedBox(height: 10),
          const Text(
            'You\'re offline. NutriScan is using its on-device AI model '
            'to keep you tracking.\n\n'
            'Your data will sync automatically when you reconnect.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: AppColors.hintGreen, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ),
        ],
      ),
    ),
  );
}
