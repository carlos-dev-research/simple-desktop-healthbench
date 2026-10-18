# Feature: Evaluation UI

**Status:** Done · **Date:** 2026-10-17 · **Constitution:** v1.0.0

## Summary

The first usable app. A user can start a HealthBench evaluation from a form,
watch it progress live, stop it and continue it later, and browse the results:
- a list of runs;
- a run's summary, with a score histogram;
- every conversation, with the model's reply and each graded criterion.

It brings the reference dashboard's **Results** and **New run** views to the
desktop, on top of the evaluation core (feature 002). Managing run files
(delete, export, import) is feature 004, and dataset download is feature 005.

Reference: [healthbench.md §7](../../docs/reference/healthbench.md) (feature inventory) and the reference repo's `webview/`.

## User stories

### US1 (P1): Start an evaluation

As an **evaluator**, I want a form for the connection, the models and the
dataset, so that I can start a run without the command line.

Acceptance scenarios:
1. **Given** the New run view, **when** it opens, **then** it shows these fields:
   - base URL;
   - API key (hidden while typing);
   - model under test and its reasoning effort (none, low, medium, high);
   - grader model and its reasoning effort;
   - a dataset file chosen with the system file dialog, showing its name and conversation count once read;
   - an optional maximum number of conversations.
2. **Given** a missing or invalid field (empty model, invalid base URL, unreadable dataset, limit < 1), **when** the user tries to start, **then** the run doesn't start and the field shows why.
3. **Given** valid fields, **when** the user starts the run, **then** it begins and the progress panel appears.
4. **Given** values typed or chosen in the form (base URL, API key, models, efforts, dataset, limit), **when** the user switches to Runs and back, **then** they are all still there. **Given** the app is closed and reopened, **when** the form shows, **then** every field is empty: nothing is stored on disk (Constitution III). *(Amended 2026-10-17 at the owner's request.)*

### US2 (P1): Follow a run live

As an **evaluator**, I want to see a run's progress as it happens, so that I
know how far it is and whether something is wrong.

Acceptance scenarios:
1. **Given** a running run, **when** it progresses, **then** the panel updates live with:
   - its status;
   - a bar for conversations processed out of the total (including the part of the current conversation that is done);
   - a second bar and text for the criteria graded in the current conversation, or "generating the response";
   - elapsed time, estimated time left, the score so far, and the number of conversations graded;
   - recent errors, labelled as skipped conversations.
2. **Given** a running run, **when** the user presses **Stop**, **then** the panel says it will stop after the current conversation, and it then shows *stopped*.
3. **Given** a run that ended (completed, stopped or failed), **when** the panel shows it, **then** it shows the final state and the reason for a failure, and offers to open the run's results.
4. **Given** a running run, **when** the user tries to start another one, **then** it isn't possible: only one run at a time, as in the reference.

### US3 (P1): Browse runs and results

As an **evaluator**, I want to see all my runs and inspect any of them, so that
I can understand how a model did.

Acceptance scenarios:
1. **Given** run files in the app's storage, **when** the Runs view opens, **then** it lists them newest first, with:
   - run id and status (running, stopped, completed, failed, interrupted);
   - model under test, grader, reasoning efforts and dataset;
   - conversations graded out of selected;
   - the score, as a number and a bar.

   Files that are not valid run files are listed separately, with the reason they were rejected.
2. **Given** a selected run, **when** its summary shows, **then** it includes the run score, conversations, criteria graded, positive criteria met (percentage and count), and penalties triggered (percentage and count). It also shows a histogram of conversation scores in 11 bins (below 0, then 0.0–0.1 … 0.9–1.0) with a count on each bar.
3. **Given** a selected run, **when** its conversations are listed, **then** each row shows its number, a preview of the last user message, the points earned out of the possible, and the score. The list can be searched (in the messages, the reply, the criteria and the explanations, ignoring case) and sorted (original order, lowest score first, highest first). Long runs load progressively.
4. **Given** an opened conversation, **when** it shows, **then** it includes every message with its role, the evaluated reply rendered as Markdown, and a table of every criterion with:
   - points;
   - outcome: earned, missed, penalty or avoided, visually distinct;
   - criterion text and tags;
   - the grader's explanation.
5. **Given** a run in progress, **when** it is shown in the list, **then** it appears as running, and its results update when the list is refreshed.

### US4 (P1): Continue a run

As an **evaluator**, I want to continue a stopped, failed, interrupted or
incomplete run, so that long evaluations survive interruptions.

Acceptance scenarios:
1. **Given** a run with conversations still missing, **when** it is selected, **then** a **Continue** action is offered. It asks for the API key and the dataset file. The key is prefilled with the key from this session's New-run form, if there is one, and can be changed. *(Amended 2026-10-17, Constitution 1.1.0.)*
2. **Given** the key and the right dataset, **when** the user continues, **then** the run resumes in the progress panel, grading only the missing conversations.
3. **Given** a different dataset file, **when** the user continues, **then** it is refused with the reason, and nothing changes.
4. **Given** a run with nothing left to do, **when** it is selected, **then** no Continue action is offered.

### US5 (P2): Safe display and honest numbers

As a **user**, I want model output shown safely and the results put in
context, so that nothing harmful runs and I don't over-read the scores.

Acceptance scenarios:
1. **Given** Markdown in a model reply, **when** it is shown, **then** headings, paragraphs, lists, emphasis, code and tables are rendered. Raw HTML is shown as text, and nothing is loaded from the network. Images appear as their text description only, and links are shown but never opened automatically.
2. **Given** any results view, **when** it is shown, **then** it includes notes that model output is unreviewed and not medical advice, and that scores from subsets or other graders are not comparable to published HealthBench numbers.
3. **Given** text in the results, **when** the user selects it, **then** it can be copied.

## Functional requirements

- **FR-001** The app MUST have two main views, **Runs** and **New run**, reachable at all times.
- **FR-002** The New-run form MUST collect the fields listed in US1-1. It MUST validate them before starting, using the core's rules.
- **FR-003** The API key MUST be held only in memory: no preferences, no files, never shown after typing unless the user reveals it.
- **FR-004** All form fields, including the API key and the chosen dataset, MUST be kept **in memory for the app session**, surviving view changes, and MUST NOT be written to disk. *(Amended 2026-10-17: previously, non-secret fields were remembered in a file between launches. That file is no longer written, and a leftover one is deleted.)*
- **FR-005** The dataset MUST be chosen with the native open dialog. The app MUST read it with the core and show its name and conversation count, or the core's error.
- **FR-006** Only one run MUST be active at a time.
- **FR-007** The progress panel MUST show everything in US2-1 and update live, without blocking the interface.
- **FR-008** Stop MUST map to the core's stop: it takes effect after the current conversation.
- **FR-009** Runs MUST be stored in, and listed from, the app's own storage folder (flutter-desktop.md §2.1).
- **FR-010** The Runs view MUST list valid runs and separately list rejected files with their reasons. A refresh action MUST re-read the folder.
- **FR-011** The run summary and histogram MUST match US3-2, with numbers recomputed by the core.
- **FR-012** Conversation search, sort and progressive loading MUST match US3-3.
- **FR-013** The conversation detail MUST match US3-4.
- **FR-014** Continue MUST be offered exactly when conversations are missing and the run isn't active. It MUST ask for the dataset each time, and for the key, prefilled with the session's key when one was entered (US4, Constitution III.1 as amended in 1.1.0).
- **FR-015** Markdown rendering MUST follow US5-1.
- **FR-016** The notes in US5-2 MUST be visible in the Runs and New-run views.

## Non-functional requirements

- **NFR-001** The interface stays responsive during a run and while opening the largest run (5,000 conversations). Lists are built lazily.
- **NFR-002** Works with light and dark appearance at 960 × 640 and larger, with no overflow.
- **NFR-003** Keyboard: Tab moves through the form fields, and Enter starts the run from the form.
- **NFR-004** Every widget test runs without network access. The integration test drives a full run against a local fake endpoint.

## Key entities

- **Run summary**: a run file's header and status, plus the derived counts and score.
- **Run list entry**: a valid run, or a rejected file with its reason.
- **Form state**: the New-run fields; the key only in memory.

## Edge cases

- The storage folder doesn't exist yet (first launch).
- A run file is being written while the list is read (an in-progress run).
- The dataset file is moved after it was chosen.
- The app quits during a run: the run shows as interrupted next time, and can be continued.
- A conversation with very long messages or hundreds of criteria.
- A reply with a huge table, or deeply nested lists.

## Out of scope

- Deleting, exporting and importing run files (feature 004).
- Downloading datasets and sampling subsets (feature 005).
- Per-theme and per-axis breakdowns and bootstrap error bars (later, with the results features).
- Storing the API key (Constitution III).
- More than one run at a time.

## Clarifications

### 2026-10-17 (decided under delegation)
- **Dataset access:** the dataset is chosen with the file dialog for each new run and each continue. The app doesn't keep long-term access to folders outside its storage (macOS sandbox). A dataset library belongs to feature 005.
- **API key on continue:** ~~the Continue dialog always starts with an empty key field~~. Superseded 2026-10-17: it is prefilled with the session key (Constitution 1.1.0).
- **Markdown:** rendered by the app itself from a first-party parser (see plan), because no maintained Flutter Favorite renders Markdown.
