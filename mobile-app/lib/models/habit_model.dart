class HabitModel {
  final String id;
  final String name;
  final String emoji;
  final String time;
  bool isEnabled;

  HabitModel({
    required this.id,
    required this.name,
    required this.emoji,
    required this.time,
    this.isEnabled = true,
  });

  factory HabitModel.fromJson(Map<String, dynamic> json) {
    return HabitModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '✅',
      time: json['time'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'time': time,
        'isEnabled': isEnabled,
      };
}
