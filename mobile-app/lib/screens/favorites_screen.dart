import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/meal_model.dart';
import '../providers/auth_provider.dart';
import '../providers/meal_provider.dart';
import '../services/meal_service.dart';
import '../theme/app_theme.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favorite Foods')),
      body: Consumer2<MealProvider, AuthProvider>(
        builder: (context, meals, auth, _) {
          final favorites = meals.favorites;

          if (favorites.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_border,
                      size: 72, color: AppColors.hintGreen),
                  const SizedBox(height: 16),
                  const Text('No favorites yet',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.hintGreen)),
                  const SizedBox(height: 8),
                  const Text('Heart a food on the results screen to save it here',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: AppColors.hintGreen)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: favorites.length,
            itemBuilder: (context, i) {
              final food = favorites[i];
              return _FavoriteCard(
                food: food,
                onAdd: () => _addToLog(context, food, auth, meals),
                onRemove: () {
                  final uid = auth.user?.uid;
                  if (uid != null) {
                    meals.removeFavorite(
                        food['label'] as String? ?? '', uid);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addToLog(
    BuildContext context,
    Map<String, dynamic> food,
    AuthProvider auth,
    MealProvider mealProvider,
  ) async {
    final user = auth.user;
    if (user == null) return;

    final n = food['nutrition'] as Map<String, dynamic>? ?? {};
    final meal = MealModel(
      id: const Uuid().v4(),
      userId: user.uid,
      foodName: food['display_name'] as String? ??
          food['label'] as String? ??
          'Unknown',
      imagePath: '',
      confidence: 1.0,
      nutrition: NutritionInfo(
        calories: (n['calories'] as num?)?.toDouble() ?? 0,
        protein: (n['protein'] as num?)?.toDouble() ?? 0,
        carbs: (n['carbs'] as num?)?.toDouble() ?? 0,
        fat: (n['fat'] as num?)?.toDouble() ?? 0,
        fiber: (n['fiber'] as num?)?.toDouble() ?? 0,
      ),
      timestamp: DateTime.now(),
    );

    await MealService().saveMeal(meal);
    mealProvider.loadMeals(user.uid);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${meal.foodName} added to today\'s log!')),
      );
    }
  }
}

class _FavoriteCard extends StatelessWidget {
  final Map<String, dynamic> food;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _FavoriteCard({
    required this.food,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = food['display_name'] as String? ??
        food['label'] as String? ??
        'Unknown';
    final n = food['nutrition'] as Map<String, dynamic>? ?? {};
    final cal = (n['calories'] as num?)?.toStringAsFixed(0) ?? '—';
    final protein = (n['protein'] as num?)?.toStringAsFixed(1) ?? '—';
    final carbs = (n['carbs'] as num?)?.toStringAsFixed(1) ?? '—';
    final fat = (n['fat'] as num?)?.toStringAsFixed(1) ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant, color: AppColors.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.primary)),
                const SizedBox(height: 4),
                Text('$cal kcal · P:${protein}g · C:${carbs}g · F:${fat}g',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.hintGreen)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: AppColors.primary),
            tooltip: 'Add to today',
            onPressed: onAdd,
          ),
          IconButton(
            icon: const Icon(Icons.favorite,
                color: AppColors.error),
            tooltip: 'Remove favorite',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
