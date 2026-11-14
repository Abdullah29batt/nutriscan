import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteService {
  Interpreter? _interpreter;
  List<String>? _classNames;

  bool get isReady => _interpreter != null && _classNames != null;

  Future<void> initialize() async {
    if (isReady) return;
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/food_model.tflite',
        options: options,
      );
      final jsonStr =
          await rootBundle.loadString('assets/class_names_filtered.json');
      _classNames = List<String>.from(json.decode(jsonStr) as List);
    } catch (e) {
      _interpreter = null;
      _classNames = null;
      throw Exception('TFLite init failed: $e');
    }
  }

  /// Classify [imageFile] and return the top-1 prediction.
  Future<Map<String, dynamic>> classify(File imageFile) async {
    if (!isReady) await initialize();
    final interpreter = _interpreter!;
    final classNames = _classNames!;

    // Read input shape from the model — [1, 224, 224, 3]
    final inputShape = interpreter.getInputTensor(0).shape;
    final inputH = inputShape[1];
    final inputW = inputShape[2];
    final numClasses = classNames.length; // 108

    // ── Decode & resize ────────────────────────────────────────────────────
    final rawBytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) throw Exception('Could not decode image');
    final resized = img.copyResize(decoded, width: inputW, height: inputH);

    // ── Build input buffer ─────────────────────────────────────────────────
    final inputBuffer = Float32List(inputH * inputW * 3);
    int idx = 0;
    for (int y = 0; y < inputH; y++) {
      for (int x = 0; x < inputW; x++) {
        final p = resized.getPixel(x, y);
        // EfficientNetV2M preprocessing: [0,255] → [-1, 1]
        // Applied here because the model was exported without the built-in
        // Rescaling layer (include_preprocessing=False) to avoid SELECT_TF_OPS.
        inputBuffer[idx++] = (p.r.toDouble() / 127.5) - 1.0;
        inputBuffer[idx++] = (p.g.toDouble() / 127.5) - 1.0;
        inputBuffer[idx++] = (p.b.toDouble() / 127.5) - 1.0;
      }
    }

    // ── Run inference ──────────────────────────────────────────────────────
    // tflite_flutter 0.12.x treats any List (including Float32List) as a
    // nested structure and tries to reshape it, which causes a RangeError for
    // both the [1,224,224,3] input and [1,108] output.
    // Passing Uint8List for input and ByteBuffer for output bypasses all shape
    // checks (confirmed in getInputShapeIfDifferent / copyTo source) and does
    // a direct byte-level copy — no reshape, no error.
    final outputBuffer = Float32List(numClasses);
    interpreter.run(
      inputBuffer.buffer.asUint8List(), // skip input shape-check
      outputBuffer.buffer,              // skip output shape-check
    );

    // ── Extract top-1 ─────────────────────────────────────────────────────
    final indices = List<int>.generate(numClasses, (i) => i)
      ..sort((a, b) => outputBuffer[b].compareTo(outputBuffer[a]));

    final top1 = indices.take(1).map((i) {
      return <String, dynamic>{
        'label': classNames[i],
        'display_name': _formatLabel(classNames[i]),
        'confidence': outputBuffer[i].clamp(0.0, 1.0),
      };
    }).toList();

    return {
      'food_name': top1.first['display_name'],
      'confidence': top1.first['confidence'],
      'predictions': top1,
      'source': 'on-device',
    };
  }

  String _formatLabel(String label) => label
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _classNames = null;
  }
}
