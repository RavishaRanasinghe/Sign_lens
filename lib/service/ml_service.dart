import 'dart:math';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/prediction.dart';

class MLService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  List<String> get labels => List.unmodifiable(_labels);

  /// Load TFLite model + labels from assets.
  /// The model takes 63 floats (21 hand landmarks × x,y,z) and outputs
  /// a probability distribution over gesture classes.
  Future<void> init() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/hand_gesture.tflite',
        options: options,
      );

      final raw = await rootBundle.loadString('assets/models/labels.txt');
      _labels = raw
          .trim()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  /// Classify 63 landmark floats into a gesture Prediction.
  Prediction classify(List<double> rawLandmarks) {
    if (!_isInitialized || _interpreter == null) return Prediction.empty();
    if (rawLandmarks.length < 63) return Prediction.empty();

    final normalized = _normalizeLandmarks(rawLandmarks);

    // Input shape: [1, 63]
    final input = [normalized];
    final outputBuffer = List.generate(1, (_) => List.filled(_labels.length, 0.0));

    _interpreter!.run(input, outputBuffer);

    final scores = outputBuffer[0];
    final maxScore = scores.reduce(max);
    final maxIdx = scores.indexOf(maxScore);

    return Prediction(
      label: maxIdx < _labels.length ? _labels[maxIdx] : 'nothing',
      confidence: maxScore,
      timestamp: DateTime.now(),
      landmarks: rawLandmarks,
    );
  }

  /// Normalize landmarks relative to wrist (landmark 0) and scale to [-1,1]
  /// so the classification is position-invariant on screen.
  List<double> _normalizeLandmarks(List<double> raw) {
    final wx = raw[0], wy = raw[1], wz = raw[2];

    final shifted = List<double>.generate(63, (i) {
      final c = i % 3;
      if (c == 0) return raw[i] - wx;
      if (c == 1) return raw[i] - wy;
      return raw[i] - wz;
    });

    final maxVal = shifted.map((v) => v.abs()).reduce(max);
    if (maxVal == 0) return shifted;
    return shifted.map((v) => v / maxVal).toList();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}