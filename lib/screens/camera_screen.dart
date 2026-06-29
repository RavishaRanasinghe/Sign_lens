import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/prediction.dart';
import '../services/camera_service.dart';
import '../services/ml_service.dart';
import '../widgets/gesture_overlay.dart';
import '../widgets/result_banner.dart';
import 'history_screen.dart';

// ── Providers ──────────────────────────────────────────────────────────────

final predictionProvider = StateProvider<Prediction>((ref) => Prediction.empty());
final sentenceProvider = StateProvider<String>((ref) => '');
final landmarksProvider = StateProvider<List<double>>((ref) => []);
final holdProgressProvider = StateProvider<double>((ref) => 0.0);
final sessionsProvider = StateProvider<List<DetectionSession>>((ref) => []);

// ── Screen ─────────────────────────────────────────────────────────────────

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  final _cameraService = CameraService();
  final _mlService = MLService();

  bool _isInitialized = false;
  bool _isFrontCamera = true;
  String? _errorMessage;

  // Hold-to-type state
  static const Duration _holdDuration = Duration(milliseconds: 1500);
  Timer? _holdTimer;
  Timer? _progressTimer;
  String _lastStableGesture = '';
  double _holdProgress = 0.0;

  // Current session
  late DetectionSession _currentSession;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _currentSession = DetectionSession.start();
    _init();
  }

  Future<void> _init() async {
    try {
      await _mlService.init();
      await _cameraService.init();
      _startStream();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to initialize: $e\n\n'
            'Make sure hand_gesture.tflite is in assets/models/');
      }
    }
  }

  void _startStream() {
    _cameraService.startStream(
      onLandmarks: _onLandmarks,
      onError: (e) => debugPrint('Camera error: $e'),
    );
  }

  void _onLandmarks(List<double> landmarks) {
    if (!mounted) return;

    // Run classification
    final prediction = _mlService.classify(landmarks);

    // Update providers
    ref.read(landmarksProvider.notifier).state = landmarks;
    ref.read(predictionProvider.notifier).state = prediction;

    // Handle hold-to-type logic
    if (prediction.isValid) {
      _handleHoldToType(prediction);
    } else {
      _resetHold();
    }

    // Track in session
    _currentSession.predictions.add(prediction);
  }

  void _handleHoldToType(Prediction prediction) {
    if (prediction.label == _lastStableGesture) return;

    // New gesture detected — reset and start counting
    _resetHold();
    _lastStableGesture = prediction.label;

    // Progress animation (updates 30× per second)
    _holdProgress = 0.0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 33), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final progress = t.tick * 33 / _holdDuration.inMilliseconds;
      ref.read(holdProgressProvider.notifier).state = progress.clamp(0.0, 1.0);
    });

    // Commit the letter after hold duration
    _holdTimer = Timer(_holdDuration, () {
      if (!mounted) return;
      _commitGesture(prediction.label);
      _resetHold();
    });
  }

  void _commitGesture(String label) {
    HapticFeedback.mediumImpact();

    final current = ref.read(sentenceProvider);
    String updated;

    switch (label) {
      case 'space':
        updated = '$current ';
        break;
      case 'del':
        updated = current.isEmpty ? '' : current.substring(0, current.length - 1);
        break;
      case 'nothing':
        return;
      default:
        updated = '$current$label';
    }

    ref.read(sentenceProvider.notifier).state = updated;
    _currentSession.builtSentence = updated;
  }

  void _resetHold() {
    _holdTimer?.cancel();
    _progressTimer?.cancel();
    _holdTimer = null;
    _progressTimer = null;
    _lastStableGesture = '';
    _holdProgress = 0.0;
    if (mounted) {
      ref.read(holdProgressProvider.notifier).state = 0.0;
    }
  }

  Future<void> _switchCamera() async {
    await _cameraService.stopStream();
    await _cameraService.switchCamera();
    setState(() => _isFrontCamera = !_isFrontCamera);
    _startStream();
  }

  void _saveSession() {
    if (ref.read(sentenceProvider).isEmpty) return;
    _currentSession.endTime = DateTime.now();
    _currentSession.builtSentence = ref.read(sentenceProvider);

    final sessions = List<DetectionSession>.from(ref.read(sessionsProvider));
    sessions.insert(0, _currentSession);
    ref.read(sessionsProvider.notifier).state = sessions;

    _currentSession = DetectionSession.start();
    ref.read(sentenceProvider.notifier).state = '';
    ref.read(predictionProvider.notifier).state = Prediction.empty();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session saved to history'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _cameraService.stopStream();
    } else if (state == AppLifecycleState.resumed) {
      _startStream();
    }
  }

  @override
  void dispose() {
    _resetHold();
    _cameraService.dispose();
    _mlService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) return _ErrorView(message: _errorMessage!);
    if (!_isInitialized) return const _LoadingView();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera preview
          _CameraPreviewWidget(controller: _cameraService.controller!),

          // 2. Hand landmark overlay
          Consumer(builder: (ctx, ref, _) {
            final landmarks = ref.watch(landmarksProvider);
            return GestureOverlay(
              landmarks: landmarks,
              imageSize: Size(
                _cameraService.controller!.value.previewSize!.height,
                _cameraService.controller!.value.previewSize!.width,
              ),
              isFrontCamera: _isFrontCamera,
            );
          }),

          // 3. Top bar
          SafeArea(child: _TopBar(onHistory: _goToHistory, onSave: _saveSession)),

          // 4. Result banner (bottom)
          Positioned(
            left: 16,
            right: 16,
            bottom: 48,
            child: Consumer(builder: (ctx, ref, _) {
              final prediction = ref.watch(predictionProvider);
              final holdProgress = ref.watch(holdProgressProvider);
              final sentence = ref.watch(sentenceProvider);
              return ResultBanner(
                prediction: prediction,
                holdProgress: holdProgress,
                currentSentence: sentence,
                onClear: () {
                  ref.read(sentenceProvider.notifier).state = '';
                  _currentSession.builtSentence = '';
                },
              );
            }),
          ),

          // 5. Camera switch button
          Positioned(
            right: 20,
            top: MediaQuery.of(context).padding.top + 60,
            child: _CameraToggleButton(onTap: _switchCamera),
          ),
        ],
      ),
    );
  }

  void _goToHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _CameraPreviewWidget extends StatelessWidget {
  final CameraController controller;
  const _CameraPreviewWidget({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxWidth * controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
      );
    });
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onHistory;
  final VoidCallback onSave;

  const _TopBar({required this.onHistory, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // App title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sign_language, color: Color(0xFF00E5FF), size: 18),
                SizedBox(width: 6),
                Text(
                  'SignLens',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Save button
          _IconBtn(icon: Icons.save_outlined, onTap: onSave, tooltip: 'Save session'),
          const SizedBox(width: 8),
          // History button
          _IconBtn(icon: Icons.history, onTap: onHistory, tooltip: 'History'),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBtn({required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _CameraToggleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CameraToggleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
        child: const Icon(Icons.flip_camera_ios_outlined,
            color: Colors.white, size: 22),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00E5FF)),
            SizedBox(height: 20),
            Text('Loading model…',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 48),
              const SizedBox(height: 16),
              Text(message,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}