import 'dart:io';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/meal_model.dart';

class ApiService {
  /// Override at build time, e.g. for a local backend:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://nutriscan-backend-production-dabf.up.railway.app',
  );

  Future<Map<String, dynamic>> recognizeFood(File imageFile) async {
    final uri = Uri.parse('$baseUrl/food/recognize');
    final request = http.MultipartRequest('POST', uri);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      request.headers['Authorization'] = 'Bearer $token';
    }

    final extension = imageFile.path.split('.').last.toLowerCase();
    final mediaType = extension == 'png'
        ? MediaType('image', 'png')
        : MediaType('image', 'jpeg');

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        imageFile.path,
        contentType: mediaType,
      ),
    );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception(
        'Request timed out. Check that your backend is running at $baseUrl',
      ),
    );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Server error ${response.statusCode}: ${response.body}');
    }
  }

  Future<List<String>> getHealthTips(List<String> meals) async {
    final uri = Uri.parse('$baseUrl/health/tips');
    try {
      final headers = {'Content-Type': 'application/json'};
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode({'meals': meals}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data.map((e) => e.toString()).toList();
        }
        if (data is Map && data['tips'] is List) {
          return (data['tips'] as List).map((e) => e.toString()).toList();
        }
      }
      throw Exception('Server error ${response.statusCode}');
    } catch (e) {
      throw Exception('Failed to get health tips: $e');
    }
  }

  NutritionInfo parseNutrition(Map<String, dynamic> apiResponse) {
    final nutritionJson =
        (apiResponse['nutrition'] ?? apiResponse['nutrition_per_100g'])
            as Map<String, dynamic>?;
    if (nutritionJson == null) {
      throw Exception('No nutrition data in API response');
    }
    return NutritionInfo.fromJson(nutritionJson);
  }
}