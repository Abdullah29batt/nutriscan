import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/meal_model.dart';
import '../theme/app_theme.dart';

class MealHistoryItem extends StatelessWidget {
  final MealModel meal;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const MealHistoryItem({
    super.key,
    required this.meal,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _FoodImage(imagePath: meal.imagePath),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.foodName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM d, yyyy · h:mm a')
                          .format(meal.timestamp),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _Badge(
                            label:
                                '${meal.nutrition.calories.toStringAsFixed(0)} kcal',
                            color: AppTheme.primary),
                        const SizedBox(width: 6),
                        _Badge(
                            label:
                                'P ${meal.nutrition.protein.toStringAsFixed(1)}g',
                            color: const Color(0xFF42A5F5)),
                        const SizedBox(width: 6),
                        _Badge(
                            label:
                                'C ${meal.nutrition.carbs.toStringAsFixed(1)}g',
                            color: const Color(0xFFFFCA28)),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppTheme.textSecondary, size: 20),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodImage extends StatelessWidget {
  final String imagePath;
  const _FoodImage({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final isLocal = imagePath.isNotEmpty && !imagePath.startsWith('http');
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: isLocal
          ? Image.file(
              File(imagePath),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        width: 72,
        height: 72,
        color: AppTheme.surface,
        child: const Icon(Icons.fastfood,
            color: AppTheme.primaryLight, size: 32),
      );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
