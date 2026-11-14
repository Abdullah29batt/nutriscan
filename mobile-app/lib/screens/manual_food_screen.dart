import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/meal_model.dart';
import '../providers/auth_provider.dart';
import '../providers/meal_provider.dart';
import '../services/gemini_service.dart';
import '../services/meal_service.dart';
import '../theme/app_theme.dart';

class ManualFoodScreen extends StatefulWidget {
  const ManualFoodScreen({super.key});

  @override
  State<ManualFoodScreen> createState() => _ManualFoodScreenState();
}

class _ManualFoodScreenState extends State<ManualFoodScreen> {
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _nutrition;
  double _servingSize = 100;
  bool _searching = false;
  bool _adding = false;
  String? _error;

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _error = null;
      _nutrition = null;
    });

    final result = await GeminiService.searchFoodNutrition(query);

    if (!mounted) return;
    if (result != null) {
      setState(() {
        _nutrition = result;
        _servingSize = 100;
        _searching = false;
      });
    } else {
      setState(() {
        _error = 'Could not find nutrition data for "$query". Try a different name.';
        _searching = false;
      });
    }
  }

  Future<void> _addToLog() async {
    if (_nutrition == null) return;
    setState(() => _adding = true);

    final user = context.read<AuthProvider>().user;
    if (user == null) {
      setState(() => _adding = false);
      return;
    }

    final factor = _servingSize / 100;
    final n = _nutrition!;
    final meal = MealModel(
      id: const Uuid().v4(),
      userId: user.uid,
      foodName: n['display_name'] as String? ??
          _searchCtrl.text.trim(),
      imagePath: '',
      confidence: 1.0,
      nutrition: NutritionInfo(
        calories: ((n['calories'] as num?)?.toDouble() ?? 0) * factor,
        protein: ((n['protein'] as num?)?.toDouble() ?? 0) * factor,
        carbs: ((n['carbs'] as num?)?.toDouble() ?? 0) * factor,
        fat: ((n['fat'] as num?)?.toDouble() ?? 0) * factor,
        fiber: ((n['fiber'] as num?)?.toDouble() ?? 0) * factor,
      ),
      timestamp: DateTime.now(),
      servingSize: _servingSize,
    );

    await MealService().saveMeal(meal);

    if (!mounted) return;
    context.read<MealProvider>().loadMeals(user.uid);

    setState(() => _adding = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${meal.foodName} added to today\'s log!')),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _nutrition;
    final factor = _servingSize / 100;

    return Scaffold(
      appBar: AppBar(title: const Text('Manual Food Entry')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Search ──────────────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search food (e.g. "grilled chicken")',
                    prefixIcon: Icon(Icons.search, color: AppColors.hintGreen),
                  ),
                  onSubmitted: (_) => _search(),
                  textInputAction: TextInputAction.search,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _searching ? null : _search,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(64, 54)),
                child: _searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.search),
              ),
            ]),


            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],

            // ── Results ─────────────────────────────────────────────────────
            if (n != null) ...[
              const SizedBox(height: 24),
              Text(
                n['display_name'] as String? ?? _searchCtrl.text,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              ),
              const SizedBox(height: 4),
              const Text('Per 100 g (slide to adjust serving)',
                  style: TextStyle(fontSize: 13, color: AppColors.hintGreen)),
              const SizedBox(height: 16),

              // Serving slider
              Row(children: [
                const Text('Serving',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                        fontSize: 13)),
                Expanded(
                  child: Slider(
                    value: _servingSize,
                    min: 10,
                    max: 500,
                    divisions: 98,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.lightGreen,
                    onChanged: (v) => setState(() => _servingSize = v),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text('${_servingSize.toStringAsFixed(0)}g',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          fontSize: 13)),
                ),
              ]),

              const SizedBox(height: 12),

              // Nutrition grid
              _NutritionGrid(
                calories:
                    ((n['calories'] as num?)?.toDouble() ?? 0) * factor,
                protein:
                    ((n['protein'] as num?)?.toDouble() ?? 0) * factor,
                carbs: ((n['carbs'] as num?)?.toDouble() ?? 0) * factor,
                fat: ((n['fat'] as num?)?.toDouble() ?? 0) * factor,
                fiber:
                    ((n['fiber'] as num?)?.toDouble() ?? 0) * factor,
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _adding ? null : _addToLog,
                icon: _adding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add),
                label: const Text('Add to Today\'s Log'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NutritionGrid extends StatelessWidget {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  const _NutritionGrid(
      {required this.calories,
      required this.protein,
      required this.carbs,
      required this.fat,
      required this.fiber});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: AppColors.cardGreen,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: AppColors.primary,
              child: Column(
                children: [
                  const Text('Calories',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(calories.toStringAsFixed(0),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800)),
                  const Text('kcal',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
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

class _MacroTile extends StatelessWidget {
  final String label;
  final double value;
  const _MacroTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${value.toStringAsFixed(1)}g',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(height: 2),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.hintGreen)),
      ],
    );
  }
}
