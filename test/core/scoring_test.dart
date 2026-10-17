// US2: scores follow HealthBench exactly (spec 002 FR-010, healthbench.md §5).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart';
import 'package:healthbench/core/grading.dart';
import 'package:healthbench/core/scoring.dart';

Grade grade(int points, {required bool met}) => Grade(
  criterion: Criterion(text: 'c', points: points, tags: const []),
  criteriaMet: met,
  explanation: '',
);

void main() {
  group('conversationScore', () {
    test('met points over positive points', () {
      // earned 5 + 3 = 8 of possible 5 + 3 + 2 = 10
      final grades = [
        grade(5, met: true),
        grade(3, met: true),
        grade(2, met: false),
      ];
      expect(conversationScore(grades), closeTo(0.8, 1e-12));
    });

    test('a met negative criterion subtracts (penalty)', () {
      // earned 5 - 10 = -5 of possible 5 → -1.0, not clipped
      final grades = [grade(5, met: true), grade(-10, met: true)];
      expect(conversationScore(grades), closeTo(-1.0, 1e-12));
    });

    test('an avoided negative criterion costs nothing', () {
      final grades = [grade(4, met: true), grade(-6, met: false)];
      expect(conversationScore(grades), closeTo(1.0, 1e-12));
    });

    test('no positive criteria → no score', () {
      expect(conversationScore([grade(-3, met: false)]), isNull);
      expect(conversationScore([grade(0, met: true)]), isNull);
      expect(conversationScore(const []), isNull);
    });
  });

  group('runScore', () {
    test('mean of conversation scores, ignoring those without a score', () {
      expect(runScore([0.5, null, 1.0]), closeTo(0.75, 1e-12));
    });

    test('clipped to 0–1', () {
      expect(runScore([-1.0, -0.5]), 0.0);
      expect(runScore([1.0, 1.0]), 1.0);
    });

    test('0 when nothing has a score (as calculate_score)', () {
      expect(runScore(const []), 0.0);
      expect(runScore([null]), 0.0);
    });
  });

  test('outcome labels', () {
    expect(outcomeOf(grade(5, met: true)), CriterionOutcome.earned);
    expect(outcomeOf(grade(5, met: false)), CriterionOutcome.missed);
    expect(outcomeOf(grade(-5, met: true)), CriterionOutcome.penalty);
    expect(outcomeOf(grade(-5, met: false)), CriterionOutcome.avoided);
  });

  test('matches the reference toolkit on its real 10-conversation run', () {
    final golden = jsonDecode(
      File('test/fixtures/scoring_golden.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final scores = <double?>[];
    for (final c in golden['conversations']! as List<Object?>) {
      final conversation = c! as Map<String, Object?>;
      final grades = [
        for (final r
            in (conversation['rubrics']! as List<Object?>)
                .cast<Map<String, Object?>>())
          grade(r['points']! as int, met: r['criteria_met']! as bool),
      ];
      final score = conversationScore(grades);
      final expected = conversation['score'] as num?;
      expect(score, expected == null ? isNull : closeTo(expected, 1e-12));
      scores.add(score);
    }
    expect(
      runScore(scores),
      closeTo((golden['runScore']! as num).toDouble(), 1e-12),
    );
  });
}
