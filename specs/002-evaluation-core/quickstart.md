# Quickstart: validating 002

Automated tests cover every acceptance scenario against fake endpoints. These manual
checks confirm behaviour against a **real** OpenAI-compatible endpoint, using the
developer script `tool/try_run.dart` (research R16, plan S2). Run them from the repo root.

Preparation:
- Put a HealthBench file in `healthbench/` (see the README → Dataset section).
- Set the key **in your shell only**: `export HEALTHBENCH_API_KEY=…`. Never put it in a file.

| # | Scenario | Steps | Expected |
|---|---|---|---|
| Q1 | US1 Read | `fvm dart run tool/try_run.dart --dataset healthbench/<file> --count-only` | Prints the conversation count (5000 for oss_eval) within 5 s |
| Q2 | US3/US4 Real run | `fvm dart run tool/try_run.dart --dataset healthbench/<file> --limit 3 --base-url https://api.groq.com/openai/v1 --model openai/gpt-oss-20b --grader openai/gpt-oss-20b --effort low` | Progress lines appear. The run file is in `build/try_runs/` with a header, a `running` status, 3 conversation lines and a `completed` status with a score in [0, 1] |
| Q3 | US5 Stop and continue | Run Q2 with `--limit 10`, press Ctrl-C once after 2 conversations, then rerun with `--resume build/try_runs/<file>` | The first session ends `stopped` after the current conversation. The resume grades only the remaining 8, and the final `graded` is 10 |
| Q4 | US4-5 Fatal error | Run Q2 with `HEALTHBENCH_API_KEY=wrong` | It stops immediately as `failed` (authentication), and **no run file is left** |
| Q5 | FR-008 No key | `grep -r "$HEALTHBENCH_API_KEY" build/try_runs/` | No matches |
| Q6 | US6 Validate | `fvm dart run tool/try_run.dart --validate build/try_runs/<file>` | "valid", with the status and score. Then edit one line by hand and run it again: rejected, naming that line |
