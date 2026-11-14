import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/nutrition_provider.dart';
import '../theme/app_theme.dart';

class HealthCalculatorScreen extends StatefulWidget {
  const HealthCalculatorScreen({super.key});

  @override
  State<HealthCalculatorScreen> createState() => _HealthCalculatorScreenState();
}

class _HealthCalculatorScreenState extends State<HealthCalculatorScreen> {
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _ageCtrl    = TextEditingController();

  String _gender   = 'male';
  String _activity = 'sedentary';
  String _goal     = 'maintain';

  double? _bmi;
  double? _bmr;
  double? _tdee;
  double? _dailyCalories;
  double? _protein;
  double? _carbs;
  double? _fat;
  String? _bmiCategory;
  bool _saving = false;

  static const _activityMultipliers = {
    'sedentary':         1.2,
    'lightly_active':    1.375,
    'moderately_active': 1.55,
    'very_active':       1.725,
    'extra_active':      1.9,
  };

  static const _activityLabels = {
    'sedentary':         'Sedentary (little/no exercise)',
    'lightly_active':    'Lightly Active (1–3 days/week)',
    'moderately_active': 'Moderately Active (3–5 days)',
    'very_active':       'Very Active (6–7 days)',
    'extra_active':      'Extra Active (twice/day)',
  };

  static const _goalOptions = {
    'lose_weight':  'Lose Weight  (−500 kcal/day)',
    'lose_fast':    'Lose Weight Fast  (−750 kcal/day)',
    'maintain':     'Maintain Weight',
    'gain_muscle':  'Gain Muscle  (+300 kcal/day)',
    'gain_weight':  'Gain Weight  (+500 kcal/day)',
  };

  static const _goalAdjust = {
    'lose_weight':  -500.0,
    'lose_fast':    -750.0,
    'maintain':        0.0,
    'gain_muscle':   300.0,
    'gain_weight':   500.0,
  };

  void _calculate() {
    final h = double.tryParse(_heightCtrl.text);
    final w = double.tryParse(_weightCtrl.text);
    final a = int.tryParse(_ageCtrl.text);
    if (h == null || w == null || a == null || h <= 0 || w <= 0 || a <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields correctly.')),
      );
      return;
    }

    // BMI
    final bmi = w / ((h / 100) * (h / 100));

    // BMR — Mifflin-St Jeor
    final bmr = _gender == 'male'
        ? (10 * w) + (6.25 * h) - (5 * a) + 5
        : (10 * w) + (6.25 * h) - (5 * a) - 161;

    // TDEE
    final tdee = bmr * (_activityMultipliers[_activity] ?? 1.2);

    // Goal-adjusted daily calories
    final dailyCalories =
        (tdee + (_goalAdjust[_goal] ?? 0.0)).clamp(1000.0, double.infinity);

    // BMI category
    final String cat;
    if (bmi < 18.5) {
      cat = 'Underweight';
    } else if (bmi < 25) {
      cat = 'Normal weight';
    } else if (bmi < 30) {
      cat = 'Overweight';
    } else {
      cat = 'Obese';
    }

    // Macros
    final double proteinPerKg;
    final double fatFraction;
    if (_goal == 'gain_muscle') {
      proteinPerKg = 2.2; fatFraction = 0.25;
    } else if (_goal == 'lose_weight' || _goal == 'lose_fast') {
      proteinPerKg = 2.0; fatFraction = 0.25;
    } else {
      proteinPerKg = 1.6; fatFraction = 0.30;
    }
    final protein = w * proteinPerKg;
    final fat     = (dailyCalories * fatFraction) / 9;
    final carbs   = ((dailyCalories - protein * 4 - fat * 9) / 4)
        .clamp(0.0, double.infinity);

    setState(() {
      _bmi          = bmi;
      _bmr          = bmr;
      _tdee         = tdee;
      _dailyCalories = dailyCalories;
      _protein      = protein;
      _carbs        = carbs;
      _fat          = fat;
      _bmiCategory  = cat;
    });
  }

  Future<void> _saveAndApply() async {
    if (_dailyCalories == null) return;
    setState(() => _saving = true);

    final uid       = FirebaseAuth.instance.currentUser?.uid;
    final nutrition = context.read<NutritionProvider>();

    nutrition.setDailyGoal(_dailyCalories!, uid: uid);
    nutrition.setMacroGoals(
      protein: _protein!,
      carbs:   _carbs!,
      fat:     _fat!,
      uid:     uid,
    );

    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('health_info')
            .doc('data')
            .set({
          'bmr':            _bmr,
          'tdee':           _tdee,
          'daily_calories': _dailyCalories,
          'daily_protein':  _protein,
          'daily_carbs':    _carbs,
          'daily_fat':      _fat,
          'bmi':            _bmi,
          'goal':           _goal,
          'weight':         double.tryParse(_weightCtrl.text),
          'height':         double.tryParse(_heightCtrl.text),
          'age':            int.tryParse(_ageCtrl.text),
          'gender':         _gender,
          'activity_level': _activity,
          'updated_at':     FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await nutrition.saveGoalsToFirestore(uid);
      } catch (e) {
        debugPrint('Save health info failed: $e');
      }
    }

    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Daily goal set to ${_dailyCalories!.toStringAsFixed(0)} kcal!'),
        ),
      );
    }
  }

  Color _bmiColor() {
    if (_bmi == null)  return AppColors.primary;
    if (_bmi! < 18.5)  return Colors.blue;
    if (_bmi! < 25)    return AppColors.accent;
    if (_bmi! < 30)    return AppColors.orange;
    return AppColors.error;
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Calculator')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Inputs ──────────────────────────────────────────────────────
            _SectionHeader('Your Details'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _Field(ctrl: _heightCtrl, label: 'Height', suffix: 'cm', hint: '170'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(ctrl: _weightCtrl, label: 'Weight', suffix: 'kg', hint: '70'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(ctrl: _ageCtrl, label: 'Age', suffix: 'yr', hint: '25'),
              ),
            ]),
            const SizedBox(height: 16),

            // Gender
            Row(children: [
              Expanded(
                child: _RadioCard(
                  label: 'Male ♂',
                  selected: _gender == 'male',
                  onTap: () => setState(() => _gender = 'male'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RadioCard(
                  label: 'Female ♀',
                  selected: _gender == 'female',
                  onTap: () => setState(() => _gender = 'female'),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Activity Level
            _SectionHeader('Activity Level'),
            const SizedBox(height: 8),
            ..._activityLabels.entries.map((e) => RadioListTile<String>(
                  value:      e.key,
                  groupValue: _activity,
                  onChanged:  (v) => setState(() => _activity = v!),
                  title: Text(e.value,
                      style: const TextStyle(fontSize: 13, color: AppColors.primary)),
                  activeColor:     AppColors.primary,
                  contentPadding:  EdgeInsets.zero,
                  dense:           true,
                )),
            const SizedBox(height: 16),

            // Weight Goal
            _SectionHeader('Weight Goal'),
            const SizedBox(height: 8),
            ..._goalOptions.entries.map((e) => RadioListTile<String>(
                  value:      e.key,
                  groupValue: _goal,
                  onChanged:  (v) => setState(() {
                    _goal = v!;
                    if (_tdee != null) _calculate();
                  }),
                  title: Text(e.value,
                      style: const TextStyle(fontSize: 13, color: AppColors.primary)),
                  activeColor:    AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  dense:          true,
                )),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _calculate,
              child: const Text('Calculate'),
            ),

            // ── Results ─────────────────────────────────────────────────────
            if (_bmi != null) ...[
              const SizedBox(height: 24),
              _SectionHeader('Results'),
              const SizedBox(height: 12),

              _ResultCard(
                label:    'BMI',
                value:    _bmi!.toStringAsFixed(1),
                subtitle: _bmiCategory!,
                color:    _bmiColor(),
              ),
              const SizedBox(height: 10),
              _ResultCard(
                label:    'BMR (Basal Metabolic Rate)',
                value:    '${_bmr!.toStringAsFixed(0)} kcal',
                subtitle: 'Calories burned at rest',
                color:    Colors.blue,
              ),
              const SizedBox(height: 10),
              _ResultCard(
                label:    'TDEE (Maintenance)',
                value:    '${_tdee!.toStringAsFixed(0)} kcal',
                subtitle: 'Total daily energy expenditure',
                color:    AppColors.accent,
              ),
              const SizedBox(height: 10),
              _ResultCard(
                label:    'Daily Calorie Target',
                value:    '${_dailyCalories!.toStringAsFixed(0)} kcal',
                subtitle: 'Adjusted for your ${_goalOptions[_goal]?.split('  ').first ?? 'goal'}',
                color:    AppColors.primary,
              ),
              const SizedBox(height: 14),

              // Macro row
              Row(children: [
                Expanded(child: _MacroCard(label: 'Protein', value: '${_protein!.toStringAsFixed(0)}g', color: Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _MacroCard(label: 'Carbs',   value: '${_carbs!.toStringAsFixed(0)}g',   color: Colors.amber.shade700)),
                const SizedBox(width: 8),
                Expanded(child: _MacroCard(label: 'Fat',     value: '${_fat!.toStringAsFixed(0)}g',     color: Colors.red)),
              ]),

              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saving || _dailyCalories == null ? null : _saveAndApply,
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Save & Set as Calorie Goal'),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary));
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String suffix;
  final String hint;
  const _Field({required this.ctrl, required this.label, required this.suffix, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix, hintText: hint),
    );
  }
}

class _RadioCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RadioCard({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.lightGreen,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.hintGreen),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  const _ResultCard(
      {required this.label, required this.value, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13, color: color, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 11, color: AppColors.hintGreen)),
              ],
            ),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _MacroCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MacroCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.hintGreen)),
        ],
      ),
    );
  }
}
