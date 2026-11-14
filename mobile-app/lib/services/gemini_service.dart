import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// AI "coach" features (meal feedback, nutrition search).
///
/// All Gemini calls go through the NutriScan backend, so the Gemini API key
/// lives only on the server and is never shipped inside the APK.
class GeminiService {
  static const Duration _timeout = Duration(seconds: 30);

  static Future<Map<String, String>> _authHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static Future<Map<String, dynamic>?> _post(
      String path, Map<String, dynamic> body) async {
    final response = await http
        .post(Uri.parse('${ApiService.baseUrl}$path'),
            headers: await _authHeaders(), body: jsonEncode(body))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      debugPrint('POST $path failed: ${response.statusCode} ${response.body}');
      return null;
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ── Nutrition database (per 100 g) ─────────────────────────────────────────
  static const Map<String, Map<String, dynamic>> _nutritionDb = {
    // ── Common Western foods ──────────────────────────────────────────────────
    'pizza':        {'calories': 266, 'protein': 11,  'carbs': 33,  'fat': 10,   'fiber': 2.3, 'display_name': 'Pizza'},
    'burger':       {'calories': 295, 'protein': 17,  'carbs': 24,  'fat': 14,   'fiber': 1.3, 'display_name': 'Burger'},
    'hamburger':    {'calories': 295, 'protein': 17,  'carbs': 24,  'fat': 14,   'fiber': 1.3, 'display_name': 'Hamburger'},
    'rice':         {'calories': 130, 'protein': 2.7, 'carbs': 28,  'fat': 0.3,  'fiber': 0.4, 'display_name': 'Rice'},
    'fried_rice':   {'calories': 163, 'protein': 4,   'carbs': 28,  'fat': 4,    'fiber': 0.9, 'display_name': 'Fried Rice'},
    'chicken':      {'calories': 165, 'protein': 31,  'carbs': 0,   'fat': 3.6,  'fiber': 0,   'display_name': 'Chicken'},
    'grilled_chicken':{'calories':165,'protein': 31,  'carbs': 0,   'fat': 3.6,  'fiber': 0,   'display_name': 'Grilled Chicken'},
    'chicken_wings':{'calories': 290, 'protein': 27,  'carbs': 0,   'fat': 19,   'fiber': 0,   'display_name': 'Chicken Wings'},
    'salad':        {'calories': 20,  'protein': 1.8, 'carbs': 3.5, 'fat': 0.2,  'fiber': 2.1, 'display_name': 'Salad'},
    'greek_salad':  {'calories': 100, 'protein': 4,   'carbs': 7,   'fat': 7,    'fiber': 2,   'display_name': 'Greek Salad'},
    'pasta':        {'calories': 220, 'protein': 8,   'carbs': 43,  'fat': 1.3,  'fiber': 2.5, 'display_name': 'Pasta'},
    'spaghetti':    {'calories': 220, 'protein': 8,   'carbs': 43,  'fat': 1.3,  'fiber': 2.5, 'display_name': 'Spaghetti'},
    'bread':        {'calories': 265, 'protein': 9,   'carbs': 49,  'fat': 3.2,  'fiber': 2.7, 'display_name': 'Bread'},
    'garlic_bread': {'calories': 350, 'protein': 8,   'carbs': 45,  'fat': 15,   'fiber': 2,   'display_name': 'Garlic Bread'},
    'eggs':         {'calories': 155, 'protein': 13,  'carbs': 1.1, 'fat': 11,   'fiber': 0,   'display_name': 'Eggs'},
    'omelette':     {'calories': 155, 'protein': 11,  'carbs': 1,   'fat': 12,   'fiber': 0,   'display_name': 'Omelette'},
    'fish':         {'calories': 136, 'protein': 22,  'carbs': 0,   'fat': 5,    'fiber': 0,   'display_name': 'Fish'},
    'salmon':       {'calories': 208, 'protein': 20,  'carbs': 0,   'fat': 13,   'fiber': 0,   'display_name': 'Salmon'},
    'tuna':         {'calories': 116, 'protein': 26,  'carbs': 0,   'fat': 1,    'fiber': 0,   'display_name': 'Tuna'},
    'steak':        {'calories': 271, 'protein': 26,  'carbs': 0,   'fat': 18,   'fiber': 0,   'display_name': 'Steak'},
    'sandwich':     {'calories': 250, 'protein': 12,  'carbs': 30,  'fat': 8,    'fiber': 3,   'display_name': 'Sandwich'},
    'hot_dog':      {'calories': 290, 'protein': 11,  'carbs': 24,  'fat': 17,   'fiber': 1,   'display_name': 'Hot Dog'},
    'soup':         {'calories': 50,  'protein': 2,   'carbs': 8,   'fat': 1,    'fiber': 1,   'display_name': 'Soup'},
    'sushi':        {'calories': 150, 'protein': 6,   'carbs': 28,  'fat': 1,    'fiber': 1,   'display_name': 'Sushi'},
    'tacos':        {'calories': 226, 'protein': 10,  'carbs': 21,  'fat': 11,   'fiber': 3,   'display_name': 'Tacos'},
    'french_fries': {'calories': 312, 'protein': 3.4, 'carbs': 41,  'fat': 15,   'fiber': 3.8, 'display_name': 'French Fries'},
    'onion_rings':  {'calories': 411, 'protein': 5,   'carbs': 44,  'fat': 25,   'fiber': 2,   'display_name': 'Onion Rings'},
    'nachos':       {'calories': 300, 'protein': 7,   'carbs': 35,  'fat': 16,   'fiber': 3,   'display_name': 'Nachos'},

    // ── Fruits ────────────────────────────────────────────────────────────────
    'apple':        {'calories': 52,  'protein': 0.3, 'carbs': 14,  'fat': 0.2,  'fiber': 2.4, 'display_name': 'Apple'},
    'banana':       {'calories': 89,  'protein': 1.1, 'carbs': 23,  'fat': 0.3,  'fiber': 2.6, 'display_name': 'Banana'},
    'orange':       {'calories': 47,  'protein': 0.9, 'carbs': 12,  'fat': 0.1,  'fiber': 2.4, 'display_name': 'Orange'},
    'mango':        {'calories': 60,  'protein': 0.8, 'carbs': 15,  'fat': 0.4,  'fiber': 1.6, 'display_name': 'Mango'},
    'mango_fruit':  {'calories': 60,  'protein': 0.8, 'carbs': 15,  'fat': 0.4,  'fiber': 1.6, 'display_name': 'Mango'},
    'grapes':       {'calories': 67,  'protein': 0.6, 'carbs': 17,  'fat': 0.4,  'fiber': 0.9, 'display_name': 'Grapes'},
    'avocado':      {'calories': 160, 'protein': 2,   'carbs': 9,   'fat': 15,   'fiber': 7,   'display_name': 'Avocado'},
    'strawberry':   {'calories': 32,  'protein': 0.7, 'carbs': 8,   'fat': 0.3,  'fiber': 2,   'display_name': 'Strawberry'},
    'ressberry':    {'calories': 52,  'protein': 1.2, 'carbs': 12,  'fat': 0.7,  'fiber': 6.5, 'display_name': 'Raspberry'},
    'chery_fruit':  {'calories': 50,  'protein': 1,   'carbs': 12,  'fat': 0.3,  'fiber': 1.6, 'display_name': 'Cherry'},

    // ── Dairy ─────────────────────────────────────────────────────────────────
    'milk':         {'calories': 61,  'protein': 3.2, 'carbs': 4.8, 'fat': 3.3,  'fiber': 0,   'display_name': 'Milk'},
    'cheese':       {'calories': 402, 'protein': 25,  'carbs': 1.3, 'fat': 33,   'fiber': 0,   'display_name': 'Cheese'},
    'yogurt':       {'calories': 59,  'protein': 3.5, 'carbs': 5,   'fat': 3.3,  'fiber': 0,   'display_name': 'Yogurt'},
    'ice_cream':    {'calories': 207, 'protein': 3.5, 'carbs': 24,  'fat': 11,   'fiber': 0.7, 'display_name': 'Ice Cream'},
    'frozen_yogurt':{'calories': 127, 'protein': 3,   'carbs': 22,  'fat': 3,    'fiber': 0,   'display_name': 'Frozen Yogurt'},

    // ── Sweets & Desserts ─────────────────────────────────────────────────────
    'chocolate':    {'calories': 546, 'protein': 5,   'carbs': 60,  'fat': 31,   'fiber': 7,   'display_name': 'Chocolate'},
    'cake':         {'calories': 347, 'protein': 5,   'carbs': 50,  'fat': 15,   'fiber': 1,   'display_name': 'Cake'},
    'chocolate_cake':{'calories':371, 'protein': 5,   'carbs': 53,  'fat': 17,   'fiber': 2,   'display_name': 'Chocolate Cake'},
    'cheesecake':   {'calories': 321, 'protein': 6,   'carbs': 26,  'fat': 23,   'fiber': 0.4, 'display_name': 'Cheesecake'},
    'donut':        {'calories': 452, 'protein': 5,   'carbs': 51,  'fat': 25,   'fiber': 1.5, 'display_name': 'Donut'},
    'donuts':       {'calories': 452, 'protein': 5,   'carbs': 51,  'fat': 25,   'fiber': 1.5, 'display_name': 'Donuts'},
    'waffles':      {'calories': 291, 'protein': 8,   'carbs': 37,  'fat': 13,   'fiber': 1.5, 'display_name': 'Waffles'},
    'pancakes':     {'calories': 227, 'protein': 6,   'carbs': 28,  'fat': 10,   'fiber': 1.3, 'display_name': 'Pancakes'},
    'macarons':     {'calories': 400, 'protein': 5,   'carbs': 60,  'fat': 17,   'fiber': 1,   'display_name': 'Macarons'},
    'tiramisu':     {'calories': 280, 'protein': 5,   'carbs': 28,  'fat': 17,   'fiber': 0.5, 'display_name': 'Tiramisu'},
    'creme_brulee': {'calories': 230, 'protein': 4,   'carbs': 23,  'fat': 14,   'fiber': 0,   'display_name': 'Crème Brûlée'},
    'cannoli':      {'calories': 300, 'protein': 6,   'carbs': 35,  'fat': 15,   'fiber': 1,   'display_name': 'Cannoli'},

    // ── Egyptian & Middle Eastern foods ──────────────────────────────────────
    'bamya':        {'calories': 35,  'protein': 2,   'carbs': 7,   'fat': 0.2,  'fiber': 3.2, 'display_name': 'Bamya (Okra Stew)'},
    'bamia':        {'calories': 35,  'protein': 2,   'carbs': 7,   'fat': 0.2,  'fiber': 3.2, 'display_name': 'Bamia (Okra Stew)'},
    'koshari':      {'calories': 180, 'protein': 5,   'carbs': 35,  'fat': 3.0,  'fiber': 4.0, 'display_name': 'Koshari'},
    'koshary':      {'calories': 180, 'protein': 5,   'carbs': 35,  'fat': 3.0,  'fiber': 4.0, 'display_name': 'Koshari'},
    'fattah':       {'calories': 280, 'protein': 12,  'carbs': 40,  'fat': 8.0,  'fiber': 2.0, 'display_name': 'Fattah'},
    'fatta':        {'calories': 280, 'protein': 12,  'carbs': 40,  'fat': 8.0,  'fiber': 2.0, 'display_name': 'Fattah'},
    'molokhia':     {'calories': 45,  'protein': 4,   'carbs': 8,   'fat': 0.5,  'fiber': 3.0, 'display_name': 'Molokhia'},
    'mulukhiyah':   {'calories': 45,  'protein': 4,   'carbs': 8,   'fat': 0.5,  'fiber': 3.0, 'display_name': 'Molokhia'},
    'kunafa':       {'calories': 380, 'protein': 8,   'carbs': 55,  'fat': 15.0, 'fiber': 1.0, 'display_name': 'Kunafa'},
    'knafeh':       {'calories': 380, 'protein': 8,   'carbs': 55,  'fat': 15.0, 'fiber': 1.0, 'display_name': 'Kunafa'},
    'mansaf':       {'calories': 310, 'protein': 18,  'carbs': 30,  'fat': 12.0, 'fiber': 1.5, 'display_name': 'Mansaf'},
    'mahshi':       {'calories': 130, 'protein': 5,   'carbs': 20,  'fat': 4.0,  'fiber': 2.0, 'display_name': 'Mahshi'},
    'kibbeh':       {'calories': 220, 'protein': 14,  'carbs': 18,  'fat': 10.0, 'fiber': 1.5, 'display_name': 'Kibbeh'},
    'shawarma':     {'calories': 280, 'protein': 22,  'carbs': 25,  'fat': 10.0, 'fiber': 2.0, 'display_name': 'Shawarma'},
    'kebab':        {'calories': 226, 'protein': 22,  'carbs': 4,   'fat': 14.0, 'fiber': 0.5, 'display_name': 'Kebab'},
    'falafel':      {'calories': 333, 'protein': 13,  'carbs': 32,  'fat': 18.0, 'fiber': 8.0, 'display_name': 'Falafel'},
    'hummus':       {'calories': 177, 'protein': 8,   'carbs': 20,  'fat': 8.0,  'fiber': 6.0, 'display_name': 'Hummus'},
    'baklava':      {'calories': 428, 'protein': 6,   'carbs': 56,  'fat': 21.0, 'fiber': 2.0, 'display_name': 'Baklava'},
    'qatayef':      {'calories': 320, 'protein': 7,   'carbs': 50,  'fat': 10.0, 'fiber': 1.5, 'display_name': 'Qatayef'},
    'mojadra':      {'calories': 155, 'protein': 7,   'carbs': 28,  'fat': 3.0,  'fiber': 5.0, 'display_name': 'Mujaddara'},
    'mandi':        {'calories': 290, 'protein': 20,  'carbs': 30,  'fat': 9.0,  'fiber': 1.0, 'display_name': 'Mandi'},
    'fava_beans':   {'calories': 110, 'protein': 8,   'carbs': 19,  'fat': 0.5,  'fiber': 8.0, 'display_name': 'Fava Beans (Ful)'},
    'ful':          {'calories': 110, 'protein': 8,   'carbs': 19,  'fat': 0.5,  'fiber': 8.0, 'display_name': 'Ful Medames'},
    'samosa':       {'calories': 262, 'protein': 5,   'carbs': 31,  'fat': 13,   'fiber': 2,   'display_name': 'Samosa'},
    'spring_rolls': {'calories': 153, 'protein': 4,   'carbs': 22,  'fat': 6,    'fiber': 1.5, 'display_name': 'Spring Rolls'},
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns personalised 2–3 sentence feedback using the user's full profile.
  static Future<String?> getPersonalizedFeedback({
    required String foodName,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double calorieGoal,
    required double todayCalories,
    required List<String> allergies,
    required List<String> dietRestrictions,
    required String healthGoal,
  }) async {
    // Always check allergens locally first, regardless of network.
    final conflicts = _checkAllergens(foodName, allergies);
    final warningPrefix = conflicts.isNotEmpty
        ? '⚠️ Warning: This food may contain ${conflicts.join(', ')}. Check ingredients carefully.\n\n'
        : '';

    try {
      final data = await _post('/ai/feedback', {
        'food_name': foodName,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'calorie_goal': calorieGoal,
        'today_calories': todayCalories,
        'allergies': allergies,
        'diet_restrictions': dietRestrictions,
        'health_goal': healthGoal,
      });
      final text = (data?['feedback'] as String?)?.trim();
      if (text != null && text.isNotEmpty) return warningPrefix + text;
    } catch (e) {
      debugPrint('AI feedback failed: $e');
    }

    return warningPrefix +
        _personalizedFallback(
          foodName: foodName,
          calories: calories,
          protein: protein,
          calorieGoal: calorieGoal,
          todayCalories: todayCalories,
        );
  }

  /// Looks up nutrition per 100 g for a given food name.
  /// Checks the local database first, then asks the backend (Gemini) as a fallback.
  static Future<Map<String, dynamic>?> searchFoodNutrition(
      String foodName) async {
    // Normalise the query to match database keys.
    final query = foodName.toLowerCase().trim();
    final keyUnderscore = query.replaceAll(' ', '_');
    final keySpace = query.replaceAll('_', ' ');

    // Direct key lookup.
    final direct = _nutritionDb[keyUnderscore] ?? _nutritionDb[keySpace];
    if (direct != null) return Map.from(direct);

    // Partial / contains match (handles "chicken curry" → 'chicken').
    for (final entry in _nutritionDb.entries) {
      final k = entry.key.replaceAll('_', ' ');
      if (k.contains(keySpace) || keySpace.contains(k)) {
        return Map.from(entry.value)
          ..['display_name'] = foodName; // keep user's query as display name
      }
    }

    // Backend fallback: POST /nutrition/lookup (Gemini, per 100 g).
    try {
      final data = await _post('/nutrition/lookup', {'query': foodName});
      final foods = data?['foods'] as List?;
      if (foods != null && foods.isNotEmpty) {
        final f = Map<String, dynamic>.from(foods.first as Map);
        num n(String k) => (f[k] as num?) ?? 0;
        return {
          'calories': n('calories'),
          'protein': n('protein_g'),
          'carbs': n('total_carbohydrate_g'),
          'fat': n('total_fat_g'),
          'fiber': n('dietary_fiber_g'),
          'display_name': f['food_name'] ?? foodName,
        };
      }
    } catch (e) {
      debugPrint('Nutrition lookup failed: $e');
    }

    // Both local db and backend failed → return null so UI shows error message.
    return null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns allergens that may be present in [foodName] based on user's list.
  static List<String> _checkAllergens(String foodName, List<String> userAllergies) {
    if (userAllergies.isEmpty || userAllergies.contains('None')) return [];
    final food = foodName.toLowerCase();
    const allergenKeywords = {
      'Gluten': ['bread', 'wheat', 'pasta', 'pizza', 'croissant', 'waffle',
          'pancake', 'cookie', 'cake', 'burger', 'sandwich', 'donut', 'noodle'],
      'Dairy': ['milk', 'cheese', 'yogurt', 'ice cream', 'butter', 'cream',
          'tiramisu', 'cheesecake', 'lasagna'],
      'Nuts': ['almond', 'peanut', 'walnut', 'cashew', 'pistachio',
          'hazelnut', 'nut', 'baklava'],
      'Eggs': ['egg', 'omelette', 'mayonnaise', 'quiche'],
      'Shellfish': ['shrimp', 'crab', 'lobster', 'oyster', 'mussel', 'prawn'],
      'Soy': ['soy', 'tofu', 'edamame', 'miso'],
    };
    final conflicts = <String>[];
    for (final allergen in userAllergies) {
      final keywords = allergenKeywords[allergen];
      if (keywords != null && keywords.any((k) => food.contains(k))) {
        conflicts.add(allergen);
      }
    }
    return conflicts;
  }

  static String _personalizedFallback({
    required String foodName,
    required double calories,
    required double protein,
    required double calorieGoal,
    required double todayCalories,
  }) {
    final remaining = calorieGoal - todayCalories;
    if (remaining < 0) {
      return "You've exceeded your calorie goal today. Consider lighter options for your next meal.";
    }
    if (calories > calorieGoal * 0.3) {
      return "This is a high-calorie meal. Balance it with lighter options for the rest of the day.";
    }
    if (protein > 20) {
      return "Great protein content! This meal supports muscle maintenance and keeps you full longer.";
    }
    if (remaining < 200) {
      return "Almost at your daily goal! Keep portions small for the rest of the day.";
    }
    return "Great job tracking $foodName! Stay consistent to reach your health goals.";
  }
}
