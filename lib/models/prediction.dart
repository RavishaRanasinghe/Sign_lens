import 'package:flutter/foundation.dart';

@immutable
class Prediction {
  final String label;
  final double confidence;
  final DateTime timestamp;
  final List<double> landmarks;

  const Prediction({
    required this.label,
    required this.confidence,
    required this.timestamp,
    required this.landmarks,
  });

  bool get isValid => confidence >= 0.75 && label != 'nothing';

  bool get isSpecial => label == 'space' || label == 'del';

  String get displayLabel {
    switch (label) {
      case 'space':
        return '␣';
      case 'del':
        return '⌫';
      case 'nothing':
        return '–';
      default:
        return label;
    }
  }

  Prediction copyWith({
    String? label,
    double? confidence,
    DateTime? timestamp,
    List<double>? landmarks,
  }) {
    return Prediction(
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      timestamp: timestamp ?? this.timestamp,
      landmarks: landmarks ?? this.landmarks,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory Prediction.empty() => Prediction(
        label: 'nothing',
        confidence: 0.0,
        timestamp: DateTime.now(),
        landmarks: [],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Prediction &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          confidence == other.confidence;

  @override
  int get hashCode => label.hashCode ^ confidence.hashCode;

  @override
  String toString() =>
      'Prediction(label: $label, confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
}

class DetectionSession {
  final String id;
  final DateTime startTime;
  DateTime endTime;
  final List<Prediction> predictions;
  String builtSentence;

  DetectionSession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.predictions,
    required this.builtSentence,
  });

  factory DetectionSession.start() => DetectionSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        predictions: [],
        builtSentence: '',
      );

  Duration get duration => endTime.difference(startTime);

  int get letterCount =>
      predictions.where((p) => p.isValid && !p.isSpecial).length;

  Map<String, dynamic> toMap() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'sentence': builtSentence,
        'letterCount': letterCount,
        'predictionCount': predictions.length,
      };
}