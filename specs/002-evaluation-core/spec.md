# Feature: Evaluation core

**Status:** Approved · **Date:** 2026-10-17 · **Constitution:** v1.0.0

## Summary

The building blocks that run a HealthBench evaluation, without any user
interface yet. They are ported from the reference toolkit (`pygrader`: dataset
records, generation and grading, scoring, run loop) and adapted to this app's
own run file:
- **Read** a HealthBench dataset.
- **Send** each conversation to a model under test, through any OpenAI-compatible endpoint.
- **Ask** a grader model, once per rubric criterion, whether the reply meets the criterion.
- **Score** the results exactly as HealthBench defines it.
- **Record** everything in one run file as the run progresses, so a run can be stopped and later continued where it left off.

The UI feature that follows (003) only presents these capabilities. Every
behaviour here can be verified by automated tests against a fake model
endpoint, with no paid API involved.

Domain reference: [docs/reference/healthbench.md](../../docs/reference/healthbench.md) §2–§5 and §7.
Run-file decisions: [flutter-desktop.md §2.2](../../docs/reference/flutter-desktop.md).

## User stories

### US1 (P1): Read a HealthBench dataset

As an **evaluator**, I want the app to read a HealthBench dataset file and tell
me how many conversations it has, so that I know what a run will cover.

Acceptance scenarios:
1. **Given** a valid HealthBench file, **when** it is read, **then** every conversation is available with its id, messages, rubric criteria (text, points, tags), example tags and optional ideal completion. The conversation count equals the number of non-empty lines.
2. **Given** a file where criteria are stored as encoded text instead of objects, or where tags or ideal-completion data are missing or empty, **when** it is read, **then** it is read the same as a normal file. Missing values count as empty.
3. **Given** a line that is not valid JSON or lacks required fields, **when** the file is read, **then** reading stops with a message naming the line number and the problem, and no partial dataset is used.
4. **Given** a limit N, **when** the dataset is read, **then** only the first N conversations are selected.

### US2 (P1): Score exactly like HealthBench

As an **evaluator**, I want scores computed with the official formulas, so that
my results mean the same as everyone else's HealthBench numbers.

Acceptance scenarios:
1. **Given** a graded conversation, **when** it is scored, **then** the score is the points of met criteria (negative points subtract) divided by the sum of positive points. It is **not** clipped, so it can be below 0.
2. **Given** a conversation with no positive-point criteria, **when** it is scored, **then** it has no score and is left out of the run score.
3. **Given** several scored conversations, **when** the run score is computed, **then** it is their mean, clipped to the range 0–1.
4. **Given** each graded criterion, **when** its outcome is shown, **then** it is labelled *earned* (positive, met), *missed* (positive, not met), *penalty* (negative, met) or *avoided* (negative, not met).
5. **Given** hand-computed examples, including negative points, penalties and no positive criteria, **when** they are scored, **then** the results match exactly.

### US3 (P1): Generate and grade one conversation

As an **evaluator**, I want each conversation answered by the model under test
and then judged criterion by criterion by the grader model, so that every
rubric item gets an explicit met/not-met decision with the grader's reasoning.

Acceptance scenarios:
1. **Given** a conversation and connection settings (base URL, API key, model under test, grader model, reasoning effort for each), **when** it is evaluated, **then** the model under test receives the conversation's messages unchanged and returns a reply.
2. **Given** that reply, **when** it is graded, **then** the grader is asked once per criterion, using the grader prompt filled with the conversation, the reply and the criterion. Each answer yields an explanation and a met/not-met flag.
3. **Given** a reasoning effort of *low*, *medium* or *high*, **when** a request is sent, **then** that effort is requested. **Given** *none*, **then** no effort is sent at all, so models without the option still work.
4. **Given** a grader answer that wraps the JSON in extra text, **when** it is read, **then** the first valid JSON object in the text is used. **Given** an answer with no valid JSON object, **then** grading that conversation fails with a clear reason.
5. **Given** the request settings, **when** requests are sent, **then** both models use temperature 0.3, as in the reference.

### US4 (P1): Run a whole evaluation, with progress

As an **evaluator**, I want to run a full dataset (or its first N
conversations) and follow its progress live, so that I can see how far it is
and how it's scoring.

Acceptance scenarios:
1. **Given** a dataset and settings, **when** a run starts, **then** a new run file is created whose name contains the run's start timestamp. Progress is reported continuously: conversations done, failed and total; the criterion being graded within the current conversation; the running score; the most recent errors (up to 10); and elapsed time.
2. **Given** a conversation finishes grading, **when** it is recorded, **then** it is appended to the run file and flushed to disk **before** the next conversation starts.
3. **Given** a temporary error (rate limit, timeout, server error), **when** it occurs, **then** the request is retried up to 4 times. The request timeout is 180 seconds.
4. **Given** a conversation that still fails after the retries, **when** this happens, **then** it is skipped, counted as failed, left out of the run file and the score, and its error is kept. The run continues.
5. **Given** an error that will repeat for every conversation (invalid key, permission denied, unknown model or endpoint), or **5 conversations failing in a row**, **when** this happens, **then** the run stops with status *failed* and the reason is reported.
6. **Given** the run completes, **when** it ends, **then** the run file records status *completed* and the final score.
7. **Given** no conversation was graded successfully (for example, the key was wrong), **when** the run ends, **then** no run file is left behind.

### US5 (P1): Stop and continue a run

As an **evaluator**, I want to stop a run and continue it later from where it
stopped, so that long runs (up to 5,000 conversations) don't have to be done in
one sitting or restarted after a problem.

Acceptance scenarios:
1. **Given** a running run, **when** the user stops it, **then** it stops after the conversation in progress finishes, keeps everything graded so far, and the run file records status *stopped*.
2. **Given** a stopped, failed or interrupted run, **when** it is continued, **then** only conversations not yet in the run file are evaluated, including ones that failed before. New results are appended to the same file, and the score covers all graded conversations.
3. **Given** a continued run, **when** it starts, **then** the API key must be provided again (Constitution Article III). All other settings come from the run file.
4. **Given** the app or computer quit in the middle of writing a line, **when** the run is continued or opened, **then** the incomplete last line is detected and discarded, and every complete line is kept.
5. **Given** the dataset file for a run has changed or is missing, **when** the run is continued, **then** continuing is refused with a clear reason. Results from a different dataset are never mixed into the run.

### US6 (P2): Read and validate a run file

As an **evaluator**, I want any run file to be checked strictly when it is read,
so that later features (results browser, import) can rely on it and bad files are
rejected cleanly.

Acceptance scenarios:
1. **Given** a run file written by this app, **when** it is read, **then** its settings, status, every graded conversation and its scores are available. Scores are recomputed from the graded criteria, and they match what the run reported.
2. **Given** a file whose name doesn't match the run-file pattern, or whose header or any line is malformed or has missing or wrong-typed fields, **when** it is read, **then** it is rejected with a reason naming the problem (and the line, where relevant). Nothing from it is used.
3. **Given** any run file, **when** it is inspected, **then** it never contains the API key.

## Functional requirements

**Dataset**
- **FR-001** The app MUST read HealthBench dataset files (one conversation per line) as described in healthbench.md §2, including the tolerances in US1-2.
- **FR-002** Reading MUST fail as a whole, naming the line and the problem, if any line is invalid (US1-3).
- **FR-003** The app MUST support selecting only the first N conversations.

**Model access**
- **FR-004** The app MUST call any OpenAI-compatible Chat Completions endpoint, given a base URL, API key and model name.
- **FR-005** Reasoning effort MUST be sent only for *low*, *medium* or *high*, and left out for *none*.
- **FR-006** Grader requests MUST ask for a structured answer (an explanation plus a met/not-met flag) where the endpoint supports it, and MUST fall back to extracting the first valid JSON object from the text.
- **FR-007** Temporary errors MUST be retried up to 4 times with a 180-second timeout per request. Errors that will repeat (authentication, permission, not found) MUST NOT be retried.
- **FR-008** The API key MUST NOT appear in any log, error message, progress report or file.

**Grading and scoring**
- **FR-009** Each criterion MUST be graded with a separate grader request, using the **reference toolkit's grader prompt** (`GRADER.md`, reproduced in healthbench.md §4), so results line up with earlier runs of the toolkit. The run file MUST record which prompt was used.
- **FR-010** Scores MUST follow healthbench.md §5 exactly: the conversation score (unclipped), the run score (mean, clipped to 0–1), the exclusion of conversations with no positive criteria, and the four outcome labels.
- **FR-011** Per-theme and per-axis scores and the bootstrap standard deviation are **not** part of this feature. They come with the results browser that displays them. The run file MUST keep every tag they will need (example tags and criterion tags).

**Runs**
- **FR-012** A run MUST report progress as described in US4-1, after every criterion and every conversation.
- **FR-013** The failure policy MUST match US4-3 to US4-5 (the reference behaviour).
- **FR-014** Conversations MUST be evaluated **one at a time**, and criteria one after another, as in the reference.
- **FR-015** Stopping MUST take effect after the current conversation. No graded work is lost.
- **FR-016** Continuing MUST evaluate only conversations missing from the run file, MUST require the API key again, and MUST refuse if the dataset differs.

**Run file**
- **FR-017** Each run MUST be one `.jsonl` file: a header with the run settings (no API key), then one line per graded conversation, appended and flushed as each finishes. The file name MUST contain the start timestamp. The exact format and name pattern are fixed in this feature's contract.
- **FR-018** Each graded conversation line MUST include the conversation id, the messages, the example tags, the reply, and for every criterion: its text, points, tags, the met/not-met flag and the grader's explanation.
- **FR-019** The run file MUST always show the run's current status: *running*, *stopped*, *completed* or *failed*, plus the final score once it has finished.
- **FR-020** Reading a run file MUST validate it completely (US6-2) and MUST tolerate only an incomplete **last** line (US5-4).
- **FR-021** A run with nothing graded MUST NOT leave a run file.

## Non-functional requirements

- **NFR-001** Everything in this feature is pure Dart with no UI dependency (Constitution Article VI), and runs on macOS, Windows and Linux.
- **NFR-002** Tests MUST use a local fake OpenAI-compatible endpoint and never call a real one (Article VII).
- **NFR-003** Reading the full 5,000-conversation dataset MUST NOT block the caller. It may take up to 5 seconds.
- **NFR-004** An abrupt quit at any moment MUST lose at most the conversation in progress.
- **NFR-005** Model output and dataset content are treated as untrusted input. Very large lines or replies are rejected with a reason rather than crashing (Article IV).

## Key entities

- **Dataset**: a HealthBench file with its conversations.
- **Conversation**: an id, the messages so far, rubric criteria, example tags, and an optional ideal completion.
- **Criterion**: a statement with points (which may be negative) and tags.
- **Connection settings**: base URL, API key (in memory only), model under test, grader model, reasoning effort for each.
- **Run**: one evaluation of one dataset with fixed settings, a status and a run file.
- **Graded conversation**: a conversation plus the reply and one grade per criterion.
- **Grade**: met/not-met plus the grader's explanation for one criterion.
- **Progress**: the live counters described in US4-1.

## Edge cases

- The endpoint returns an empty reply, or no choices at all.
- The grader returns `criteria_met` as a string ("true") or omits it.
- Two runs start within the same second, so their timestamped names would collide.
- The disk fills up, or the run file becomes unwritable, during a run.
- The dataset has duplicate conversation ids. Continuing relies on ids, so this must be rejected or handled.
- A stop is requested while a retry is waiting.
- A run is continued while it's already running somewhere else in the app.
- A conversation has hundreds of criteria, making grading very long.

## Out of scope

- Any user interface (feature 003).
- Deleting, exporting and importing run files as user actions (feature 004). Only the reading and validation they will rely on is here.
- Downloading datasets and sampling subsets (feature 005).
- Reading the reference repo's run format (Constitution Article V).
- Storing the API key anywhere (Article III).
- Making the temperature configurable. It stays 0.3, as in the reference.

## Clarifications

### 2026-10-17
- **Q:** Which grader prompt? → **A:** The reference toolkit's `GRADER.md` (FR-009).
- **Q:** Sequential or parallel evaluation? → **A:** One at a time, as in the reference (FR-014).
- **Q:** Score breakdowns now? → **A:** Later, with the results UI. The run file keeps the tags they need (FR-011).
