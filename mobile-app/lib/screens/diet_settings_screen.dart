import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/nutrition_provider.dart';
import '../theme/app_theme.dart';

class DietSettingsScreen extends StatefulWidget {
  const DietSettingsScreen({super.key});

  @override
  State<DietSettingsScreen> createState() => _DietSettingsScreenState();
}

class _DietSettingsScreenState extends State<DietSettingsScreen> {
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();

  String _gender = 'male';
  String _activityLevel = 'sedentary';
  String _dietGoal = 'maintain';
  String _dietType = 'normal';
  double _calculatedCalories = 2000;

  static const _activityFactors = {
    'sedentary': 1.2,
    'light': 1.375,
    'moderate': 1.55,
    'active': 1.725,
    'extra': 1.9,
  };

  static const _goalAdjustments = {
    'lose': -500.0,
    'maintain': 0.0,
    'gain': 300.0,
  };

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ageController.text = (prefs.getInt('age') ?? 25).toString();
      _weightController.text =
          (prefs.getDouble('weight') ?? 70.0).toString();
      _heightController.text =
          (prefs.getDouble('height') ?? 170.0).toString();
      _gender = prefs.getString('gender') ?? 'male';
      _activityLevel = prefs.getString('activity_level') ?? 'sedentary';
      _dietGoal = prefs.getString('diet_goal_setting') ?? 'maintain';
      _dietType = prefs.getString('diet_type_setting') ?? 'normal';
    });
    _recalculate();
  }

  void _recalculate() {
    final age = int.tryParse(_ageController.text) ?? 25;
    final weight = double.tryParse(_weightController.text) ?? 70;
    final height = double.tryParse(_heightController.text) ?? 170;

    double bmr;
    if (_gender == 'male') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }

    final factor = _activityFactors[_activityLevel] ?? 1.2;
    final adjustment = _goalAdjustments[_dietGoal] ?? 0.0;

    setState(() {
      _calculatedCalories = (bmr * factor + adjustment).clamp(1200, 5000);
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('age', int.tryParse(_ageController.text) ?? 25);
    await prefs.setDouble(
        'weight', double.tryParse(_weightController.text) ?? 70);
    await prefs.setDouble(
        'height', double.tryParse(_heightController.text) ?? 170);
    await prefs.setString('gender', _gender);
    await prefs.setString('activity_level', _activityLevel);
    await prefs.setString('diet_goal_setting', _dietGoal);
    await prefs.setString('diet_type_setting', _dietType);

    if (!mounted) return;
    context.read<NutritionProvider>()
      ..setDailyGoal(_calculatedCalories)
      ..setDietInfo(_dietType, _dietGoal);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved!')));
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diet Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Body Profile'),
            _RowField(label: 'Age', controller: _ageController,
                onChanged: (_) => _recalculate()),
            const SizedBox(height: 12),
            _RowField(
                label: 'Weight',
                controller: _weightController,
                suffix: 'kg',
                onChanged: (_) => _recalculate()),
            const SizedBox(height: 12),
            _RowField(
                label: 'Height',
                controller: _heightController,
                suffix: 'cm',
                onChanged: (_) => _recalculate()),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Gender',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                _ToggleBtn(
                    label: 'Male',
                    selected: _gender == 'male',
                    onTap: () {
                      setState(() => _gender = 'male');
                      _recalculate();
                    }),
                const SizedBox(width: 8),
                _ToggleBtn(
                    label: 'Female',
                    selected: _gender == 'female',
                    onTap: () {
                      setState(() => _gender = 'female');
                      _recalculate();
                    }),
              ],
            ),
            _sectionTitle('Activity Level'),
            ...[
              ('sedentary', 'Sedentary'),
              ('light', 'Lightly Active'),
              ('moderate', 'Moderately Active'),
              ('active', 'Very Active'),
              ('extra', 'Extra Active'),
            ].map((e) => RadioListTile<String>(
                  title: Text(e.$2,
                      style:
                          const TextStyle(color: AppColors.primary)),
                  value: e.$1,
                  groupValue: _activityLevel,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _activityLevel = v!);
                    _recalculate();
                  },
                )),
            _sectionTitle('Diet Goal'),
            ...[
              ('lose', 'Lose Weight'),
              ('maintain', 'Maintain Weight'),
              ('gain', 'Gain Muscle'),
            ].map((e) => RadioListTile<String>(
                  title: Text(e.$2,
                      style:
                          const TextStyle(color: AppColors.primary)),
                  value: e.$1,
                  groupValue: _dietGoal,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _dietGoal = v!);
                    _recalculate();
                  },
                )),
            _sectionTitle('Diet Type'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'normal',
                'keto',
                'halal',
                'vegetarian',
                'high_protein',
                'deficit',
              ].map((t) {
                final label = t
                    .replaceAll('_', ' ')
                    .split(' ')
                    .map((w) =>
                        w[0].toUpperCase() + w.substring(1))
                    .join(' ');
                return ChoiceChip(
                  label: Text(label),
                  selected: _dietType == t,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                      color: _dietType == t
                          ? Colors.white
                          : AppColors.primary),
                  onSelected: (_) =>
                      setState(() => _dietType = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text('Your Daily Goal',
                      style: TextStyle(
                          color: AppColors.hintGreen, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    '${_calculatedCalories.toStringAsFixed(0)} kcal',
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: _save, child: const Text('Save')),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _RowField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? suffix;
  final ValueChanged<String> onChanged;

  const _RowField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: onChanged,
            decoration: InputDecoration(suffixText: suffix),
          ),
        ),
      ],
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.lightGreen,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}
