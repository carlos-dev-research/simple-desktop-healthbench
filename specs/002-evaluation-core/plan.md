# Plan: 002 evaluation core

**Status:** Approved (delegated, see below) · **Date:** 2026-10-17 · **Spec:** [spec.md](spec.md) (Approved) · **Constitution:** v1.0.0

## Technical context

| Item | Choice |
|---|---|
| Language | Pure Dart in `lib/core/`. No Flutter, `dart:ui` or Riverpod imports (rule PR-1) |
| New dependencies | `http` ^1.6.0 and `crypto` ^3.0.7, both **dart.dev first-party** (Article IX). No dev dependencies beyond the SDK |
| Concurrency | One conversation at a time (FR-014). The dataset is parsed with `Isolate.run` (NFR-003) |
| Storage | Append-only JSONL run file (contracts/run-file.md), with a flush after each line |
| Network | Our own OpenAI-compatible client (contracts/chat-completions.md) |
| Tests | Unit tests with `MockClient`, plus a real local fake server (`dart:io` `HttpServer` on 127.0.0.1) for the run-loop, retry and timeout tests. One integration test inside the sandboxed macOS app |

Research: [research.md](research.md) · Contracts: [run-file](contracts/run-file.md), [chat-completions](contracts/chat-completions.md), [core-api](contracts/core-api.md) · [data-model.md](data-model.md) · [quickstart.md](quickstart.md)

## Constitution check

| Article | Result | Notes |
|---|---|---|
| I Spec first | ✅ | Approved spec. This plan is pending review |
| II Scoring fidelity | ✅ | Formulas from healthbench.md §5, tested with hand-computed fixtures. Same prompt and parameters as the reference |
| III Privacy | ✅ | Key held in memory only. `toString` redacts it, error messages are scrubbed (FR-008), and base URLs with credentials are rejected (R9). A test greps every run file the suite writes for the key |
| IV Untrusted content | ✅ | Size limits (R12). Strict run-file validation. Model text is stored as-is and rendered later by the UI |
| V Run-file integrity | ✅ | Append-only, flushed per line, truncated last line handled, full validation, timestamp name |
| VI Architecture | ✅ | Everything lives in `lib/core/`. Hand-written JSON. No wrappers beyond the one needed client |
| VII Testing | ✅ | Test-first per module. No real API in tests. A fake server checks retries, timeouts and the stop rules |
| VIII Cross-platform | ✅ | Pure Dart plus `dart:io` files and sockets, the same on all three OSes. CI runs it all |
| IX Dependencies | ✅ | Only first-party dart.dev packages. The justification is R1 (http) and R8 (crypto) |
| X Simplicity | ✅ | No breakdowns, no parallelism (spec). The dev script is the only extra (S2) |
| XI Toolchain | ✅ | No new tools |
| XII Workflow | ✅ | Commits to `main` with task IDs |

**Complexity Tracking:** `tool/try_run.dart` is a developer-only script outside the app (see S2). It's justified because there's no other way to check 002 against a real endpoint before the UI exists.

## Project structure (new in 002)

```
lib/core/
  settings.dart           # ReasoningEffort, ModelSettings, ConnectionSettings, ClientOptions
  dataset.dart            # Message, Criterion, Conversation, Dataset, readDataset
  chat_client.dart        # ChatClient, ChatError hierarchy, retry/backoff, key redaction
  grader_prompt.dart      # GRADER.md text, id, sha256, single-pass fill, conversation → text
  grading.dart            # extractFirstJsonObject, Grade, GradedConversation, evaluateConversation
  scoring.dart            # outcomeOf, conversationScore, runScore
  run_file.dart           # run-file names, line encoding, writer (append + flush), reader/validator
  runner.dart             # EvaluationRun start/resume, progress stream, stop, failure policy
test/core/
  settings_test.dart  dataset_test.dart  chat_client_test.dart  grader_prompt_test.dart
  grading_test.dart  scoring_test.dart  run_file_test.dart  runner_test.dart
  no_secrets_test.dart                       # FR-008 across everything the suite writes
test/support/
  fake_openai_server.dart                    # scripted local endpoint (status, body, delay)
  fixtures.dart                              # small dataset lines and run files, valid and invalid
integration_test/network.dart                # R15: an HTTP call from inside the sandboxed app (run via all_test.dart, R18)
tool/try_run.dart                            # S2: developer-only real-endpoint runner
```

## Design highlights

1. **The client** (contract) uses `http.Client`, which can be injected. Timeouts come from `Future.timeout`, and the retry loop follows R2. `ChatError` is a sealed class, and `isFatal` drives the runner.
2. **The grader** ports `grade_prompt` and `grade` exactly (R3–R5). `onCriterion` feeds the progress report.
3. **The run file:**
   - A writer opens the file with `FileMode.append`, writes the line plus `\n`, then calls `flush()`.
   - The reader streams lines, validates RF-1 to RF-9, recomputes the scores, and derives the status.
4. **The runner:**
   - It creates a name that doesn't collide, then writes the header and a `running` status.
   - It evaluates the conversations not done yet, in index order:
     - success → append the line and update the progress;
     - fatal error → `failed`;
     - other error → count it, keep the redacted message (last 10), and fail the run after 5 in a row.
   - `stop()` sets a flag that is checked before each conversation.
   - At the end it appends the final status. If nothing was ever graded, it deletes the file.
   - `resume` re-reads and validates the file, checks that the dataset's SHA-256 matches, truncates an incomplete last line, and appends `running`.
5. **Active-run registry:** a static set of normalised paths (R14).

## Implementation phases (tasks.md will detail them)

1. **Setup:** dependencies, `test/support/` (the fake server and fixtures).
2. **Scoring and grading text helpers (US2, US3):** tests first, then `scoring.dart`, `grader_prompt.dart` and `extractFirstJsonObject`.
3. **Dataset (US1):** tests first, then `dataset.dart`.
4. **Client (US3, FR-004 to FR-008):** tests first with `MockClient` and the fake server, then `chat_client.dart`.
5. **Evaluate one conversation (US3):** tests first, then `evaluateConversation`.
6. **Run file (US6, FR-017 to FR-020):** tests first (valid and invalid fixtures, truncated last line), then `run_file.dart`.
7. **Runner (US4, US5):** tests first against the fake server (progress, retries, fatal errors, 5 failures in a row, stop, resume, dataset changed, nothing graded), then `runner.dart`.
8. **Security and platform:** `no_secrets_test`, `integration_test/network.dart` (macOS locally, all OSes in CI).
9. **Dev script and verification:** `tool/try_run.dart`, quickstart Q1–Q6 against Groq with your key, docs, CI green.

## Delegation (2026-10-17)

The project owner delegated **all technical decisions until their first hands-on UI test** ("make full technical development decisions until the first UI test by me, use the reference documents"). Plans and task lists for 002 and 003 are approved under this delegation. Decisions are recorded here and in research.md. The owner reviews everything at the UI test.

## Spec issues found during planning (resolved under delegation)

- **S1. 001's outgoing-network check moves on again.** Spec 001 (US3-3 amendment) said the real outgoing request would be checked in 002. 002 has no UI, so it can't run inside the **release** app.
  - **Proposal:** 002 adds an integration test that makes a real HTTP request from **inside the sandboxed debug app**, to a local fake endpoint (R15). This proves the network permission works under the sandbox.
  - The **release-build** check against a real endpoint becomes part of 003's quickstart.
  - **Decision: accepted.** The note in spec 001 is updated.
- **S2. Developer script `tool/try_run.dart`** (R16). A small command-line runner outside the app, so you can try 002 against a real endpoint (Groq) before the UI exists:
  - It reads the key from the `HEALTHBENCH_API_KEY` environment variable and never stores it.
  - It writes runs to `build/try_runs/`, which is git-ignored.
  - It doesn't ship in the app.

  It's similar to the reference's `eval.py`. **Decision: keep it.**
