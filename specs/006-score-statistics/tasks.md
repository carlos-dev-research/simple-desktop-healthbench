# Tasks: 006 score statistics

**Status:** Draft, pending approval · **Plan:** [plan.md](plan.md)

- [ ] T001 Tests first: `test/core/statistics_test.dart` (hand-computed, golden from Python, bootstrap determinism and properties) and `test/core/seeded_random_test.dart` (the SplitMix64 reference sequence)
- [ ] T002 Implement `lib/core/seeded_random.dart` and `lib/core/statistics.dart`. T001 passes
- [ ] T003 `RunSummary`: `medianScore`, `scoreStdDev`, `bootstrapStd`, with a test in `run_summary_test`
- [ ] T004 Run detail: three tiles with tooltips, and "± bootstrap std" on the run score. Widget test
- [ ] T005 Checks, commit, CI
