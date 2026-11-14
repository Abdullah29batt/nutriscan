import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_model.dart';
import '../providers/meal_provider.dart';
import '../providers/nutrition_provider.dart';
import '../services/gemini_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class ResultsScreen extends StatefulWidget {
  final String? mealType;
  const ResultsScreen({super.key, this.mealType});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _saved = false;
  bool _initialized = false;
  String? _healthTip;
  bool _loadingTip = false;

  // Single serving size (grams) for the displayed food card.
  double _servingSize = 100.0;

  // Snapshot of predictions at load time — stays stable even after chip taps
  // (which overwrite provider.allPredictions via updateCurrentMealFoodName).
  List<Map<String, dynamic>> _originalPredictions = [];

  // Index into _originalPredictions of the currently selected food.
  int _selectedPredictionIndex = 0;

  // Class names for the autocomplete correction field (Feature 1).
  List<String> _classNames = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final provider = context.read<MealProvider>();
      _servingSize = 100.0;
      _originalPredictions = List.from(provider.allPredictions);
      _fetchHealthTip(provider);
      _loadClassNames();

      // Offline confidence dialogs: < 50% = not detected, 50–70% = low confidence.
      if (provider.usedOnDeviceInference) {
        final confidence = provider.currentMeal?.confidence ?? 0.0;
        if (confidence < 0.50) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showFoodNotDetectedDialog();
          });
        } else if (confidence < 0.70) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showLowConfidenceDialog();
          });
        }
      }
    }
  }

  Future<void> _loadClassNames() async {
    try {
      final raw = await rootBundle.loadString('assets/class_names_filtered.json');
      final list = List<String>.from(json.decode(raw) as List);
      if (mounted) {
        setState(() => _classNames = list.map(_fmtClass).toList());
      }
    } catch (_) {}
  }

  String _fmtClass(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  Future<void> _fetchHealthTip(MealProvider provider) async {
    final meal = provider.currentMeal;
    if (meal == null) return;
    final nutrition = context.read<NutritionProvider>();
    final n = provider.nutritionPer100g;

    // Read stored profile data
    final prefs = await SharedPreferences.getInstance();
    final allergies = prefs.getStringList('health_allergies') ?? [];
    final dietRestrictions = prefs.getStringList('health_diet') ?? [];
    final healthGoal = prefs.getString('health_goal') ?? 'Eat Healthier';

    setState(() => _loadingTip = true);
    final tip = await GeminiService.getPersonalizedFeedback(
      foodName: meal.foodName,
      calories: n?.calories ?? 0,
      protein: n?.protein ?? 0,
      carbs: n?.carbs ?? 0,
      fat: n?.fat ?? 0,
      calorieGoal: nutrition.dailyCalorieGoal,
      todayCalories: provider.todayCalories,
      allergies: allergies,
      dietRestrictions: dietRestrictions,
      healthGoal: healthGoal,
    );
    if (mounted) setState(() { _healthTip = tip; _loadingTip = false; });
  }

  void _toggleFavorite(MealProvider meals) {
    final meal = meals.currentMeal;
    if (meal == null) return;
    final uid = meal.userId;
    if (uid.isEmpty) return;

    final label = meal.foodName.toLowerCase().replaceAll(' ', '_');
    if (meals.isFavorite(label)) {
      meals.removeFavorite(label, uid);
    } else {
      meals.addFavorite({
        'label': label,
        'display_name': meal.foodName,
        'nutrition': meal.nutrition.toJson(),
      }, uid);
    }
  }

  Future<void> _save() async {
    final mealProv = context.read<MealProvider>();
    final nutritionProv = context.read<NutritionProvider>();
    if (mealProv.currentMeal == null) return;

    // Scale nutrition to the serving size the user actually selected.
    final nutritionPer100g = mealProv.nutritionPer100g;
    if (nutritionPer100g != null) {
      final totalGrams = _servingSize;
      final f = totalGrams / 100;
      mealProv.applyServingAdjustment(
        totalGrams,
        NutritionInfo(
          calories: nutritionPer100g.calories * f,
          protein: nutritionPer100g.protein * f,
          carbs:   nutritionPer100g.carbs   * f,
          fat:     nutritionPer100g.fat     * f,
          fiber:   nutritionPer100g.fiber   * f,
          sugar:   nutritionPer100g.sugar   * f,
          sodium:  nutritionPer100g.sodium  * f,
        ),
      );
    }

    // Re-read after adjustment so assignMealToType gets the scaled values.
    final meal = mealProv.currentMeal!;
    await mealProv.saveCurrentMeal();

    if (!mounted) return;
    if (widget.mealType != null) {
      nutritionProv.assignMealToType(meal, widget.mealType!);
    }

    _checkAndAlert(mealProv, nutritionProv);
    _updateSmartNotifications(mealProv, nutritionProv);
    mealProv.loadFrequentFoods();

    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Meal saved to history!')),
    );
  }

  void _updateSmartNotifications(MealProvider meals, NutritionProvider nutrition) {
    final hour = DateTime.now().hour;
    if (hour < 15) NotificationService.cancelLunchReminder();
    if (hour >= 15) NotificationService.cancelDinnerReminder();
    NotificationService.scheduleEndOfDaySummary(
      todayCalories: meals.todayCalories,
      goalCalories: nutrition.dailyCalorieGoal,
    );
  }

  Widget _buildConfidenceWidget(MealProvider provider) {
    final confidence = provider.currentMeal?.confidence ?? 0.0;
    final isOnDevice = provider.usedOnDeviceInference;

    // Online + low confidence: autocomplete correction card (online path only).
    if (!isOnDevice && confidence < 0.7) {
      return _ConfidenceWarningCard(
        confidence: confidence,
        classNames: _classNames,
        onCorrect: provider.updateCurrentMealFoodName,
      );
    }

    // Online high confidence OR any offline result: confidence chip.
    // For offline low-confidence the dialog (see _showLowConfidenceDialog)
    // already warns the user — no inline card needed.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withAlpha(60)),
        ),
        child: Text(
          '✅ Identified with ${(confidence * 100).toStringAsFixed(0)}% confidence',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  void _checkAndAlert(MealProvider meals, NutritionProvider nutrition) {
    final cal = meals.todayCalories;
    final calGoal = nutrition.dailyCalorieGoal;
    if (calGoal > 0) {
      final pct = cal / calGoal;
      if (pct > 1.0) {
        NotificationService.sendImmediateAlert(
          id: 21,
          title: '⚠️ Calorie Goal Exceeded!',
          body:
              'You\'ve exceeded your daily goal by ${(cal - calGoal).toStringAsFixed(0)} kcal.',
        );
      } else if (pct > 0.9) {
        NotificationService.sendImmediateAlert(
          id: 21,
          title: '📊 Almost at Your Calorie Goal',
          body:
              'Only ${(calGoal - cal).toStringAsFixed(0)} kcal remaining — choose your next meal wisely!',
        );
      }
    }

    final fat = meals.todayFat;
    final fatGoal = nutrition.fatGoal;
    if (fatGoal > 0 && fat > fatGoal * 1.2) {
      NotificationService.sendImmediateAlert(
        id: 22,
        title: '⚠️ High Fat Intake',
        body:
            'Today\'s fat (${fat.toStringAsFixed(0)}g) is ${((fat / fatGoal - 1) * 100).toStringAsFixed(0)}% over your daily limit.',
      );
    }

    final carbs = meals.todayCarbs;
    final carbsGoal = nutrition.carbsGoal;
    if (carbsGoal > 0 && carbs > carbsGoal * 1.2) {
      NotificationService.sendImmediateAlert(
        id: 23,
        title: '⚠️ High Carb Intake',
        body:
            'Today\'s carbs (${carbs.toStringAsFixed(0)}g) are ${((carbs / carbsGoal - 1) * 100).toStringAsFixed(0)}% over your daily goal.',
      );
    }
  }

  void _discard() {
    context.read<MealProvider>().clearCurrentMeal();
    Navigator.of(context).pop();
  }

  void _showLowConfidenceDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Low Confidence'),
        content: const Text(
          'We are not confident about this result.\n'
          'Please try scanning again with better lighting.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _discard();
            },
            child: const Text('Try Again'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Use This Result Anyway'),
          ),
        ],
      ),
    );
  }

  void _showFoodNotDetectedDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Food Not Detected'),
        content: const Text(
          'The food could not be recognized.\n'
          'Please try scanning again with better lighting '
          'and a clearer view of the food.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _discard();
            },
            child: const Text('Try Again'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Use Anyway'),
          ),
        ],
      ),
    );
  }

  ({double cal, double protein, double carbs, double fat, double fiber})
      _totals(NutritionInfo n) {
    final f = _servingSize / 100;
    return (
      cal:     n.calories * f,
      protein: n.protein  * f,
      carbs:   n.carbs    * f,
      fat:     n.fat      * f,
      fiber:   n.fiber    * f,
    );
  }

  Widget _buildChip(int index, MealProvider provider) {
    final pred = _originalPredictions[index];
    final name = pred['display_name'] as String? ?? 'Unknown';
    final conf = (pred['confidence'] as num?)?.toDouble() ?? 0.0;
    final pct  = (conf * 100).toStringAsFixed(0);
    final isSelected = _selectedPredictionIndex == index;
    const selectedColor = Color(0xFF1B5E3B);

    return GestureDetector(
      onTap: () {
        provider.updateCurrentMealFoodName(name);
        setState(() => _selectedPredictionIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor
              : selectedColor.withAlpha(25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? selectedColor : selectedColor.withAlpha(100),
          ),
        ),
        child: Text(
          '$name  $pct%',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : selectedColor,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MealProvider>();
    final meal = provider.currentMeal;

    if (meal == null) {
      return const Scaffold(
        body: Center(child: Text('No results available.')),
      );
    }

    final isOnDevice = provider.usedOnDeviceInference;
    final nutritionPer100g = provider.nutritionPer100g;
    final totals = nutritionPer100g != null ? _totals(nutritionPer100g) : null;

    final topLabel = meal.foodName.toLowerCase().replaceAll(' ', '_');
    final isFav = provider.isFavorite(topLabel);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _discard,
        ),
        actions: [
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Colors.red : Colors.white,
            ),
            tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () => _toggleFavorite(provider),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero image ────────────────────────────────────────────────────
            SizedBox(
              height: 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(meal.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.lightGreen,
                      child: const Icon(Icons.fastfood,
                          size: 80, color: AppColors.primary),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Offline banner
                  if (isOnDevice) ...[
                    _OfflineBanner(),
                    const SizedBox(height: 12),
                  ],

                  // Confidence guardrail (Feature 1)
                  _buildConfidenceWidget(provider),
                  const SizedBox(height: 14),

                  const Text(
                    'Detected Foods',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nutritionPer100g != null
                        ? 'Adjust each serving size — nutrition updates in real time.'
                        : 'Nutrition unavailable (on-device mode).',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.hintGreen),
                  ),
                  const SizedBox(height: 14),

                  // ── Top prediction card ────────────────────────────────────
                  _FoodCard(
                    foodName: meal.foodName,
                    confidence: meal.confidence,
                    nutritionPer100g: nutritionPer100g,
                    servingSize: _servingSize,
                    onServingSizeChanged: (v) => setState(() => _servingSize = v),
                  )
                      .animate()
                      .fadeIn(duration: 350.ms, curve: Curves.easeOut)
                      .slideY(begin: 0.08, end: 0, curve: Curves.easeOut),

                  // ── Alternative prediction chips (if confidence < 85%) ──────
                  if (_originalPredictions.length > 1 &&
                      ((_originalPredictions[0]['confidence'] as num?)
                              ?.toDouble() ??
                          1.0) <
                          0.85) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Not what you scanned? Try:',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.hintGreen,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int i = 1; i < _originalPredictions.length; i++)
                          _buildChip(i, provider),
                      ],
                    ),
                  ],

                  // ── Total nutrition card ───────────────────────────────────
                  if (totals != null) ...[
                    const SizedBox(height: 8),
                    _TotalNutritionCard(
                      calories: totals.cal,
                      protein: totals.protein,
                      carbs: totals.carbs,
                      fat: totals.fat,
                      fiber: totals.fiber,
                    ),
                  ],

                  // ── Health tip ─────────────────────────────────────────────
                  const SizedBox(height: 16),
                  if (_loadingTip)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary),
                          ),
                          SizedBox(width: 10),
                          Text('Getting health tip…',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.hintGreen)),
                        ],
                      ),
                    )
                  else if (_healthTip != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.tips_and_updates_outlined,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _healthTip!,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // ── Action buttons ─────────────────────────────────────────
                  if (!_saved) ...[
                    ElevatedButton.icon(
                      onPressed: _servingSize > 0 ? _save : null,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save to History'),
                    ),
                    if (_servingSize == 0) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Please keep at least one item to log',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.hintGreen,
                        ),
                      ),
                    ],
                  ] else
                    OutlinedButton.icon(
                      onPressed: _discard,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Done'),
                    ),
                  const SizedBox(height: 12),
                  if (!_saved)
                    TextButton(
                      onPressed: _discard,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        foregroundColor: AppColors.hintGreen,
                      ),
                      child: const Text('Discard'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.orange.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.orange.withAlpha(80)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Backend unreachable — identified on-device. '
              'Nutrition estimated by AI.',
              style: TextStyle(fontSize: 13, color: Color(0xFF795548)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card for a single detected food prediction.
class _FoodCard extends StatelessWidget {
  final String foodName;
  final double confidence;
  final NutritionInfo? nutritionPer100g;
  final double servingSize;
  final ValueChanged<double> onServingSizeChanged;

  const _FoodCard({
    required this.foodName,
    required this.confidence,
    this.nutritionPer100g,
    required this.servingSize,
    required this.onServingSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final n = nutritionPer100g;
    final factor = servingSize / 100;
    final pct = (confidence * 100).toStringAsFixed(0);
    final confColor = confidence >= 0.8
        ? AppColors.primary
        : confidence >= 0.5
            ? const Color(0xFFFFCA28)
            : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + confidence badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    foodName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: confColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: confColor.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 13, color: confColor),
                      const SizedBox(width: 4),
                      Text(
                        '$pct%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: confColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Serving slider
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Serving',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: servingSize,
                    min: 0,
                    max: 500,
                    divisions: 500,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.lightGreen,
                    onChanged: onServingSizeChanged,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${servingSize.toStringAsFixed(0)}g',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

            // Nutrition row
            if (n != null) ...[
              const Divider(height: 12, thickness: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MacroChip(
                      label: 'Cal',
                      value: n.calories * factor,
                      isCalories: true),
                  _MacroChip(label: 'Protein', value: n.protein * factor),
                  _MacroChip(label: 'Carbs', value: n.carbs * factor),
                  _MacroChip(label: 'Fat', value: n.fat * factor),
                  _MacroChip(label: 'Fiber', value: n.fiber * factor),
                ],
              ),
            ] else ...[
              const SizedBox(height: 4),
              const Text(
                'Nutrition data not available',
                style: TextStyle(fontSize: 12, color: AppColors.hintGreen),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact macro display used inside each food card.
class _MacroChip extends StatelessWidget {
  final String label;
  final double value;
  final bool isCalories;

  const _MacroChip({
    required this.label,
    required this.value,
    this.isCalories = false,
  });

  @override
  Widget build(BuildContext context) {
    final display =
        isCalories ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    final unit = isCalories ? 'kcal' : 'g';

    return Column(
      children: [
        Text(
          '$display$unit',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style:
              const TextStyle(fontSize: 10, color: AppColors.hintGreen),
        ),
      ],
    );
  }
}

/// Summary card showing combined nutrition for all foods.
class _TotalNutritionCard extends StatelessWidget {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;

  const _TotalNutritionCard({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: AppColors.cardGreen,
        child: Column(
          children: [
            // Calorie header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: AppColors.primary,
              child: Column(
                children: [
                  const Text(
                    'Total Nutrition',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: calories),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    builder: (_, value, __) => Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const Text(
                    'kcal',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            // Macro row
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MacroTile(label: 'Protein', value: protein),
                  _MacroTile(label: 'Carbs', value: carbs),
                  _MacroTile(label: 'Fat', value: fat),
                  _MacroTile(label: 'Fiber', value: fiber),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Macro display used in the total nutrition card.
class _MacroTile extends StatelessWidget {
  final String label;
  final double value;

  const _MacroTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${value.toStringAsFixed(1)}g',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.hintGreen),
        ),
      ],
    );
  }
}

// ── Feature 1: confidence guardrail ──────────────────────────────────────────

/// Yellow warning card shown when the model is not confident (< 70%).
/// Includes an autocomplete search so the user can correct the food name.
class _ConfidenceWarningCard extends StatelessWidget {
  final double confidence;
  final List<String> classNames;
  final Future<void> Function(String) onCorrect;

  const _ConfidenceWarningCard({
    required this.confidence,
    required this.classNames,
    required this.onCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCA28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤔', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Not quite sure about this one!',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF5D4037)),
                    ),
                    Text(
                      'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF795548)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Autocomplete<String>(
            optionsBuilder: (v) {
              if (v.text.length < 2) return const Iterable<String>.empty();
              final q = v.text.toLowerCase();
              return classNames
                  .where((n) => n.toLowerCase().contains(q))
                  .take(6);
            },
            fieldViewBuilder: (ctx, ctrl, focusNode, onSubmitted) => TextField(
              controller: ctrl,
              focusNode: focusNode,
              onSubmitted: (text) {
                final t = text.trim();
                if (t.isNotEmpty) {
                  onCorrect(t);
                  FocusScope.of(ctx).unfocus();
                }
              },
              decoration: InputDecoration(
                hintText: 'Search correct food...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon:
                    const Icon(Icons.search, size: 18, color: Color(0xFF795548)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            onSelected: (selected) => onCorrect(selected),
            optionsViewBuilder: (_, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    itemBuilder: (_, i) {
                      final opt = options.elementAt(i);
                      return ListTile(
                        dense: true,
                        title: Text(opt,
                            style: const TextStyle(fontSize: 13)),
                        onTap: () => onSelected(opt),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
