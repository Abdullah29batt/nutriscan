import 'package:flutter/material.dart';
import '../models/meal_model.dart';
import '../theme/app_theme.dart';

class NutritionCard extends StatelessWidget {
  final NutritionInfo nutrition;
  final double servingSize;

  const NutritionCard({
    super.key,
    required this.nutrition,
    this.servingSize = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart_rounded,
                    color: AppTheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Nutrition Info',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withAlpha(80),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'per ${servingSize.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _CaloriesBanner(calories: nutrition.calories),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _MacroTile(
                        label: 'Protein',
                        value: nutrition.protein,
                        unit: 'g',
                        color: const Color(0xFF42A5F5),
                        icon: Icons.fitness_center)),
                const SizedBox(width: 10),
                Expanded(
                    child: _MacroTile(
                        label: 'Carbs',
                        value: nutrition.carbs,
                        unit: 'g',
                        color: const Color(0xFFFFCA28),
                        icon: Icons.grain)),
                const SizedBox(width: 10),
                Expanded(
                    child: _MacroTile(
                        label: 'Fat',
                        value: nutrition.fat,
                        unit: 'g',
                        color: const Color(0xFFEF5350),
                        icon: Icons.water_drop)),
              ],
            ),
            if (nutrition.fiber > 0 || nutrition.sodium > 0) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (nutrition.fiber > 0)
                    Expanded(
                        child: _MicroRow(
                            label: 'Fiber',
                            value: '${nutrition.fiber.toStringAsFixed(1)}g')),
                  if (nutrition.sugar > 0)
                    Expanded(
                        child: _MicroRow(
                            label: 'Sugar',
                            value: '${nutrition.sugar.toStringAsFixed(1)}g')),
                  if (nutrition.sodium > 0)
                    Expanded(
                        child: _MicroRow(
                            label: 'Sodium',
                            value:
                                '${nutrition.sodium.toStringAsFixed(0)}mg')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CaloriesBanner extends StatelessWidget {
  final double calories;
  const _CaloriesBanner({required this.calories});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            calories.toStringAsFixed(0),
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1),
          ),
          const Text('kcal',
              style: TextStyle(fontSize: 14, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _MacroTile extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  final IconData icon;

  const _MacroTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            '${value.toStringAsFixed(1)}$unit',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: color),
          ),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _MicroRow extends StatelessWidget {
  final String label;
  final String value;
  const _MicroRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ',
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary)),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
      ],
    );
  }
}
