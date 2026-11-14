import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/meal_model.dart';
import '../providers/auth_provider.dart';
import '../providers/meal_provider.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatelessWidget {
  final bool embedded;
  const HistoryScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Meal History')),
      body: Consumer2<MealProvider, AuthProvider>(
        builder: (context, mealProvider, authProvider, _) {
          if (mealProvider.isAnalyzing) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final meals = mealProvider.meals;

          if (meals.isEmpty) {
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                final uid = authProvider.user?.uid;
                if (uid != null) await mealProvider.loadMeals(uid);
              },
              child: ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history,
                              size: 72,
                              color: AppColors.lightGreen),
                          const SizedBox(height: 16),
                          const Text('No meal history yet',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.hintGreen)),
                          const SizedBox(height: 8),
                          const Text(
                              'Start scanning food to build your history',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.hintGreen)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final grouped = _groupByDate(meals);
          final dates = grouped.keys.toList();

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              final uid = authProvider.user?.uid;
              if (uid != null) await mealProvider.loadMeals(uid);
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100, top: 8),
              itemCount: dates.length,
              itemBuilder: (context, i) {
                final date = dates[i];
                final dayMeals = grouped[date]!;
                return _DateGroup(
                  date: date,
                  meals: dayMeals,
                  onDelete: (meal) {
                    final uid = authProvider.user?.uid;
                    if (uid != null) {
                      mealProvider.deleteMeal(uid, meal.id);
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Map<String, List<MealModel>> _groupByDate(List<MealModel> meals) {
    final map = <String, List<MealModel>>{};
    for (final meal in meals) {
      final key = DateFormat('yyyy-MM-dd').format(meal.timestamp);
      map.putIfAbsent(key, () => []).add(meal);
    }
    return map;
  }
}

class _DateGroup extends StatelessWidget {
  final String date;
  final List<MealModel> meals;
  final void Function(MealModel) onDelete;

  const _DateGroup({
    required this.date,
    required this.meals,
    required this.onDelete,
  });

  String _formatDate(String dateStr) {
    final d = DateTime.parse(dateStr);
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    if (DateFormat('yyyy-MM-dd').format(today) == dateStr) return 'Today';
    if (DateFormat('yyyy-MM-dd').format(yesterday) == dateStr) {
      return 'Yesterday';
    }
    return DateFormat('EEEE, MMM d').format(d);
  }

  double get _totalCalories =>
      meals.fold(0.0, (sum, m) => sum + m.nutrition.calories);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                _formatDate(date),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_totalCalories.toStringAsFixed(0)} kcal total',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        ...meals.map((meal) => Dismissible(
              key: Key(meal.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                margin: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_outline,
                    color: Colors.white, size: 26),
              ),
              onDismissed: (_) => onDelete(meal),
              child: _MealCard(meal: meal),
            )),
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  final MealModel meal;
  const _MealCard({required this.meal});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: meal.imagePath.isNotEmpty
                  ? Image.file(
                      File(meal.imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.cardGreen,
                        child: const Icon(Icons.fastfood,
                            color: AppColors.primary),
                      ),
                    )
                  : Container(
                      color: AppColors.cardGreen,
                      child: const Icon(Icons.fastfood,
                          color: AppColors.primary),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.foodName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('h:mm a').format(meal.timestamp),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.hintGreen),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    _MacroBadge(
                        label:
                            '${meal.nutrition.calories.toStringAsFixed(0)} kcal',
                        color: AppColors.primary),
                    _MacroBadge(
                        label:
                            'P: ${meal.nutrition.protein.toStringAsFixed(1)}g',
                        color: Colors.blue),
                    _MacroBadge(
                        label:
                            'C: ${meal.nutrition.carbs.toStringAsFixed(1)}g',
                        color: Colors.amber.shade700),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _MacroBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
