import 'package:flutter/material.dart';
import '../models/prediction.dart';

/// Floating banner shown at the bottom of the camera screen.
/// Displays the current gesture prediction, confidence, and hold timer.
class ResultBanner extends StatelessWidget {
  final Prediction prediction;
  final double holdProgress; // 0.0 – 1.0 for the hold-to-type timer
  final String currentSentence;
  final VoidCallback? onClear;

  const ResultBanner({
    super.key,
    required this.prediction,
    required this.holdProgress,
    required this.currentSentence,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sentence display
        if (currentSentence.isNotEmpty) _SentenceCard(sentence: currentSentence, onClear: onClear),
        const SizedBox(height: 10),
        // Prediction card
        _PredictionCard(prediction: prediction, holdProgress: holdProgress),
      ],
    );
  }
}

class _SentenceCard extends StatelessWidget {
  final String sentence;
  final VoidCallback? onClear;

  const _SentenceCard({required this.sentence, this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              sentence,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.clear_rounded, color: Colors.white54, size: 20),
            ),
        ],
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  final Prediction prediction;
  final double holdProgress;

  const _PredictionCard({required this.prediction, required this.holdProgress});

  Color get _confidenceColor {
    if (prediction.confidence >= 0.85) return const Color(0xFF00E676);
    if (prediction.confidence >= 0.65) return const Color(0xFFFFD740);
    return const Color(0xFFFF5252);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = prediction.isValid;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.black.withOpacity(0.82)
            : Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00E5FF).withOpacity(0.6)
              : Colors.white.withOpacity(0.1),
          width: isActive ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Big gesture letter
              Text(
                prediction.displayLabel,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white38,
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Confidence badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? _confidenceColor.withOpacity(0.15)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isActive
                          ? '${(prediction.confidence * 100).toStringAsFixed(0)}%'
                          : 'No hand',
                      style: TextStyle(
                        color: isActive ? _confidenceColor : Colors.white38,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Hold-to-type label
                  Text(
                    isActive
                        ? holdProgress > 0
                            ? 'Hold to type…'
                            : 'Gesture detected'
                        : 'Show hand to camera',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Hold-to-type progress bar
          if (isActive && holdProgress > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: holdProgress,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact chip used in the history screen
class PredictionChip extends StatelessWidget {
  final Prediction prediction;

  const PredictionChip({super.key, required this.prediction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            prediction.displayLabel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Text(
            '${(prediction.confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}