class NutritionInfo {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double sodium;

  const NutritionInfo({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber = 0,
    this.sugar = 0,
    this.sodium = 0,
  });

  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    double parse(dynamic v) =>
        v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
    return NutritionInfo(
      calories: parse(json['calories']),
      protein: parse(json['protein']),
      carbs: parse(json['carbs'] ?? json['carbohydrates']),
      fat: parse(json['fat']),
      fiber: parse(json['fiber']),
      sugar: parse(json['sugar']),
      sodium: parse(json['sodium']),
    );
  }

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'sugar': sugar,
        'sodium': sodium,
      };
}

class MealModel {
  final String id;
  final String userId;
  final String foodName;
  final String imagePath;
  final double confidence;
  final NutritionInfo nutrition;
  final DateTime timestamp;
  final double servingSize;

  const MealModel({
    required this.id,
    required this.userId,
    required this.foodName,
    required this.imagePath,
    required this.confidence,
    required this.nutrition,
    required this.timestamp,
    this.servingSize = 100,
  });

  factory MealModel.fromJson(Map<String, dynamic> json) {
    return MealModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      foodName: json['foodName'] as String? ?? 'Unknown Food',
      imagePath: json['imagePath'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      nutrition: NutritionInfo.fromJson(
          json['nutrition'] as Map<String, dynamic>? ?? {}),
      timestamp: json['timestamp'] is String
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.fromMillisecondsSinceEpoch(
              (json['timestamp'] as num?)?.toInt() ?? 0),
      servingSize: (json['servingSize'] as num?)?.toDouble() ?? 100,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'foodName': foodName,
        'imagePath': imagePath,
        'confidence': confidence,
        'nutrition': nutrition.toJson(),
        'timestamp': timestamp.toIso8601String(),
        'servingSize': servingSize,
      };

  MealModel copyWith({
    String? id,
    String? userId,
    String? foodName,
    String? imagePath,
    double? confidence,
    NutritionInfo? nutrition,
    DateTime? timestamp,
    double? servingSize,
  }) {
    return MealModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      foodName: foodName ?? this.foodName,
      imagePath: imagePath ?? this.imagePath,
      confidence: confidence ?? this.confidence,
      nutrition: nutrition ?? this.nutrition,
      timestamp: timestamp ?? this.timestamp,
      servingSize: servingSize ?? this.servingSize,
    );
  }
}
