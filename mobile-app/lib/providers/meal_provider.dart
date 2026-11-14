import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart' show Uuid;

import '../models/meal_model.dart';
import '../services/api_service.dart';
import '../services/meal_service.dart';
import '../services/nutrition_tflite_service.dart';
import '../services/tflite_service.dart';

enum MealLoadState { idle, loading, success, error }

enum InferenceSource { api, onDevice }

class MealProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final MealService _mealService = MealService();
  final TFLiteService _tflite = TFLiteService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _foodConfidenceThreshold = 0.15;

  List<MealModel> _meals = [];
  MealModel? _currentMeal;
  MealLoadState _state = MealLoadState.idle;
  String? _error;
  InferenceSource? _lastSource;
  bool _noFoodDetected = false;

  // Full prediction list and per-100 g nutrition from the last API response
  List<Map<String, dynamic>> _allPredictions = [];
  NutritionInfo? _nutritionPer100g;

  // Favorites
  List<Map<String, dynamic>> _favorites = [];

  // Frequent foods (Feature 4)
  List<Map<String, dynamic>> _frequentFoods = [];

  // ── Getters ────────────────────────────────────────────────────────────────

  List<MealModel> get meals => List.unmodifiable(_meals);
  MealModel? get currentMeal => _currentMeal;
  MealLoadState get state => _state;
  String? get error => _error;
  bool get isAnalyzing => _state == MealLoadState.loading;
  bool get usedOnDeviceInference => _lastSource == InferenceSource.onDevice;
  bool get noFoodDetected => _noFoodDetected;
  List<Map<String, dynamic>> get allPredictions =>
      List.unmodifiable(_allPredictions);
  NutritionInfo? get nutritionPer100g => _nutritionPer100g;
  List<Map<String, dynamic>> get favorites => List.unmodifiable(_favorites);
  List<Map<String, dynamic>> get frequentFoods =>
      List.unmodifiable(_frequentFoods);

  // ── Today's nutrition (computed from Firestore-backed meals list) ──────────

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
  }

  List<MealModel> get todayMeals => _meals.where((m) => _isToday(m.timestamp)).toList();

  double get todayCalories =>
      todayMeals.fold(0.0, (s, m) => s + m.nutrition.calories);
  double get todayProtein =>
      todayMeals.fold(0.0, (s, m) => s + m.nutrition.protein);
  double get todayCarbs =>
      todayMeals.fold(0.0, (s, m) => s + m.nutrition.carbs);
  double get todayFat =>
      todayMeals.fold(0.0, (s, m) => s + m.nutrition.fat);

  int get todayMealCount => todayMeals.length;

  List<double> get last7DaysCalories {
    final result = <double>[];
    for (int i = 6; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      final total = _meals
          .where((m) =>
              m.timestamp.year == day.year &&
              m.timestamp.month == day.month &&
              m.timestamp.day == day.day)
          .fold(0.0, (s, m) => s + m.nutrition.calories);
      result.add(total);
    }
    return result;
  }

  // ── Analyse ────────────────────────────────────────────────────────────────

  Future<bool> analyzeFood(File imageFile, String userId) async {
    _setState(MealLoadState.loading);
    _error = null;
    _currentMeal = null;
    _lastSource = null;
    _allPredictions = [];
    _nutritionPer100g = null;
    _noFoodDetected = false;
    notifyListeners();

    // 1. Try backend
    try {
      final result = await _api.recognizeFood(imageFile);

      final rawPreds = result['predictions'] as List<dynamic>?;
      _allPredictions = rawPreds
              ?.map((p) => Map<String, dynamic>.from(p as Map))
              .toList() ??
          [];

      final nutritionJson = result['nutrition'] as Map<String, dynamic>?;
      _nutritionPer100g =
          nutritionJson != null ? NutritionInfo.fromJson(nutritionJson) : null;

      _currentMeal = _mealFromApiResult(result, imageFile, userId);
      if (_currentMeal!.confidence < _foodConfidenceThreshold) {
        _noFoodDetected = true;
        _error = 'No food detected in this image.';
        _setState(MealLoadState.error);
        return false;
      }
      await _applyNutritionPrediction(_currentMeal!.foodName);
      _lastSource = InferenceSource.api;
      _setState(MealLoadState.success);
      return true;
    } catch (apiError) {
      debugPrint(
          'API unavailable ($apiError) — falling back to on-device model');
    }

    // 2. On-device TFLite fallback
    try {
      final result = await _tflite.classify(imageFile);

      // Populate predictions list from top-1 so ResultsScreen works offline.
      final preds = result['predictions'] as List<dynamic>?;
      _allPredictions = preds
              ?.map((p) => Map<String, dynamic>.from(p as Map))
              .toList() ??
          [];
      _nutritionPer100g = null;

      _currentMeal = _mealFromTFLiteResult(result, imageFile, userId);
      if (_currentMeal!.confidence < _foodConfidenceThreshold) {
        _noFoodDetected = true;
        _error = 'No food detected in this image.';
        _setState(MealLoadState.error);
        return false;
      }
      await _applyNutritionPrediction(_currentMeal!.foodName);
      _lastSource = InferenceSource.onDevice;
      _setState(MealLoadState.success);
      return true;
    } catch (tfliteError) {
      _error =
          'Recognition failed. Make sure the backend is reachable or the '
          'on-device model is loaded correctly.\n\nDetail: $tfliteError';
      _setState(MealLoadState.error);
      return false;
    }
  }

  void _setState(MealLoadState s) {
    _state = s;
    notifyListeners();
  }

  // Runs the on-device nutrition model and overwrites _nutritionPer100g and
  // _currentMeal.nutrition. Silently keeps existing values on failure.
  Future<void> _applyNutritionPrediction(String foodName) async {
    try {
      final nutrition =
          await NutritionTFLiteService.instance.predict(foodName);
      if (nutrition != null) {
        _nutritionPer100g = nutrition;
        _currentMeal = _currentMeal?.copyWith(nutrition: nutrition);
      }
    } catch (e) {
      debugPrint('NutritionTFLite predict failed: $e');
    }
  }

  // ── Parse helpers ──────────────────────────────────────────────────────────

  MealModel _mealFromApiResult(
      Map<String, dynamic> result, File imageFile, String userId) {
    final preds = result['predictions'] as List<dynamic>?;
    final first = (preds != null && preds.isNotEmpty)
        ? preds.first as Map<String, dynamic>?
        : null;
    final nutritionJson =
        (result['nutrition'] ?? result['nutrition_per_100g'])
            as Map<String, dynamic>?;
    return MealModel(
      id: const Uuid().v4(),
      userId: userId,
      foodName: result['top_display_name'] as String? ??
          result['food_name'] as String? ??
          'Unknown Food',
      imagePath: imageFile.path,
      confidence: (first?['confidence'] as num?)?.toDouble() ??
          (result['confidence'] as num?)?.toDouble() ??
          0.0,
      nutrition: nutritionJson != null
          ? NutritionInfo.fromJson(nutritionJson)
          : const NutritionInfo(calories: 0, protein: 0, carbs: 0, fat: 0),
      timestamp: DateTime.now(),
      servingSize: (result['serving_size'] as num?)?.toDouble() ?? 100,
    );
  }

  MealModel _mealFromTFLiteResult(
      Map<String, dynamic> result, File imageFile, String userId) {
    return MealModel(
      id: const Uuid().v4(),
      userId: userId,
      foodName: result['food_name'] as String? ?? 'Unknown Food',
      imagePath: imageFile.path,
      confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
      nutrition:
          const NutritionInfo(calories: 0, protein: 0, carbs: 0, fat: 0),
      timestamp: DateTime.now(),
      servingSize: 100,
    );
  }

  // ── History ────────────────────────────────────────────────────────────────

  Future<void> saveCurrentMeal() async {
    if (_currentMeal == null) return;
    await _mealService.saveMeal(_currentMeal!);
    await _mealService.trackFoodLogged(
        _currentMeal!.foodName, _currentMeal!.nutrition);
    _meals.insert(0, _currentMeal!);
    notifyListeners();
    await _updateStreak(_currentMeal!.userId);
  }

  /// Scales the current meal's nutrition to the user-selected serving size
  /// before saving so stored values match what was shown on screen.
  void applyServingAdjustment(double totalGrams, NutritionInfo scaledNutrition) {
    if (_currentMeal == null) return;
    _currentMeal = _currentMeal!.copyWith(
      nutrition: scaledNutrition,
      servingSize: totalGrams,
    );
  }

  // ── Feature 1: correct a low-confidence classification ─────────────────────

  Future<void> updateCurrentMealFoodName(String newName) async {
    if (_currentMeal == null) return;
    _currentMeal = _currentMeal!.copyWith(foodName: newName, confidence: 1.0);
    _allPredictions = [
      <String, dynamic>{
        'label': newName.toLowerCase().replaceAll(' ', '_'),
        'display_name': newName,
        'confidence': 1.0,
      }
    ];
    notifyListeners();
    await _applyNutritionPrediction(newName);
    notifyListeners();
  }

  // ── Feature 4: frequent-food quick log ─────────────────────────────────────

  Future<void> loadFrequentFoods() async {
    _frequentFoods = await _mealService.getFrequentFoods();
    notifyListeners();
  }

  Future<void> quickLogFood(
    String foodName,
    String userId, {
    NutritionInfo? nutrition,
  }) async {
    final resolved =
        nutrition ?? const NutritionInfo(calories: 0, protein: 0, carbs: 0, fat: 0);
    final meal = MealModel(
      id: const Uuid().v4(),
      userId: userId,
      foodName: foodName,
      imagePath: '',
      confidence: 1.0,
      nutrition: resolved,
      timestamp: DateTime.now(),
      servingSize: 100,
    );
    await _mealService.saveMeal(meal);
    await _mealService.trackFoodLogged(foodName, resolved);
    _meals.insert(0, meal);
    notifyListeners();
    await _updateStreak(userId);
  }

  Future<void> loadMeals(String userId) async {
    _setState(MealLoadState.loading);
    try {
      // Fast: serve from local cache immediately
      _meals = await _mealService.getMeals(userId);
      _setState(MealLoadState.idle);
      // Background: refresh from Firestore and update UI when done
      _mealService.syncFromFirestore(userId).then((meals) {
        _meals = meals;
        notifyListeners();
      }).catchError((_) {});
    } catch (e) {
      _error = 'Failed to load history.';
      _setState(MealLoadState.error);
    }
  }

  Future<void> deleteMeal(String userId, String mealId) async {
    await _mealService.deleteMeal(userId, mealId);
    _meals.removeWhere((m) => m.id == mealId);
    notifyListeners();
  }

  void clearCurrentMeal() {
    _currentMeal = null;
    _allPredictions = [];
    _nutritionPer100g = null;
    _state = MealLoadState.idle;
    _error = null;
    _lastSource = null;
    _noFoodDetected = false;
    notifyListeners();
  }

  // ── Streak ─────────────────────────────────────────────────────────────────

  Future<int> _updateStreak(String uid) async {
    try {
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('stats')
          .doc('streak');
      final snap = await ref.get();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final yesterday = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(const Duration(days: 1)));

      int newStreak = 1;
      if (snap.exists) {
        final last = snap.data()!['lastLoggedDate'] as String?;
        final cur = (snap.data()!['streak'] as num?)?.toInt() ?? 0;
        if (last == today) return cur; // already counted today
        if (last == yesterday) newStreak = cur + 1;
      }
      await ref.set({'streak': newStreak, 'lastLoggedDate': today});
      return newStreak;
    } catch (e) {
      debugPrint('Streak update failed: $e');
      return 0;
    }
  }

  // ── Favorites ──────────────────────────────────────────────────────────────

  bool isFavorite(String label) =>
      _favorites.any((f) => f['label'] == label);

  Future<void> loadFavorites(String uid) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('favorites')
          .get();
      _favorites = snap.docs.map((d) => d.data()).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Load favorites failed: $e');
    }
  }

  Future<void> addFavorite(Map<String, dynamic> food, String uid) async {
    final label = food['label'] as String? ?? '';
    if (isFavorite(label)) return;
    _favorites.add(food);
    notifyListeners();
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('favorites')
          .doc(label)
          .set(food);
    } catch (e) {
      debugPrint('Add favorite failed: $e');
    }
  }

  Future<void> removeFavorite(String label, String uid) async {
    _favorites.removeWhere((f) => f['label'] == label);
    notifyListeners();
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('favorites')
          .doc(label)
          .delete();
    } catch (e) {
      debugPrint('Remove favorite failed: $e');
    }
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _tflite.dispose();
    super.dispose();
  }
}
