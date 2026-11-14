import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/nutrition_provider.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // ── Step 1 state ────────────────────────────────────────────────────────────
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String _gender = 'male';
  String _activity = 'sedentary';
  double? _bmi;
  double? _bmr;
  double? _tdee;
  String? _bmiCategory;
  final _calorieGoalCtrl = TextEditingController();

  // ── Step 2 state ────────────────────────────────────────────────────────────
  final Set<String> _allergies = {};
  final Set<String> _dietRestrictions = {};
  final _healthNotesCtrl = TextEditingController();

  // ── Step 3 state ────────────────────────────────────────────────────────────
  String _mainGoal = 'Eat Healthier';
  int _waterGoal = 8;

  // ── Constants ────────────────────────────────────────────────────────────────
  static const _activityMultipliers = {
    'sedentary': 1.2,
    'light': 1.375,
    'moderate': 1.55,
    'active': 1.725,
    'very_active': 1.9,
  };
  static const _activityLabels = {
    'sedentary': 'Sedentary (little/no exercise)',
    'light': 'Lightly active (1–3 days/week)',
    'moderate': 'Moderately active (3–5 days)',
    'active': 'Very active (6–7 days)',
    'very_active': 'Extra active (twice/day)',
  };
  static const _allergyOptions = [
    'Gluten', 'Dairy', 'Nuts', 'Eggs', 'Shellfish', 'Soy', 'None',
  ];
  static const _dietOptions = [
    'Vegetarian', 'Vegan', 'Keto', 'Halal', 'Diabetic-Friendly', 'None',
  ];
  static const _goalOptions = [
    'Lose Weight', 'Maintain Weight', 'Gain Muscle', 'Eat Healthier',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _calorieGoalCtrl.dispose();
    _healthNotesCtrl.dispose();
    super.dispose();
  }

  // ── Calculations ─────────────────────────────────────────────────────────────

  void _calculate() {
    final h = double.tryParse(_heightCtrl.text);
    final w = double.tryParse(_weightCtrl.text);
    final a = int.tryParse(_ageCtrl.text);
    if (h == null || w == null || a == null || h <= 0 || w <= 0 || a <= 0) {
      return;
    }

    final bmi = w / ((h / 100) * (h / 100));
    final bmr = _gender == 'male'
        ? (10 * w) + (6.25 * h) - (5 * a) + 5
        : (10 * w) + (6.25 * h) - (5 * a) - 161;
    final multiplier = _activityMultipliers[_activity] ?? 1.2;
    final tdee = bmr * multiplier;

    String category;
    if (bmi < 18.5) {
      category = 'Underweight';
    } else if (bmi < 25) {
      category = 'Normal weight';
    } else if (bmi < 30) {
      category = 'Overweight';
    } else {
      category = 'Obese';
    }

    setState(() {
      _bmi = bmi;
      _bmr = bmr;
      _tdee = tdee;
      _bmiCategory = category;
      _calorieGoalCtrl.text = tdee.toStringAsFixed(0);
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────────────

  void _nextPage() {
    if (_currentPage == 0) {
      // Require calculated values before proceeding
      if (_tdee == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all fields and tap Calculate first.')),
        );
        return;
      }
    }
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // Compute goal-adjusted daily calories from TDEE + selected goal.
  double _adjustedCalories() {
    final tdee = _tdee ?? 2000.0;
    switch (_mainGoal) {
      case 'Lose Weight':     return (tdee - 500).clamp(1000.0, double.infinity);
      case 'Gain Muscle':     return tdee + 300;
      default:                return tdee; // Maintain Weight, Eat Healthier
    }
  }

  // Compute macros from adjusted calories and body weight.
  ({double protein, double carbs, double fat}) _computeMacros(double calories) {
    final w = double.tryParse(_weightCtrl.text) ?? 70.0;
    final double proteinPerKg;
    final double fatFraction;
    if (_mainGoal == 'Gain Muscle') {
      proteinPerKg = 2.2; fatFraction = 0.25;
    } else if (_mainGoal == 'Lose Weight') {
      proteinPerKg = 2.0; fatFraction = 0.25;
    } else {
      proteinPerKg = 1.6; fatFraction = 0.30;
    }
    final protein = w * proteinPerKg;
    final fat     = (calories * fatFraction) / 9;
    final carbs   = ((calories - protein * 4 - fat * 9) / 4).clamp(0.0, double.infinity);
    return (protein: protein, carbs: carbs, fat: fat);
  }

  Future<void> _finish() async {
    final uid           = FirebaseAuth.instance.currentUser?.uid;
    final dailyCalories = _adjustedCalories();
    final macros        = _computeMacros(dailyCalories);

    // Save to SharedPreferences immediately
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('daily_calorie_goal', dailyCalories);
    await prefs.setDouble('protein_goal',       macros.protein);
    await prefs.setDouble('carbs_goal',         macros.carbs);
    await prefs.setDouble('fat_goal',           macros.fat);
    await prefs.setString('diet_goal', _mainGoal.toLowerCase().replaceAll(' ', '_'));
    await prefs.setStringList('health_allergies', _allergies.toList());
    await prefs.setStringList('health_diet', _dietRestrictions.toList());
    await prefs.setString('health_notes', _healthNotesCtrl.text.trim());
    await prefs.setString('health_goal', _mainGoal);
    await prefs.setInt('water_goal', _waterGoal);
    await prefs.setBool('onboarding_complete', true);

    // Update NutritionProvider
    if (mounted) {
      final nutrition = context.read<NutritionProvider>();
      nutrition.setDailyGoal(dailyCalories, uid: uid);
      nutrition.setMacroGoals(
        protein: macros.protein,
        carbs:   macros.carbs,
        fat:     macros.fat,
        uid:     uid,
      );
    }

    // Background Firestore saves
    if (uid != null) {
      final db = FirebaseFirestore.instance;

      // Authoritative health_info document (read by NutritionProvider)
      db.collection('users').doc(uid).collection('health_info').doc('data').set({
        'bmr':            _bmr,
        'tdee':           _tdee,
        'daily_calories': dailyCalories,
        'daily_protein':  macros.protein,
        'daily_carbs':    macros.carbs,
        'daily_fat':      macros.fat,
        'bmi':            _bmi,
        'goal':           _mainGoal.toLowerCase().replaceAll(' ', '_'),
        'weight':         double.tryParse(_weightCtrl.text),
        'height':         double.tryParse(_heightCtrl.text),
        'age':            int.tryParse(_ageCtrl.text),
        'gender':         _gender,
        'activity_level': _activity,
        'updated_at':     FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((_) {});

      // Keep profile/goals in sync
      db.collection('users').doc(uid).collection('profile').doc('goals').set({
        'dailyCalorieGoal': dailyCalories,
        'proteinGoal':      macros.protein,
        'carbsGoal':        macros.carbs,
        'fatGoal':          macros.fat,
        'bmi':              _bmi,
        'bmr':              _bmr,
        'tdee':             _tdee,
        'gender':           _gender,
        'activity':         _activity,
        'healthGoal':       _mainGoal,
        'waterGoal':        _waterGoal,
      }, SetOptions(merge: true)).catchError((_) {});

      db.collection('users').doc(uid).collection('profile').doc('health_info').set({
        'allergies':        _allergies.toList(),
        'dietRestrictions': _dietRestrictions.toList(),
        'conditions':       [],
        'notes':            _healthNotesCtrl.text.trim(),
        'updatedAt':        FieldValue.serverTimestamp(),
      }).catchError((_) {});
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _currentPage
                            ? AppColors.primary
                            : AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(
                    'Step ${_currentPage + 1} of 3',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.hintGreen),
                  ),
                  const Spacer(),
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: _prevPage,
                      style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4)),
                      child: const Text('Back'),
                    ),
                ],
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _Step1(
                    ageCtrl: _ageCtrl,
                    weightCtrl: _weightCtrl,
                    heightCtrl: _heightCtrl,
                    gender: _gender,
                    activity: _activity,
                    bmi: _bmi,
                    bmr: _bmr,
                    tdee: _tdee,
                    bmiCategory: _bmiCategory,
                    calorieGoalCtrl: _calorieGoalCtrl,
                    activityLabels: _activityLabels,
                    onGenderChanged: (v) => setState(() => _gender = v),
                    onActivityChanged: (v) => setState(() => _activity = v),
                    onCalculate: _calculate,
                  ),
                  _Step2(
                    allergies: _allergies,
                    dietRestrictions: _dietRestrictions,
                    notesCtrl: _healthNotesCtrl,
                    allergyOptions: _allergyOptions,
                    dietOptions: _dietOptions,
                    onAllergyToggle: (v) => setState(() {
                      if (v == 'None') {
                        _allergies.clear();
                        _allergies.add('None');
                      } else {
                        _allergies.remove('None');
                        _allergies.contains(v)
                            ? _allergies.remove(v)
                            : _allergies.add(v);
                      }
                    }),
                    onDietToggle: (v) => setState(() {
                      if (v == 'None') {
                        _dietRestrictions.clear();
                        _dietRestrictions.add('None');
                      } else {
                        _dietRestrictions.remove('None');
                        _dietRestrictions.contains(v)
                            ? _dietRestrictions.remove(v)
                            : _dietRestrictions.add(v);
                      }
                    }),
                  ),
                  _Step3(
                    mainGoal: _mainGoal,
                    waterGoal: _waterGoal,
                    goalOptions: _goalOptions,
                    bmi: _bmi,
                    tdee: _tdee,
                    bmiCategory: _bmiCategory,
                    calorieGoal: double.tryParse(_calorieGoalCtrl.text),
                    allergies: _allergies,
                    dietRestrictions: _dietRestrictions,
                    onGoalChanged: (v) => setState(() => _mainGoal = v),
                    onWaterGoalChanged: (v) => setState(() => _waterGoal = v),
                  ),
                ],
              ),
            ),

            // CTA button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ElevatedButton(
                onPressed: _nextPage,
                child: Text(
                  _currentPage < 2 ? 'Continue' : 'Start Using NutriScan',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 1: Health Calculator ────────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  final TextEditingController ageCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController heightCtrl;
  final String gender;
  final String activity;
  final double? bmi;
  final double? bmr;
  final double? tdee;
  final String? bmiCategory;
  final TextEditingController calorieGoalCtrl;
  final Map<String, String> activityLabels;
  final void Function(String) onGenderChanged;
  final void Function(String) onActivityChanged;
  final VoidCallback onCalculate;

  const _Step1({
    required this.ageCtrl,
    required this.weightCtrl,
    required this.heightCtrl,
    required this.gender,
    required this.activity,
    required this.bmi,
    required this.bmr,
    required this.tdee,
    required this.bmiCategory,
    required this.calorieGoalCtrl,
    required this.activityLabels,
    required this.onGenderChanged,
    required this.onActivityChanged,
    required this.onCalculate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Health Calculator',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Let us personalise your nutrition plan.',
            style: TextStyle(fontSize: 14, color: AppColors.hintGreen),
          ),
          const SizedBox(height: 20),

          // Gender selector
          Row(
            children: [
              const Text('Gender',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              _GenderChip(
                label: 'Male',
                selected: gender == 'male',
                onTap: () => onGenderChanged('male'),
              ),
              const SizedBox(width: 8),
              _GenderChip(
                label: 'Female',
                selected: gender == 'female',
                onTap: () => onGenderChanged('female'),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ageCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    suffixText: 'yrs',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Weight',
                    suffixText: 'kg',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: heightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Height',
                    suffixText: 'cm',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Activity level
          DropdownButtonFormField<String>(
            value: activity,
            decoration: const InputDecoration(labelText: 'Activity Level'),
            items: activityLabels.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) { if (v != null) onActivityChanged(v); },
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: onCalculate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Calculate'),
          ),

          if (bmi != null) ...[
            const SizedBox(height: 16),
            _ResultsCard(
              bmi: bmi!,
              bmr: bmr!,
              tdee: tdee!,
              bmiCategory: bmiCategory!,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: calorieGoalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Daily Calorie Goal',
                helperText: 'Pre-filled with your TDEE — adjust if needed',
                suffixText: 'kcal',
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _GenderChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.lightGreen,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.primary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  final double bmi;
  final double bmr;
  final double tdee;
  final String bmiCategory;
  const _ResultsCard({
    required this.bmi,
    required this.bmr,
    required this.tdee,
    required this.bmiCategory,
  });

  Color get _bmiColor {
    if (bmi < 18.5) return Colors.blue;
    if (bmi < 25) return AppColors.primary;
    if (bmi < 30) return AppColors.orange;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ResultTile(
              label: 'BMI',
              value: bmi.toStringAsFixed(1),
              sub: bmiCategory,
              color: _bmiColor),
          _ResultTile(
              label: 'BMR',
              value: bmr.toStringAsFixed(0),
              sub: 'kcal/day'),
          _ResultTile(
              label: 'TDEE',
              value: tdee.toStringAsFixed(0),
              sub: 'kcal/day',
              color: AppColors.primary),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;
  const _ResultTile({
    required this.label,
    required this.value,
    required this.sub,
    this.color = AppColors.hintGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.hintGreen,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color)),
        Text(sub,
            style:
                const TextStyle(fontSize: 10, color: AppColors.hintGreen)),
      ],
    );
  }
}

// ─── Step 2: Allergies & Dietary Restrictions ─────────────────────────────────

class _Step2 extends StatelessWidget {
  final Set<String> allergies;
  final Set<String> dietRestrictions;
  final TextEditingController notesCtrl;
  final List<String> allergyOptions;
  final List<String> dietOptions;
  final void Function(String) onAllergyToggle;
  final void Function(String) onDietToggle;

  const _Step2({
    required this.allergies,
    required this.dietRestrictions,
    required this.notesCtrl,
    required this.allergyOptions,
    required this.dietOptions,
    required this.onAllergyToggle,
    required this.onDietToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Allergies & Diet',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Help us warn you about foods that may not suit you.',
            style: TextStyle(fontSize: 14, color: AppColors.hintGreen),
          ),
          const SizedBox(height: 20),

          _OnboardingSection(label: 'Allergies'),
          const SizedBox(height: 8),
          _ChipGroup(
            options: allergyOptions,
            selected: allergies,
            onToggle: onAllergyToggle,
          ),
          const SizedBox(height: 20),

          _OnboardingSection(label: 'Dietary Preferences'),
          const SizedBox(height: 8),
          _ChipGroup(
            options: dietOptions,
            selected: dietRestrictions,
            onToggle: onDietToggle,
          ),
          const SizedBox(height: 20),

          _OnboardingSection(label: 'Other Health Notes'),
          const SizedBox(height: 8),
          TextField(
            controller: notesCtrl,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Medications, health conditions, or special requirements...',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _OnboardingSection extends StatelessWidget {
  final String label;
  const _OnboardingSection({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.hintGreen,
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final void Function(String) onToggle;
  const _ChipGroup(
      {required this.options,
      required this.selected,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return FilterChip(
          label: Text(opt),
          selected: isSelected,
          selectedColor: AppColors.primary,
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.primary,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          backgroundColor: AppColors.lightGreen,
          side: BorderSide.none,
          onSelected: (_) => onToggle(opt),
        );
      }).toList(),
    );
  }
}

// ─── Step 3: Goals & Summary ──────────────────────────────────────────────────

class _Step3 extends StatelessWidget {
  final String mainGoal;
  final int waterGoal;
  final List<String> goalOptions;
  final double? bmi;
  final double? tdee;
  final String? bmiCategory;
  final double? calorieGoal;
  final Set<String> allergies;
  final Set<String> dietRestrictions;
  final void Function(String) onGoalChanged;
  final void Function(int) onWaterGoalChanged;

  const _Step3({
    required this.mainGoal,
    required this.waterGoal,
    required this.goalOptions,
    required this.bmi,
    required this.tdee,
    required this.bmiCategory,
    required this.calorieGoal,
    required this.allergies,
    required this.dietRestrictions,
    required this.onGoalChanged,
    required this.onWaterGoalChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your Goals',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Almost done! Set your primary goal.',
            style: TextStyle(fontSize: 14, color: AppColors.hintGreen),
          ),
          const SizedBox(height: 20),

          const _OnboardingSection(label: 'Main Goal'),
          const SizedBox(height: 10),
          ...goalOptions.map((goal) {
            final selected = mainGoal == goal;
            return GestureDetector(
              onTap: () => onGoalChanged(goal),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected
                          ? Colors.white
                          : AppColors.hintGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      goal,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 20),
          const _OnboardingSection(label: 'Daily Water Goal'),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                onPressed: waterGoal > 1
                    ? () => onWaterGoalChanged(waterGoal - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline,
                    color: AppColors.primary),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$waterGoal',
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary),
                    ),
                    const Text('glasses/day',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.hintGreen)),
                  ],
                ),
              ),
              IconButton(
                onPressed: waterGoal < 20
                    ? () => onWaterGoalChanged(waterGoal + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline,
                    color: AppColors.primary),
              ),
            ],
          ),

          const SizedBox(height: 20),
          // Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Setup Summary',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
                const SizedBox(height: 10),
                _SummaryRow(
                    icon: Icons.flag_outlined,
                    label: 'Goal',
                    value: mainGoal),
                if (calorieGoal != null)
                  _SummaryRow(
                      icon: Icons.local_fire_department_outlined,
                      label: 'Calorie target',
                      value:
                          '${calorieGoal!.toStringAsFixed(0)} kcal/day'),
                if (bmi != null)
                  _SummaryRow(
                      icon: Icons.monitor_weight_outlined,
                      label: 'BMI',
                      value:
                          '${bmi!.toStringAsFixed(1)} ($bmiCategory)'),
                _SummaryRow(
                    icon: Icons.water_drop_outlined,
                    label: 'Water goal',
                    value: '$waterGoal glasses/day'),
                if (allergies.isNotEmpty &&
                    !allergies.contains('None'))
                  _SummaryRow(
                      icon: Icons.warning_amber_outlined,
                      label: 'Allergies',
                      value: allergies.join(', ')),
                if (dietRestrictions.isNotEmpty &&
                    !dietRestrictions.contains('None'))
                  _SummaryRow(
                      icon: Icons.restaurant_menu_outlined,
                      label: 'Diet',
                      value: dietRestrictions.join(', ')),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.hintGreen),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.hintGreen,
                fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
