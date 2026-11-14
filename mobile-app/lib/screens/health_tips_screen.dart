import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/meal_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class HealthTipsScreen extends StatefulWidget {
  const HealthTipsScreen({super.key});

  @override
  State<HealthTipsScreen> createState() => _HealthTipsScreenState();
}

class _HealthTipsScreenState extends State<HealthTipsScreen> {
  List<String> _tips = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchTips();
  }

  Future<void> _fetchTips() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final mealProvider = context.read<MealProvider>();
      final today = DateTime.now();
      final todayMeals = mealProvider.meals
          .where((m) =>
              m.timestamp.year == today.year &&
              m.timestamp.month == today.month &&
              m.timestamp.day == today.day)
          .map((m) => m.foodName)
          .toList();

      if (todayMeals.isEmpty) {
        setState(() {
          _tips = [];
          _loading = false;
        });
        return;
      }

      final tips = await ApiService().getHealthTips(todayMeals);
      setState(() {
        _tips = tips;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load tips. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Tips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchTips,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: const TextStyle(color: AppColors.hintGreen),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _fetchTips, child: const Text('Retry')),
          ],
        ),
      );
    }

    final mealProvider = context.watch<MealProvider>();
    final today = DateTime.now();
    final hasTodayMeals = mealProvider.meals.any((m) =>
        m.timestamp.year == today.year &&
        m.timestamp.month == today.month &&
        m.timestamp.day == today.day);

    if (!hasTodayMeals) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Log some meals first to get personalized tips',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.hintGreen, fontSize: 15),
          ),
        ),
      );
    }

    if (_tips.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No tips available',
                style: TextStyle(color: AppColors.hintGreen)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _fetchTips,
                child: const Text('Get Tips')),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _tips.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _tips[i],
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      height: 1.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
