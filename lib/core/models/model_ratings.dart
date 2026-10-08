import 'model_catalogue.dart';

/// Shared product bands. These are held-out General-mode measurements on one
/// iPhone, not overall accuracy, Knowledge Base qualification or battery life.
abstract final class ModelRatingScale {
  static int quality(int passed, int total) {
    if (total <= 0 || passed < 0 || passed > total) {
      throw ArgumentError('Invalid task counts');
    }
    final percentage = 100 * passed / total;
    return percentage >= 95
        ? 5
        : percentage >= 85
        ? 4
        : percentage >= 75
        ? 3
        : percentage >= 60
        ? 2
        : 1;
  }

  static int speed(double seconds) {
    if (!seconds.isFinite || seconds < 0) {
      throw ArgumentError('Invalid completion time');
    }
    return seconds <= 2
        ? 5
        : seconds <= 5
        ? 4
        : seconds <= 10
        ? 3
        : seconds <= 20
        ? 2
        : 1;
  }

  static const explanation =
      '1–5 bars; higher is better. Held-out General-mode ratings on iPhone 15 Pro Max, not overall accuracy or Knowledge Base ratings. Quality includes following exact output-format instructions.\n\n'
      'Quality: full-task pass rate on the same 64 fresh fictional tasks, graded without knowing which model answered. 5: ≥95%; 4: ≥85%; 3: ≥75%; 2: ≥60%; 1: below 60%.\n\n'
      'Speed: median completion time including model preparation and generation. 5: ≤2 s; 4: ≤5 s; 3: ≤10 s; 2: ≤20 s; 1: slower. Missing completions leave speed unmeasured.\n\n'
      'Memory: lower additional peak memory is better, including system model services. 5: ≤0.5 GB; 4: ≤1 GB; 3: ≤2 GB; 2: ≤3 GB; 1: more. Download size is separate.\n\n'
      'Battery: lower additional whole-device drain in a matched one-request-per-minute workload is better. 5: ≤1 percentage point/hour; 4: ≤2; 3: ≤4; 2: ≤8; 1: more. Requires repeated matched idle comparisons and a gauge cross-check; this is not a battery-life prediction.\n\n'
      'Not measured means comparable evidence is missing, not a zero score.';
}

/// Summary of one complete matched development collection. Runtime failures
/// count against quality and withhold speed, rather than rewarding fast errors.
final class ModelRatings {
  // Frozen held-out paired report and blind grades:
  // docs/evaluation/model-ratings/heldout-v2-{results,grades}-2026-10-08.json.
  static const apple = ModelRatings(
    passed: 48,
    total: 64,
    completed: 64,
    medianSeconds: 1.8795,
  );
  static const qwen = ModelRatings(
    passed: 49,
    total: 64,
    completed: 64,
    medianSeconds: 3.9455,
  );

  static ModelRatings? forModel(String id) {
    if (id == ModelCatalogue.apple.id) return apple;
    if (id == ModelCatalogue.qwen.id) return qwen;
    return null;
  }

  const ModelRatings({
    required this.passed,
    required this.total,
    required this.completed,
    required this.medianSeconds,
  }) : assert(total > 0),
       assert(passed >= 0 && passed <= completed),
       assert(completed <= total),
       assert(medianSeconds >= 0 && medianSeconds < double.infinity);

  final int passed;
  final int total;
  final int completed;
  final double medianSeconds;

  int get quality => ModelRatingScale.quality(passed, total);
  int? get speed =>
      completed == total ? ModelRatingScale.speed(medianSeconds) : null;

  String get description =>
      'Held-out phone comparison · 8 October 2026\n\n'
      'Answer quality: $passed/$total held-out tasks passed ($quality/5). '
      'Graded without knowing which model answered, with an owner spot-check. This is not overall accuracy.\n\n'
      '${speed == null ? 'Speed: not rated; only $completed/$total responses completed.' : 'Speed: ${medianSeconds.toStringAsFixed(2)} seconds median (${speed!}/5), including model preparation and generation, excluding database/UI work and rests.'}\n\n'
      'Measured unplugged on iPhone 15 Pro Max, iOS 27.0 (24A437), with ten-second rests and a dark diagnostic screen. These scores do not establish sustained-use stability.\n\n'
      'Memory and battery: comparable measurements are not available.';
}
