import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

typedef LandmarkCallback = void Function(List<double> landmarks);
typedef ErrorCallback = void Function(String error);

class CameraService {
  CameraController? _controller;
  HandLandmarkerPlugin? _plugin;
  StreamSubscription? _landmarkSub;

  bool _isProcessing = false;
  int _frameCount = 0;
  static const int _processEveryN = 6; // ~5fps on most devices

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Initialize camera (front-facing) and the hand landmark plugin.
  Future<void> init() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('No cameras found on device');

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420   // hand_landmarker expects YUV on Android
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();

    // hand_landmarker bundles its own model — no assets needed
    _plugin = HandLandmarkerPlugin.create(
      numHands: 1,
      minHandDetectionConfidence: 0.5,
      minHandPresenceConfidence: 0.5,
      minTrackingConfidence: 0.5,
    );
  }

  /// Start streaming and detecting landmarks.
  /// [onLandmarks] receives 63 floats [x0,y0,z0 … x20,y20,z20] per frame.
  void startStream({
    required LandmarkCallback onLandmarks,
    ErrorCallback? onError,
  }) {
    if (_controller == null || !isInitialized || _plugin == null) return;

    _frameCount = 0;

    // Subscribe to the plugin's landmark stream
    _landmarkSub = _plugin!.landmarkStream.listen(
      (List<Hand> hands) {
        if (hands.isEmpty) return;
        final landmarks = _extractLandmarks(hands.first);
        onLandmarks(landmarks);
      },
      onError: (e) => onError?.call(e.toString()),
    );

    // Feed camera frames into the plugin
    _controller!.startImageStream((CameraImage image) {
      _frameCount++;
      if (_frameCount % _processEveryN != 0) return;
      if (_isProcessing) return;
      _isProcessing = true;

      try {
        _plugin!.processImage(image);
      } catch (e) {
        onError?.call(e.toString());
      } finally {
        _isProcessing = false;
      }
    });
  }

  /// Stop the image stream and landmark subscription.
  Future<void> stopStream() async {
    await _landmarkSub?.cancel();
    _landmarkSub = null;
    if (_controller?.value.isStreamingImages ?? false) {
      await _controller!.stopImageStream();
    }
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    await stopStream();
    final cameras = await availableCameras();
    final current = _controller?.description;
    final next = cameras.firstWhere(
      (c) => c.lensDirection != current?.lensDirection,
      orElse: () => cameras.first,
    );
    await _controller?.dispose();
    _controller = CameraController(
      next,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    await _controller!.initialize();
  }

  /// Convert Hand landmarks to a flat list of 63 doubles.
  List<double> _extractLandmarks(Hand hand) {
    final result = <double>[];
    for (final lm in hand.landmarks) {
      result.add(lm.x);
      result.add(lm.y);
      result.add(lm.z);
    }
    while (result.length < 63) result.add(0.0);
    return result.sublist(0, 63);
  }

  Future<void> dispose() async {
    await stopStream();
    _plugin?.dispose();
    await _controller?.dispose();
    _controller = null;
  }
}