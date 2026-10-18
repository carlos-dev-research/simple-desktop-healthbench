/// Summary statistics of conversation scores (spec 006).
library;

import 'dart:math' as math;

import 'seeded_random.dart';

/// The median, or null for no values. For an even count, the mean of the
/// two middle values (FR-001).
double? median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

double _mean(List<double> values) =>
    values.fold(0.0, (sum, v) => sum + v) / values.length;

/// Sample standard deviation (n − 1), or null for fewer than 2 values
/// (FR-002).
double? sampleStdDev(List<double> values) {
  if (values.length < 2) return null;
  final mean = _mean(values);
  final squares = values.fold(0.0, (sum, v) => sum + (v - mean) * (v - mean));
  return math.sqrt(squares / (values.length - 1));
}

/// Population standard deviation, as numpy's `np.std`.
double _populationStdDev(List<double> values) {
  final mean = _mean(values);
  final squares = values.fold(0.0, (sum, v) => sum + (v - mean) * (v - mean));
  return math.sqrt(squares / values.length);
}

/// Bootstrap standard deviation of the run score, as simple-evals'
/// `bootstrap_std`: [resamples] resamples with replacement, each scored as
/// `clip(mean, 0, 1)`; the result is their population standard deviation.
/// Deterministic for a given [seed] (FR-003). Null for fewer than 2 values.
double? bootstrapStd(
  List<double> scores, {
  int resamples = 1000,
  int seed = 0,
}) {
  final n = scores.length;
  if (n < 2) return null;
  final rng = SplitMix64(seed);
  final means = List<double>.generate(resamples, (_) {
    var total = 0.0;
    for (var i = 0; i < n; i++) {
      total += scores[rng.nextIntBelow(n)];
    }
    return (total / n).clamp(0.0, 1.0);
  });
  return _populationStdDev(means);
}
