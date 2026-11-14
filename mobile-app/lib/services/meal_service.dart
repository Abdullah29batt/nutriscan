import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_model.dart';

class MealService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _localKey = 'local_meals';
  static const String _freqKey = 'food_frequencies';
  static const String _cachePrefix = 'food_cache_';

  CollectionReference<Map<String, dynamic>> _mealsRef(String userId) =>
      _db.collection('users').doc(userId).collection('meals');

  /// Write to local immediately, then sync to Firestore in background.
  Future<void> saveMeal(MealModel meal) async {
    await _saveLocally(meal);
    _mealsRef(meal.userId)
        .doc(meal.id)
        .set(meal.toJson())
        .catchError((e) => debugPrint('Firestore meal save failed: $e'));
  }

  /// Returns local cache immediately — fast and offline-safe.
  Future<List<MealModel>> getMeals(String userId) async {
    return _getLocalMeals(userId);
  }

  /// Fetch from Firestore, update local cache, return updated list.
  /// Call this after getMeals() to refresh in the background.
  Future<List<MealModel>> syncFromFirestore(String userId) async {
    try {
      final snapshot = await _mealsRef(userId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();
      final meals =
          snapshot.docs.map((d) => MealModel.fromJson(d.data())).toList();
      await _replaceLocalMeals(userId, meals);
      return meals;
    } catch (e) {
      debugPrint('Firestore meal sync failed: $e');
      return _getLocalMeals(userId);
    }
  }

  /// Delete locally immediately, then sync to Firestore in background.
  Future<void> deleteMeal(String userId, String mealId) async {
    await _deleteLocalMeal(mealId);
    _mealsRef(userId)
        .doc(mealId)
        .delete()
        .catchError((e) => debugPrint('Firestore meal delete failed: $e'));
  }

  Future<void> _saveLocally(MealModel meal) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey) ?? '[]';
    final list = (json.decode(raw) as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    list.removeWhere((e) => e['id'] == meal.id);
    list.insert(0, meal.toJson());
    await prefs.setString(_localKey, json.encode(list));
  }

  Future<List<MealModel>> _getLocalMeals(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey) ?? '[]';
    final list = (json.decode(raw) as List)
        .map((e) => e as Map<String, dynamic>)
        .where((e) => e['userId'] == userId)
        .toList();
    return list.map(MealModel.fromJson).toList();
  }

  /// Replace this user's local cache with authoritative Firestore data.
  Future<void> _replaceLocalMeals(
      String userId, List<MealModel> meals) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey) ?? '[]';
    // Preserve any meals belonging to other users
    final otherUsers = (json.decode(raw) as List)
        .map((e) => e as Map<String, dynamic>)
        .where((e) => e['userId'] != userId)
        .toList();
    final merged = [...otherUsers, ...meals.map((m) => m.toJson())];
    await prefs.setString(_localKey, json.encode(merged));
  }

  Future<void> _deleteLocalMeal(String mealId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey) ?? '[]';
    final list = (json.decode(raw) as List)
        .map((e) => e as Map<String, dynamic>)
        .where((e) => e['id'] != mealId)
        .toList();
    await prefs.setString(_localKey, json.encode(list));
  }

  // ── Frequent-food tracking & nutrition cache ────────────────────────────────

  /// Increment the log-count for [foodName] and cache its nutrition.
  Future<void> trackFoodLogged(String foodName, NutritionInfo nutrition) async {
    final prefs = await SharedPreferences.getInstance();
    final key = foodName.toLowerCase().trim();

    // frequency counter
    final freqMap = Map<String, dynamic>.from(
      json.decode(prefs.getString(_freqKey) ?? '{}') as Map,
    );
    freqMap[key] = ((freqMap[key] as num?)?.toInt() ?? 0) + 1;
    await prefs.setString(_freqKey, json.encode(freqMap));

    // nutrition cache with timestamp
    await prefs.setString(
      '$_cachePrefix$key',
      json.encode({
        ...nutrition.toJson(),
        '_cachedAt': DateTime.now().toIso8601String(),
        '_displayName': foodName,
      }),
    );
  }

  /// Return top [limit] foods sorted by frequency, with cached nutrition.
  Future<List<Map<String, dynamic>>> getFrequentFoods({int limit = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final freqMap = Map<String, dynamic>.from(
      json.decode(prefs.getString(_freqKey) ?? '{}') as Map,
    );
    final sorted = freqMap.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    final result = <Map<String, dynamic>>[];
    for (final e in sorted) {
      if (result.length >= limit) break;
      final nutrition = await getCachedNutrition(e.key, prefs: prefs);
      if (nutrition == null) continue;
      final raw = prefs.getString('$_cachePrefix${e.key}');
      final displayName = raw != null
          ? ((json.decode(raw) as Map)['_displayName'] as String?) ?? e.key
          : e.key;
      result.add({
        'foodName': displayName,
        'key': e.key,
        'count': e.value,
        'nutrition': nutrition,
      });
    }
    return result;
  }

  /// Return the cached [NutritionInfo] for [foodName], or null if missing/stale.
  Future<NutritionInfo?> getCachedNutrition(
    String foodName, {
    SharedPreferences? prefs,
  }) async {
    prefs ??= await SharedPreferences.getInstance();
    final key = foodName.toLowerCase().trim();
    final raw = prefs.getString('$_cachePrefix$key');
    if (raw == null) return null;
    try {
      final map = Map<String, dynamic>.from(json.decode(raw) as Map);
      final cachedAt = DateTime.tryParse(map['_cachedAt'] as String? ?? '');
      if (cachedAt != null &&
          DateTime.now().difference(cachedAt).inDays > 7) {
        return null; // stale
      }
      return NutritionInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
