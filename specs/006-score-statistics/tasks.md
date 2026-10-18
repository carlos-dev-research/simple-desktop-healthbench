# Tasks: 006 score statistics

**Status:** Done (owner sign-off 2026-10-18) · **Plan:** [plan.md](plan.md)

- [x] T001 Tests first: `test/core/statistics_test.dart` (hand-computed, golden from Python, bootstrap determinism and properties) and `test/core/seeded_random_test.dart` (the SplitMix64 reference sequence)
- [x] T002 Implement `lib/core/seeded_random.dart` and `lib/core/statistics.dart`. T001 passes
- [x] T003 `RunSummary`: `medianScore`, `scoreStdDev`, `bootstrapStd`, with a test in `run_summary_test`
- [x] T004 Run detail: three tiles with tooltips, and "± bootstrap std" on the run score. Widget test
- [x] T005 Checks, commit, CI

## Owner sign-off (2026-10-18)

The owner signed off and closed this feature on 2026-10-18. The automated checks pass in CI on macOS, Windows and Linux. The owner then tested the v0.2.0 release app with a real endpoint (`openai/gpt-oss-20b` on Groq, as model and grader): two 50-conversation runs completed, on HealthBench Consensus (score 0.880) and HealthBench Hard (score 0.201). Their run files are in [results/](../../results/). The quickstart rows were not ticked one by one; it stays available as a checklist.
