# Plan: 006 score statistics

**Status:** Approved · **Date:** 2026-10-18 · **Spec:** [spec.md](spec.md) (Approved) · **Constitution:** v1.2.0

## Design

- **`lib/core/seeded_random.dart`** (new, pure Dart): a small, **specified** pseudo-random generator, SplitMix64. Its output is fixed by its definition on every OS and every Dart version. `dart:math`'s `Random(seed)` doesn't promise its sequence won't change between SDK releases. The generator is shared with feature 005's sampler.
- **`lib/core/statistics.dart`** (new):
  - `median(List<double>)`;
  - `sampleStdDev(List<double>)`, with n − 1;
  - `bootstrapStd(List<double>, {resamples = 1000, seed = 0})`, where each resample is `clip(mean, 0, 1)` and the result is the population standard deviation, like `np.std` in simple-evals.
  - Each returns `null` for too few values.
- **`RunSummary`** gains `medianScore`, `scoreStdDev` and `bootstrapStd`, computed lazily from the scored rows. For 5,000 conversations that's 5 million draws, a few tens of milliseconds, so no isolate is needed.
- **UI:** three new tiles in the run detail, each with a hover tooltip explaining it, and the run-score tile reads "0.463 ± 0.031".

## Tests (written first)

- **Hand-computed values:** odd and even medians, a known standard deviation, and fewer than 2 values (null).
- **Golden values:** median and sample standard deviation on the reference run's 10 real scores, computed with Python's `statistics` module (fixture `scoring_golden.json` → `statistics`).
- **Bootstrap:** deterministic (same seed, same value); equal scores give 0; for many i.i.d. values it's close to stdev/√n.
- **SplitMix64:** the first outputs for seed 0 match the published reference sequence.
- **Widget:** the tiles and "±" are shown, and "–" for runs with a single scored conversation.

## Constitution check

| Article | Result |
|---|---|
| II Scoring fidelity | ✅ The run score is unchanged. The bootstrap method follows simple-evals |
| VI, VII | ✅ Pure-Dart core, test-first |
| IX, X | ✅ No packages. Only what the spec asks |

**Complexity Tracking:** none.
