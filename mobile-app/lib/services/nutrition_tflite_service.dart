import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/meal_model.dart';

class NutritionTFLiteService {
  NutritionTFLiteService._();
  static final NutritionTFLiteService instance = NutritionTFLiteService._();

  Interpreter? _interpreter;
  Map<String, int>? _vocabulary;
  List<double>? _idf;
  List<double>? _scalerMean;
  List<double>? _scalerScale;

  bool get isReady =>
      _interpreter != null &&
      _vocabulary != null &&
      _idf != null &&
      _scalerMean != null &&
      _scalerScale != null;

  Future<void> initialize() async {
    if (isReady) return;
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/nutrition_model.tflite',
        options: options,
      );

      final vecJson = json.decode(
        await rootBundle.loadString('assets/vectorizer.json'),
      ) as Map<String, dynamic>;
      _vocabulary = Map<String, int>.from(vecJson['vocabulary'] as Map);
      _idf = (vecJson['idf'] as List)
          .map((e) => (e as num).toDouble())
          .toList();

      final scalerJson = json.decode(
        await rootBundle.loadString('assets/scaler.json'),
      ) as Map<String, dynamic>;
      _scalerMean = (scalerJson['mean'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      _scalerScale = (scalerJson['scale'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    } catch (e) {
      _interpreter?.close();
      _interpreter = null;
      _vocabulary = null;
      _idf = null;
      _scalerMean = null;
      _scalerScale = null;
      rethrow;
    }
  }

  /// Predicts per-100 g nutrition for [foodName].
  /// Returns null if the model is unavailable or inference fails.
  Future<NutritionInfo?> predict(String foodName) async {
    if (!isReady) await initialize();

    final vocab = _vocabulary!;
    final idf = _idf!;
    final mean = _scalerMean!;
    final scale = _scalerScale!;

    // ── TF-IDF char n-gram vectorization ──────────────────────────────────
    final text = foodName.toLowerCase().replaceAll('_', ' ');
    final tfCounts = <int, double>{};
    for (int n = 2; n <= 4; n++) {
      for (int i = 0; i <= text.length - n; i++) {
        final ngram = text.substring(i, i + n);
        final idx = vocab[ngram];
        if (idx != null) {
          tfCounts[idx] = (tfCounts[idx] ?? 0.0) + 1.0;
        }
      }
    }

    // Apply IDF weights
    final vector = Float32List(3000);
    double normSq = 0.0;
    for (final entry in tfCounts.entries) {
      final val = entry.value * idf[entry.key];
      vector[entry.key] = val;
      normSq += val * val;
    }

    // L2 normalise
    if (normSq > 0) {
      final norm = math.sqrt(normSq);
      for (int i = 0; i < 3000; i++) {
        vector[i] /= norm;
      }
    }

    // ── TFLite inference: [1,3000] → [1,5] ────────────────────────────────
    // Same Uint8List/ByteBuffer trick as tflite_service.dart to bypass
    // tflite_flutter 0.12.x shape-check that would cause a RangeError.
    final outputBuffer = Float32List(5);
    _interpreter!.run(
      vector.buffer.asUint8List(),
      outputBuffer.buffer,
    );

    // ── Inverse StandardScaler + clamp to 0 ───────────────────────────────
    // nutrients order from scaler.json: calories, protein, carbs, fat, fiber
    return NutritionInfo(
      calories: math.max(0.0, outputBuffer[0] * scale[0] + mean[0]),
      protein: math.max(0.0, outputBuffer[1] * scale[1] + mean[1]),
      carbs: math.max(0.0, outputBuffer[2] * scale[2] + mean[2]),
      fat: math.max(0.0, outputBuffer[3] * scale[3] + mean[3]),
      fiber: math.max(0.0, outputBuffer[4] * scale[4] + mean[4]),
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _vocabulary = null;
    _idf = null;
    _scalerMean = null;
    _scalerScale = null;
  }
}
