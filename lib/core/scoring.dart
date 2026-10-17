/// HealthBench scoring (healthbench.md §5; port of pygrader tools.py
/// get_score / calculate_score).
library;

import 'grading.dart';

/// How a graded criterion contributed to the score.
enum CriterionOutcome {
  /// Positive points, criterion met.
  earned,

  /// Positive points, criterion not met.
  missed,

  /// Negative points, criterion met (the undesirable behaviour happened).
  penalty,

  /// Negative points, criterion not met.
  avoided,
}

CriterionOutcome outcomeOf(Grade grade) {
  final negative = grade.criterion.points < 0;
  if (grade.criteriaMet) {
    return negative ? CriterionOutcome.penalty : CriterionOutcome.earned;
  }
  return negative ? CriterionOutcome.avoided : CriterionOutcome.missed;
}

/// Points earned (met criteria, negatives subtract) over the maximum positive
/// points. Not clipped. `null` when there are no positive points.
double? conversationScore(Iterable<Grade> grades) {
  var earned = 0;
  var possible = 0;
  for (final grade in grades) {
    final points = grade.criterion.points;
    if (grade.criteriaMet) earned += points;
    if (points > 0) possible += points;
  }
  return possible > 0 ? earned / possible : null;
}

/// Mean of the conversation scores that exist, clipped to [0, 1]; 0 if none.
double runScore(Iterable<double?> conversationScores) {
  final scores = conversationScores.whereType<double>().toList();
  if (scores.isEmpty) return 0;
  final mean = scores.reduce((a, b) => a + b) / scores.length;
  return mean.clamp(0.0, 1.0);
}
