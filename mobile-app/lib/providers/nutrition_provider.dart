import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_model.dart';

class NutritionProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Goals ──────────────────────────────────────────────────────────────────
  double _dailyCalorieGoal = 2000;
  double _proteinGoal = 150;
  double _carbsGoal = 250;
  double _fatGoal = 70;

  double get dailyCalorieGoal => _dailyCalorieGoal;
  double get proteinGoal => _proteinGoal;
  double get carbsGoal => _carbsGoal;
  double get fatGoal => _fatGoal;

  // ── Water ──────────────────────────────────────────────────────────────────
  int _waterIntake = 0;
  int _waterGoal = 8;
  int get waterIntake => _waterIntake;
  int get waterGoal => _waterGoal;

  // ── Streak ─────────────────────────────────────────────────────────────────
  int _streakDays = 0;
  int get streakDays => _streakDays;

  // ── Weight ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _weightHistory = [];
  List<Map<String, dynamic>> get weightHistory =>
      List.unmodifiable(_weightHistory);

  // ── Diary (meal-type buckets) ─────────────────────────────────────────────
  Map<String, List<MealModel>> _mealsByType = {
    'breakfast': [],
    'lunch': [],
    'dinner': [],
    'snack': [],
  };
  Map<String, List<MealModel>> get mealsByType => _mealsByType;

  // ── Diet settings ──────────────────────────────────────────────────────────
  String _dietType = 'normal';
  String _dietGoal = 'maintain';
  String get dietType => _dietType;
  String get dietGoal => _dietGoal;

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  /// Call after login. Loads from local immediately, then refreshes from
  /// Firestore in the background so the UI is never blocked waiting for network.
  Future<void> loadFromFirestore(String uid) async {
    // Serve from local cache first — instant and works offline
    await _loadFromPrefs();
    notifyListeners();

    // Background refresh from Firestore
    _refreshGoalsFromFirestore(uid);
    _loadTodayWater(uid).then((_) => notifyListeners()).catchError((_) {});
    _loadStreak(uid).then((_) => notifyListeners()).catchError((_) {});
  }

  Future<void> _refreshGoalsFromFirestore(String uid) async {
    try {
      // health_info/data is the authoritative source for computed calorie/macro goals.
      bool healthInfoFound = false;
      try {
        final healthDoc = await _db
            .collection('users')
            .doc(uid)
            .collection('health_info')
            .doc('data')
            .get();
        if (healthDoc.exists) {
          final d = healthDoc.data()!;
          _dailyCalorieGoal =
              (d['daily_calories'] as num?)?.toDouble() ?? _dailyCalorieGoal;
          _proteinGoal = (d['daily_protein'] as num?)?.toDouble() ?? _proteinGoal;
          _carbsGoal   = (d['daily_carbs']   as num?)?.toDouble() ?? _carbsGoal;
          _fatGoal     = (d['daily_fat']     as num?)?.toDouble() ?? _fatGoal;
          healthInfoFound = true;
        }
      } catch (_) {}

      // Fall back to profile/goals for calorie/macros if health_info absent,
      // and always read diet type/goal from there.
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('goals')
          .get();
      if (doc.exists) {
        final d = doc.data()!;
        if (!healthInfoFound) {
          _dailyCalorieGoal =
              (d['dailyCalorieGoal'] as num?)?.toDouble() ?? _dailyCalorieGoal;
          _proteinGoal = (d['proteinGoal'] as num?)?.toDouble() ?? _proteinGoal;
          _carbsGoal   = (d['carbsGoal']   as num?)?.toDouble() ?? _carbsGoal;
          _fatGoal     = (d['fatGoal']     as num?)?.toDouble() ?? _fatGoal;
        }
        _dietType = d['dietType'] as String? ?? _dietType;
        _dietGoal = d['dietGoal'] as String? ?? _dietGoal;
      }

      await _saveGoalsToPrefs();
      notifyListeners();
    } catch (e) {
      debugPrint('Firestore goals refresh failed: $e');
    }
  }

  Future<void> _loadTodayWater(String uid) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('water')
          .doc(today)
          .get();
      _waterIntake = doc.exists
          ? ((doc.data()!['glasses'] as num?)?.toInt() ?? 0)
          : 0;
      // Cache with today's date for offline day-rollover detection
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('water_intake', _waterIntake);
      await prefs.setString('water_date', today);
    } catch (_) {}
  }

  Future<void> _loadStreak(String uid) async {
    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('stats')
          .doc('streak')
          .get();
      _streakDays = doc.exists
          ? ((doc.data()!['streak'] as num?)?.toInt() ?? 0)
          : 0;
    } catch (_) {}
  }

  // ── Save goals to Firestore ────────────────────────────────────────────────

  Future<void> saveGoalsToFirestore(String uid) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('goals')
          .set({
        'dailyCalorieGoal': _dailyCalorieGoal,
        'proteinGoal': _proteinGoal,
        'carbsGoal': _carbsGoal,
        'fatGoal': _fatGoal,
        'dietType': _dietType,
        'dietGoal': _dietGoal,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore goals save failed: $e');
    }
  }

  // ── Setters ────────────────────────────────────────────────────────────────

  void setDailyGoal(double goal, {String? uid}) {
    _dailyCalorieGoal = goal;
    notifyListeners();
    _saveToPrefs();
    if (uid != null) saveGoalsToFirestore(uid);
  }

  void setMacroGoals({
    required double protein,
    required double carbs,
    required double fat,
    String? uid,
  }) {
    _proteinGoal = protein;
    _carbsGoal = carbs;
    _fatGoal = fat;
    notifyListeners();
    _saveToPrefs();
    if (uid != null) saveGoalsToFirestore(uid);
  }

  void setDietInfo(String type, String goal) {
    _dietType = type;
    _dietGoal = goal;
    notifyListeners();
    _saveToPrefs();
  }

  // ── Water ──────────────────────────────────────────────────────────────────

  void addWater({String? uid}) {
    if (_waterIntake >= 20) return;
    _waterIntake++;
    notifyListeners();
    _saveWater(uid);
  }

  void removeWater({String? uid}) {
    if (_waterIntake <= 0) return;
    _waterIntake--;
    notifyListeners();
    _saveWater(uid);
  }

  Future<void> _saveWater(String? uid) async {
    // Write locally immediately with today's date for day-rollover detection
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('water_intake', _waterIntake);
    await prefs.setString('water_date', today);
    // Background Firestore sync
    if (uid == null) return;
    _db
        .collection('users')
        .doc(uid)
        .collection('water')
        .doc(today)
        .set({'glasses': _waterIntake, 'date': today}).catchError(
            (e) => debugPrint('Water Firestore save failed: $e'));
  }

  // ── Streak ─────────────────────────────────────────────────────────────────

  void setStreak(int days) {
    _streakDays = days;
    notifyListeners();
  }

  // ── Weight ─────────────────────────────────────────────────────────────────

  void logWeight(double weight) {
    _weightHistory.add({
      'date': DateTime.now().toIso8601String(),
      'weight': weight,
    });
    if (_weightHistory.length > 30) {
      _weightHistory = _weightHistory.sublist(_weightHistory.length - 30);
    }
    notifyListeners();
    _saveToPrefs();
  }

  // ── Diary meal-type buckets ────────────────────────────────────────────────

  void assignMealToType(MealModel meal, String type) {
    final key = type.toLowerCase();
    if (_mealsByType.containsKey(key)) {
      _mealsByType[key]!.add(meal);
      notifyListeners();
      _saveToPrefs();
    }
  }

  // ── SharedPreferences ─────────────────────────────────────────────────────

  Future<void> loadFromPrefs() async => _loadFromPrefs();

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dailyCalorieGoal =
          prefs.getDouble('daily_calorie_goal') ?? _dailyCalorieGoal;
      _proteinGoal = prefs.getDouble('protein_goal') ?? _proteinGoal;
      _carbsGoal = prefs.getDouble('carbs_goal') ?? _carbsGoal;
      _fatGoal = prefs.getDouble('fat_goal') ?? _fatGoal;
      _dietType = prefs.getString('diet_type') ?? _dietType;
      _dietGoal = prefs.getString('diet_goal') ?? _dietGoal;

      // Water: reset to 0 if it was saved on a different day (day-rollover)
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final savedDate = prefs.getString('water_date') ?? '';
      _waterIntake =
          savedDate == today ? (prefs.getInt('water_intake') ?? 0) : 0;
      _waterGoal = prefs.getInt('water_goal') ?? 8;

      final weightRaw = prefs.getString('weight_history');
      if (weightRaw != null) {
        final list = jsonDecode(weightRaw) as List;
        _weightHistory =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      final mealsRaw = prefs.getString('meals_by_type');
      if (mealsRaw != null) {
        final map = jsonDecode(mealsRaw) as Map<String, dynamic>;
        final result = <String, List<MealModel>>{
          'breakfast': [],
          'lunch': [],
          'dinner': [],
          'snack': [],
        };
        for (final key in result.keys) {
          if (map[key] is List) {
            result[key] = (map[key] as List)
                .map((e) =>
                    MealModel.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
          }
        }
        _mealsByType = result;
      }
    } catch (e) {
      debugPrint('Prefs load failed: $e');
    }
  }

  Future<void> _saveGoalsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('daily_calorie_goal', _dailyCalorieGoal);
      await prefs.setDouble('protein_goal', _proteinGoal);
      await prefs.setDouble('carbs_goal', _carbsGoal);
      await prefs.setDouble('fat_goal', _fatGoal);
      await prefs.setString('diet_type', _dietType);
      await prefs.setString('diet_goal', _dietGoal);
    } catch (e) {
      debugPrint('Goals prefs save failed: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('daily_calorie_goal', _dailyCalorieGoal);
      await prefs.setDouble('protein_goal', _proteinGoal);
      await prefs.setDouble('carbs_goal', _carbsGoal);
      await prefs.setDouble('fat_goal', _fatGoal);
      await prefs.setString('diet_type', _dietType);
      await prefs.setString('diet_goal', _dietGoal);
      await prefs.setString('weight_history', jsonEncode(_weightHistory));

      final mealsMap = <String, dynamic>{};
      for (final e in _mealsByType.entries) {
        mealsMap[e.key] = e.value.map((m) => m.toJson()).toList();
      }
      await prefs.setString('meals_by_type', jsonEncode(mealsMap));
    } catch (e) {
      debugPrint('Prefs save failed: $e');
    }
  }
}
