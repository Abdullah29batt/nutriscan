class UserProfileModel {
  String firstName;
  String lastName;
  String email;
  int age;
  double weight;
  double height;
  String gender;
  String activityLevel;
  String dietGoal;
  String dietType;
  double dailyCalorieGoal;

  UserProfileModel({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.age = 25,
    this.weight = 70,
    this.height = 170,
    this.gender = 'male',
    this.activityLevel = 'sedentary',
    this.dietGoal = 'maintain',
    this.dietType = 'normal',
    this.dailyCalorieGoal = 2000,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      age: (json['age'] as num?)?.toInt() ?? 25,
      weight: (json['weight'] as num?)?.toDouble() ?? 70,
      height: (json['height'] as num?)?.toDouble() ?? 170,
      gender: json['gender'] as String? ?? 'male',
      activityLevel: json['activityLevel'] as String? ?? 'sedentary',
      dietGoal: json['dietGoal'] as String? ?? 'maintain',
      dietType: json['dietType'] as String? ?? 'normal',
      dailyCalorieGoal:
          (json['dailyCalorieGoal'] as num?)?.toDouble() ?? 2000,
    );
  }

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'age': age,
        'weight': weight,
        'height': height,
        'gender': gender,
        'activityLevel': activityLevel,
        'dietGoal': dietGoal,
        'dietType': dietType,
        'dailyCalorieGoal': dailyCalorieGoal,
      };
}
