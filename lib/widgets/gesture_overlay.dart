import 'package:flutter/material.dart';

/// Draws the 21 MediaPipe hand landmarks and skeleton connections
/// on top of the camera preview using a CustomPainter.
class GestureOverlay extends StatelessWidget {
  final List<double> landmarks; // 63 floats [x,y,z per landmark]
  final Size imageSize;
  final bool isFrontCamera;

  const GestureOverlay({
    super.key,
    required this.landmarks,
    required this.imageSize,
    this.isFrontCamera = true,
  });

  @override
  Widget build(BuildContext context) {
    if (landmarks.length < 63) return const SizedBox.expand();
    return CustomPaint(
      painter: _HandPainter(
        landmarks: landmarks,
        imageSize: imageSize,
        isFrontCamera: isFrontCamera,
      ),
      size: Size.infinite,
    );
  }
}

class _HandPainter extends CustomPainter {
  final List<double> landmarks;
  final Size imageSize;
  final bool isFrontCamera;

  _HandPainter({
    required this.landmarks,
    required this.imageSize,
    required this.isFrontCamera,
  });

  // MediaPipe hand skeleton connections
  static const List<List<int>> _connections = [
    // Thumb
    [0, 1], [1, 2], [2, 3], [3, 4],
    // Index
    [0, 5], [5, 6], [6, 7], [7, 8],
    // Middle
    [0, 9], [9, 10], [10, 11], [11, 12],
    // Ring
    [0, 13], [13, 14], [14, 15], [15, 16],
    // Pinky
    [0, 17], [17, 18], [18, 19], [19, 20],
    // Palm
    [5, 9], [9, 13], [13, 17],
  ];

  // Fingertip indices for special highlight
  static const Set<int> _fingertips = {4, 8, 12, 16, 20};

  @override
  void paint(Canvas canvas, Size size) {
    final points = _getLandmarkPoints(size);
    _drawConnections(canvas, points);
    _drawDots(canvas, points);
  }

  /// Convert normalized [0..1] landmark coords to canvas pixels.
  List<Offset> _getLandmarkPoints(Size canvasSize) {
    final points = <Offset>[];
    for (int i = 0; i < 21; i++) {
      double x = landmarks[i * 3];
      double y = landmarks[i * 3 + 1];

      // Mirror x for front camera (selfie mirror)
      if (isFrontCamera) x = 1.0 - x;

      // Scale to canvas
      points.add(Offset(x * canvasSize.width, y * canvasSize.height));
    }
    return points;
  }

  void _drawConnections(Canvas canvas, List<Offset> points) {
    final linePaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final conn in _connections) {
      canvas.drawLine(points[conn[0]], points[conn[1]], linePaint);
    }
  }

  void _drawDots(Canvas canvas, List<Offset> points) {
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      final isTip = _fingertips.contains(i);
      final isWrist = i == 0;

      dotPaint.color = isWrist
          ? const Color(0xFFFF6B35)
          : isTip
              ? const Color(0xFF00E5FF)
              : const Color(0xFF7C4DFF).withOpacity(0.9);

      final radius = isWrist ? 6.0 : isTip ? 5.5 : 4.0;

      canvas.drawCircle(points[i], radius, dotPaint);
      canvas.drawCircle(points[i], radius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(_HandPainter old) =>
      old.landmarks != landmarks || old.imageSize != imageSize;
}