# Tasks: 006 score statistics

**Status:** Approved · Done (owner check: open any run) · **Plan:** [plan.md](plan.md)

- [x] T001 Tests first: `test/core/statistics_test.dart` (hand-computed, golden from Python, bootstrap determinism and properties) and `test/core/seeded_random_test.dart` (the SplitMix64 reference sequence)
- [x] T002 Implement `lib/core/seeded_random.dart` and `lib/core/statistics.dart`. T001 passes
- [x] T003 `RunSummary`: `medianScore`, `scoreStdDev`, `bootstrapStd`, with a test in `run_summary_test`
- [x] T004 Run detail: three tiles with tooltips, and "± bootstrap std" on the run score. Widget test
- [x] T005 Checks, commit, CI
