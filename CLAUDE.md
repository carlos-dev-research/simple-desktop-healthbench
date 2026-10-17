# CLAUDE.md

Guidance for Claude Code (and any AI coding agent) working in this repository.

## Project

**simple-desktop-healthbench** is a cross-platform **Flutter desktop app**
(macOS, Windows, Linux) for running and browsing **HealthBench** benchmarks.
A model under test answers HealthBench conversations, a grader model scores each
answer against physician-written rubric criteria, and the app stores the runs and
shows the results.

It continues https://github.com/carlos-dev-research/evals-healthbench-dashboard
(Python harness + local web dashboard). Treat that repo as the **behavioural
reference**. Keep its scoring formulas exactly. Its run-file format is **not**
kept: the app has its own revised format (see Decisions below). Other behaviour
follows the reference unless a spec
explicitly changes them.

Before working on any feature, read:
- [docs/reference/healthbench.md](docs/reference/healthbench.md): dataset schema, grading procedure, grader prompt, scoring formulas, run file format, and the feature inventory of the reference app. It applies regardless of programming language.
- [docs/reference/flutter-desktop.md](docs/reference/flutter-desktop.md): toolchains, macOS sandbox entitlements, cross-platform concerns, and candidate packages.

## Current status

- **001 project scaffold**: implemented. The owner's screen checks (quickstart Q1, Q3, Q4) are pending.
- **002 evaluation core**: implemented in `lib/core/` (dataset, chat client, grading, scoring, run file, runner), test-first, with golden fixtures generated from the reference toolkit. Developer runner: `tool/try_run.dart`.
- **003 evaluation UI**: implemented (Runs and New run views, progress, stop/continue, results browser, safe Markdown). **Waiting for the owner's first UI test:** `specs/003-evaluation-ui/quickstart.md`. The delegation ends there.
- **Delegation (2026-10-17):** the owner delegated all technical decisions until their first hands-on UI test. Plans and tasks for 002 and 003 proceed without per-phase approval. Record every decision in that feature's `research.md`/`plan.md`, and stop for the owner when the UI is ready to test.
- To set up the toolchain, run `./tool/setup.sh` (`--check` reports without installing). Flutter is pinned with **FVM** in `.fvmrc`, so run it as `fvm flutter …`.
- Integration tests: plain files in `integration_test/`, run through the single entry point `integration_test/all_test.dart` (desktop relaunch limitation, 002 research R18). Add new ones there.
- `test/project/` holds the **project-rules tests** (contract: `specs/001-project-scaffold/contracts/project-rules.md`). Never weaken one to make a change pass. If a rule has to change, amend the spec or constitution first.
- If you change the tooling (Brewfile, setup.sh, Flutter version), keep README → *macOS setup* in sync, and follow the safety rules in [flutter-desktop.md §5](docs/reference/flutter-desktop.md). Never add a tool that shadows existing commands on PATH.

### Decisions already made (carry these into the constitution)

| Decision | Detail | Recorded in |
|---|---|---|
| Run storage | Runs live in the app's own storage (the macOS sandbox container) | [flutter-desktop.md §2.1](docs/reference/flutter-desktop.md) |
| Run-file format | The app's own revised format, **not compatible** with the reference repo. Defined in a spec contract | [healthbench.md §6](docs/reference/healthbench.md) |
| Run-file actions | For each run file: **delete**, **export**, and **import**. Import accepts only files that match the format and the file-name pattern | [flutter-desktop.md §2.1](docs/reference/flutter-desktop.md) |
| Run-file shape | One `.jsonl` per run (a header line plus one line per conversation, appended live). Runs can be stopped and continued where they left off. The file name contains a timestamp. If an imported file has the same name as an existing one, it replaces it after confirmation. No format versioning for now | [flutter-desktop.md §2.2](docs/reference/flutter-desktop.md) |
| Flutter version pinning | FVM + committed `.fvmrc` | [tool/setup.sh](tool/setup.sh) |
| Native dependencies | Swift Package Manager only. No CocoaPods; reject plugins without SwiftPM support | [flutter-desktop.md §4](docs/reference/flutter-desktop.md) |
| Dev-machine safety | The setup script asks before each change, guards Homebrew, never edits profiles | [flutter-desktop.md §5](docs/reference/flutter-desktop.md) |

[`specs/constitution.md`](specs/constitution.md) v1.0.0 is **approved** (2026-10-17). The engineering conventions below are now binding through it. Next step: the first feature spec (`specs/001-*`).

---

## Spec-driven development (SDD)

This project uses **spec-driven development**: the **specification is the
source of truth**, and code is generated from it. We follow the workflow
popularised by GitHub's Spec Kit (https://github.com/github/spec-kit). It is run
by hand here, with the same file names, so Spec Kit can be adopted later without
moving files.

### Core rules

1. **No code without a spec.** Every change to app behaviour traces back to a user story or requirement in `specs/NNN-*/spec.md`. Small fixes that don't change behaviour (typos, formatting, a broken build) are exempt.
2. **Spec and code disagree → fix the code, unless the spec is wrong.** If it is, update the spec first (and the plan or tasks if they are affected), then the code. Never let them drift apart without saying so.
3. **What/why before how.** `spec.md` describes user needs and testable acceptance criteria. It contains **no** tech stack, packages, classes or file paths. Those go in `plan.md`.
4. **Don't guess. Mark it.** Write `[NEEDS CLARIFICATION: <specific question>]` wherever the input is ambiguous, and ask the user. A spec is not ready for planning while any marker remains.
5. **No speculative features.** Nothing goes in a spec or plan "because we might need it".
6. **Every phase ends with human review.** Stop after each phase and present the artifact. Move to the next phase only after the user approves.
7. **Test-first.** Write tests from the acceptance criteria and contracts, confirm they fail, then implement.
8. **The constitution wins.** `specs/constitution.md` holds the non-negotiable project principles. Every plan checks itself against it. Any deviation must be justified in the plan's *Complexity Tracking* section.

### Workflow

```
constitution (once, amended rarely)
   └─ per feature:  specify → clarify → plan → tasks → implement → verify
```

| Phase | Input | Output | Gate to pass before moving on |
|---|---|---|---|
| **Constitution** | User's principles | `specs/constitution.md` | User approves |
| **Specify** | Feature description from the user | `specs/NNN-slug/spec.md` | User stories and acceptance criteria are testable, and no implementation details appear |
| **Clarify** | spec.md | Updated spec.md with a `## Clarifications` log | No `[NEEDS CLARIFICATION]` markers remain |
| **Plan** | spec.md + constitution + reference docs | `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md` | The constitution check passes, and every requirement maps to a part of the design |
| **Tasks** | plan + design artifacts | `tasks.md` | Each task is small, testable, and references the requirement it serves |
| **Implement** | tasks.md | Tests + code, with tasks ticked off one by one | `flutter analyze` is clean, all tests pass, and each task's checkbox is updated |
| **Verify** | spec + running app | A verification note in `tasks.md` (or `quickstart.md` results) | Every acceptance criterion is shown to work, and the user signs off |

Before implementing, also run an **analyze** pass: check spec ↔ plan ↔ tasks for
gaps, contradictions and requirements with no task, and report the findings.

### Directory layout

```
specs/
  constitution.md                 # project principles (versioned, dated amendments)
  001-<feature-slug>/
    spec.md                       # WHAT and WHY: user stories, requirements, acceptance criteria
    plan.md                       # HOW: architecture, packages, structure, constitution check
    research.md                   # options considered, decisions and rationale
    data-model.md                 # entities, fields, relationships, validation, state transitions
    contracts/                    # interfaces at module and file boundaries (JSON schemas, Dart abstract APIs)
    quickstart.md                 # manual validation scenarios, step by step
    tasks.md                      # ordered, checkable task list
  002-<feature-slug>/ ...
docs/reference/                   # shared domain and platform knowledge cited by specs
```

- Feature folders are numbered in sequence (`001`, `002`, …). Use a kebab-case slug.
- When we work on branches, name each branch after its feature folder (`001-run-evaluation`).
- Shared knowledge goes in `docs/reference/`, not copied into each spec. A spec links to the section it relies on.

### Artifact outlines

**spec.md**
```
# Feature: <name>            Status: Draft | Clarified | Approved     Date: YYYY-MM-DD
## Summary                    — one paragraph, user-facing
## User stories               — "As a <role>, I want <goal> so that <benefit>", prioritised P1/P2/P3
   ### US1 (P1) …
   Acceptance scenarios:      — Given / When / Then, each independently testable
## Functional requirements    — FR-001 … "The app MUST …" (testable, no tech)
## Non-functional requirements — NFR-001 … (performance, privacy, accessibility, platforms)
## Key entities               — names and meaning only (no fields or types)
## Edge cases
## Out of scope
## Clarifications             — dated Q&A log
```

**plan.md**: technical context (Flutter/Dart versions, packages, storage, target
OSes), a constitution check (pass/fail for each principle), the project structure,
the design and its decisions (with links to research.md), phases, the testing
approach, and Complexity Tracking (justified deviations).

**tasks.md**
```
## Phase 1: Setup
- [ ] T001 <action> in <file path>  (FR-00x)
## Phase 2: Foundational (blocking)
## Phase 3: US1 (P1)
- [ ] T010 [P] [US1] Write failing test for … in test/…
- [ ] T011 [US1] Implement … in lib/…
## Phase N: Polish & cross-cutting
```
- `[P]` marks a task that can run in parallel: it touches different files and depends on no unfinished task.
- `[USn]` links a task to a user story. Within a story, tests come before implementation.
- Tick `- [x]` only after the task's tests pass. If a task turns out bigger than expected, split it in tasks.md before continuing.

### How Claude should behave in this workflow

- At the start of a session, find the active feature (the highest-numbered folder with unticked tasks, or ask) and read its spec, plan and tasks before acting.
- When asked to "build X" with no spec: draft `spec.md` first and stop for review. Do not jump to code.
- When asked to plan: research (docs, pub.dev, the reference repo) before deciding. Record the alternatives considered in `research.md`.
- When implementing: work through tasks.md in order, one task (or one `[P]` group) at a time. Report which task IDs are done and how they were verified.
- If you discover a requirement that is missing or wrong while implementing: stop, propose the spec change, and wait for the user.
- Ask before installing tools, adding packages outside the approved plan, or making large structural changes.

---

## Engineering conventions (Flutter)

These conventions are binding through `specs/constitution.md` (Articles VI–IX).

- **Layering**: a pure-Dart **core** (dataset parsing, grading client, scoring, run storage, with no Flutter imports) underneath a Flutter **UI**. The core must be unit-testable without a device.
- **Scoring**: scores must match the HealthBench formulas exactly ([healthbench.md §5](docs/reference/healthbench.md)). Test them with hand-computed fixtures, including negative points and conversations with no positive criteria.
- **Run files**: use the app's own format, defined in a spec contract. The reference format is not supported. Import validates the whole file against that contract and the file-name pattern before writing anything, and rejects non-conforming files with a clear reason.
- **Secrets**: API keys never go into logs, run files, exceptions shown in the UI, or plain preference storage.
- **Untrusted content**: model output is rendered as Markdown with HTML disabled and no remote loading.
- **Tests never call paid APIs.** Use a fake OpenAI-compatible server or client.
- **Style**: `dart format`, `flutter_lints` (or stricter), `flutter analyze` with zero issues. Code follows Effective Dart naming.
- **Platforms**: develop on macOS. Don't break Windows or Linux: no hard-coded paths and no platform-only APIs without a guard. Keep the macOS entitlements identical in `DebugProfile` and `Release`.

### Commands

Always go through FVM so the pinned SDK is used:

```sh
./tool/setup.sh --check       # verify the toolchain
fvm flutter pub get
fvm flutter analyze
fvm dart format .
fvm flutter test
fvm flutter run -d macos      # or -d windows / -d linux on those hosts
fvm flutter build macos
```

Portability rules (another Mac must build from a clean clone with only `./tool/setup.sh`):
- Commit `.fvmrc`, `pubspec.lock`, `.vscode/settings.json` and both entitlements files. There is no Podfile, because we don't use CocoaPods.
- Leave `DEVELOPMENT_TEAM` empty in the Xcode project and use "Sign to Run Locally". A personal signing team goes in the git-ignored `macos/Runner/Configs/Local.xcconfig`.
- No absolute paths, usernames, or dependence on tools installed globally on one machine.

## Repo hygiene

- `healthbench/` (dataset files) is git-ignored. Never commit dataset files, API keys or `.env` files.
- Commit messages describe the change and reference the feature or task (for example `001: T012 scoring with negative points`).
