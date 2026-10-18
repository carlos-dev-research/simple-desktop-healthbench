// Spec 006: median, standard deviation and bootstrap std of the run score;
// SplitMix64, the deterministic generator behind the bootstrap and 005's
// sampler. Golden values come from an independent Python implementation.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/seeded_random.dart';
import 'package:healthbench/core/statistics.dart';

Map<String, Object?> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

void main() {
  group('SplitMix64', () {
    test('matches the reference sequence for seed 0', () {
      final expected =
          (_json('test/fixtures/splitmix64_golden.json')['seed0_first4_signed']!
                  as List<Object?>)
              .cast<int>();
      final rng = SplitMix64(0);
      expect([for (var i = 0; i < 4; i++) rng.nextInt64()], expected);
    });

    test('unbiased bounded draws match the reference', () {
      final stats =
          _json('test/fixtures/scoring_golden.json')['statistics']!
              as Map<String, Object?>;
      final rng = SplitMix64(40);
      expect([
        for (var i = 0; i < 8; i++) rng.nextIntBelow(10),
      ], (stats['below_seed40_bound10_first8']! as List<Object?>).cast<int>());
    });

    test('bounded draws stay in range and doubles in [0, 1)', () {
      final rng = SplitMix64(7);
      for (var i = 0; i < 10000; i++) {
        expect(rng.nextIntBelow(3), inInclusiveRange(0, 2));
        final d = rng.nextDouble();
        expect(d >= 0 && d < 1, isTrue);
      }
      expect(() => rng.nextIntBelow(0), throwsArgumentError);
    });
  });

  group('median and standard deviation', () {
    test('hand-computed', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 3, 2]), 2.5);
      expect(median(const []), isNull);
      // Values 2, 4, 4, 4, 5, 5, 7, 9: sample variance 32/7.
      expect(
        sampleStdDev([2, 4, 4, 4, 5, 5, 7, 9]),
        closeTo(math.sqrt(32 / 7), 1e-12),
      );
      expect(sampleStdDev([1]), isNull);
      expect(sampleStdDev(const []), isNull);
    });

    test('match Python statistics on the reference run', () {
      final golden = _json('test/fixtures/scoring_golden.json');
      final stats = golden['statistics']! as Map<String, Object?>;
      final scores = [
        for (final c
            in (golden['conversations']! as List<Object?>)
                .cast<Map<String, Object?>>())
          if (c['score'] case final num s) s.toDouble(),
      ];
      expect(
        median(scores),
        closeTo((stats['median']! as num).toDouble(), 1e-12),
      );
      expect(
        sampleStdDev(scores),
        closeTo((stats['stdevSample']! as num).toDouble(), 1e-12),
      );
    });
  });

  group('bootstrap std', () {
    test('matches the independent Python implementation exactly', () {
      final golden = _json('test/fixtures/scoring_golden.json');
      final stats = golden['statistics']! as Map<String, Object?>;
      final scores = [
        for (final c
            in (golden['conversations']! as List<Object?>)
                .cast<Map<String, Object?>>())
          if (c['score'] case final num s) s.toDouble(),
      ];
      expect(
        bootstrapStd(scores),
        closeTo((stats['bootstrapStd_seed0_1000']! as num).toDouble(), 1e-12),
      );
    });

    test('is deterministic, 0 for identical scores, null for fewer than 2', () {
      final values = [0.1, 0.5, 0.9, 0.4];
      expect(bootstrapStd(values), bootstrapStd(values));
      expect(
        bootstrapStd([0.6, 0.6, 0.6]),
        closeTo(0, 1e-12),
      ); // float rounding only
      expect(bootstrapStd([0.6]), isNull);
    });

    test('is close to stdev/sqrt(n) for many independent scores', () {
      final rng = SplitMix64(123);
      final values = [
        for (var i = 0; i < 2000; i++) 0.25 + 0.5 * rng.nextDouble(),
      ];
      final expected = sampleStdDev(values)! / math.sqrt(values.length);
      expect(bootstrapStd(values), closeTo(expected, expected * 0.1));
    });

    test('clips each resample score to 0–1 like the run score', () {
      // All conversation scores negative: every resample clips to 0.
      expect(bootstrapStd([-1.0, -0.5, -2.0]), 0);
    });
  });
}
