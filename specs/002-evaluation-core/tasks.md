# Tasks: 002 evaluation core

**Status:** Done (owner sign-off 2026-10-18) · **Plan:** [plan.md](plan.md)

Each module is done test-first: write the test, see it fail, then implement. Commit messages start with `002: Txxx`.

## Phase 1: Setup
- [x] T001 Add the `http` and `crypto` dependencies (dart.dev). `pub get`, analyze clean *(R1, R8)*
- [x] T002 Golden fixtures generated from the reference toolkit: `test/fixtures/grader_prompt_golden.json`, `scoring_golden.json` and `json_extract_golden.json` *(Art. II)*
- [x] T003 `test/support/fake_openai_server.dart` (scripted local endpoint that records requests) and `test/support/fixtures.dart` (dataset and run-file builders)

## Phase 2: Scoring and grader-prompt text (US2, US3)
- [x] T004 [P] [US2] `test/core/scoring_test.dart`: hand-computed cases, the reference's real-run golden, the outcome labels, clipping and the no-positive case *(FR-010)*
- [x] T005 [P] [US3] `test/core/grader_prompt_test.dart`: matches the golden, single-pass filling, stable SHA-256 *(FR-009, R3)*
- [x] T006 [P] [US3] `test/core/grading_test.dart` (extraction part): matches the reference golden for every case, plus control characters inside strings *(FR-006, R4)*
- [x] T007 Implement `lib/core/scoring.dart`, `lib/core/grader_prompt.dart` and `extractFirstJsonObject` in `lib/core/grading.dart`. T004–T006 pass

## Phase 3: Settings and dataset (US1)
- [x] T008 [P] [US1] `test/core/settings_test.dart`: base-URL rules (R9), effort parsing, the key never appears in `toString`
- [x] T009 [P] [US1] `test/core/dataset_test.dart`: valid file, encoded criteria, missing tags, bad line → line number, duplicate ids, limit, blank lines, size limit *(FR-001–FR-003)*
- [x] T010 Implement `lib/core/settings.dart` and `lib/core/dataset.dart` (parsing in an isolate). T008 and T009 pass

## Phase 4: Chat client (US3, FR-004–FR-008)
- [x] T011 [US3] `test/core/chat_client_test.dart`:
  - request bodies (effort included or left out, response format, temperature);
  - the outcome table, retries 408/409/429/5xx, retry-after headers, x-should-retry, no retry for 401/403/404;
  - timeout, connection error, oversized body, empty reply, key redaction.
- [x] T012 Implement `lib/core/chat_client.dart`. T011 passes

## Phase 5: Evaluate one conversation (US3)
- [x] T013 [US3] `test/core/grading_test.dart` (evaluation part): the reply goes to the test model with the messages unchanged; one grader call per criterion with the filled prompt; `criteria_met` given as a string; invalid answer → failure; `onCriterion` callbacks *(FR-006, FR-009)*
- [x] T014 Implement `evaluateConversation` and `Grade`/`GradedConversation`. T013 passes

## Phase 6: Run file (US6, FR-017–FR-020)
- [x] T015 [US6] `test/core/run_file_test.dart`: write then read back; each of RF-1 to RF-9 rejected with a reason; truncated last line ignored; derived status including interrupted; scores recomputed
- [x] T016 Implement `lib/core/run_file.dart`. T015 passes

## Phase 7: Runner (US4, US5)
- [x] T017 [US4] `test/core/runner_test.dart` (run): file name and header, progress events, append before the next conversation, retries then skip, fatal errors stop the run, 5 failures in a row, completed score, nothing graded → no file
- [x] T018 [US5] `test/core/runner_test.dart` (stop and resume): stop after the current conversation; resume only the missing ones, including failed; key required; dataset changed → refused; truncated tail repaired; completed → refused; already active → refused
- [x] T019 Implement `lib/core/runner.dart`. T017 and T018 pass

## Phase 8: Security and platform
- [x] T020 [P] `test/core/no_secrets_test.dart`: a full fake run where the server echoes the key; the key appears in no file, progress report or error *(FR-008)*
- [x] T021 [P] `integration_test/network.dart` (run through `all_test.dart`, R18): the core client reaches a local endpoint from inside the sandboxed app *(R15, carries 001 US3-3)*

## Phase 9: Developer script, docs and verification
- [x] T022 `tool/try_run.dart`: `--count-only`, a run, `--resume` and `--validate`; key from `HEALTHBENCH_API_KEY`; output in `build/try_runs/` *(R16)*
- [x] T023 Docs: update README (the core and the dev script), CLAUDE.md status and healthbench.md §6 (link to the run-file contract)
- [x] T024 Full local checks: format, analyze, tests, integration tests. Push, then CI green on all three OSes
- [x] T025 Quickstart Q1 and Q5–Q6 locally (Q2–Q4 need the owner's key, done at the UI test). Record the results here

## Verification log

**2026-10-17 (Claude, local macOS + CI):**
- Golden fixtures from the reference toolkit match: the filled prompt is byte-identical, scores match the reference's real run (0.5731387613150002), and extraction matches on all cases.
- Q1: the real datasets read as 5000 / 3671 / 1000 conversations; the full oss_eval reads in about 1 s.
- Q2: 5 real oss_eval conversations against a local stand-in endpoint gave a valid run file of 8 lines.
- Q5: the API key appears 0 times. Q6: `--validate` says valid, and a tampered line is rejected as "line 4 … criteriaMet".
- Resuming a completed run is refused ("nothing left").
- The suite passes: 125 tests at 002, 3 consecutive runs. Integration tests pass inside the sandboxed app.
- CI is green on macOS, Windows and Linux. One Windows-only test fix: a refused loopback connection takes about 2 s on Windows.

**Pending (owner, with a real key):** Q2–Q4 against Groq. These are part of the 003 UI test (U5, U9, U10, U12).

## Owner sign-off (2026-10-18)

The owner signed off and closed this feature on 2026-10-18. The automated checks pass in CI on macOS, Windows and Linux. The manual checks in the quickstart were not recorded here as performed; they stay available as a checklist.
