# Constitution: simple-desktop-healthbench

**Version:** 1.1.0 · **Status:** Approved · **Ratified:** 2026-10-17 · **Amended:** 2026-10-17

These are the non-negotiable principles of the project. Every `plan.md` must
include a **Constitution Check** listing each article as pass or fail. Any
deviation must be justified in the plan's **Complexity Tracking** section and
approved by the project owner before work starts. If this document conflicts
with any other document in the repo, this one wins.

---

## Article I: Spec first

1. No change to app behaviour without an approved `specs/NNN-*/spec.md`. The workflow is constitution → specify → clarify → plan → tasks → implement → verify, as described in [CLAUDE.md](../CLAUDE.md).
2. The spec is the source of truth. If code and spec disagree, fix the code, or amend the spec first and then the code.
3. Specs describe *what* and *why*, never *how*. Every `[NEEDS CLARIFICATION]` marker is resolved before planning starts.
4. Every phase ends with review by the project owner.

## Article II: Scoring fidelity

1. Scores follow the HealthBench formulas exactly ([healthbench.md §5](../docs/reference/healthbench.md)):
   - Conversation score: earned points ÷ maximum positive points. It is *not* clipped.
   - Run score: the mean of conversation scores, clipped to [0, 1].
   - Conversations with no positive criteria are excluded.
2. Any change to grading or scoring (prompt, formula, aggregation) needs a spec, and the UI must label scores produced the new way.
3. The UI states that scores from subsets or non-OpenAI graders are not comparable to published numbers.

## Article III: Privacy and secrets

1. **The API key lives in memory only.** It is never written to disk, preferences, the keychain, logs, run files, crash output or error messages. Within one app session it may be reused, for example to continue a run. After the app restarts, it must be entered again.
2. **Local first.** The app makes network calls only to the endpoint the user configures and, if a spec adds dataset download, to the official dataset host.
3. **The app itself collects no telemetry.**
4. Run files contain model output and metadata, never credentials.

## Article IV: Untrusted content

1. Everything that comes from models, dataset files or imported files is untrusted.
2. Markdown is rendered with raw HTML disabled, and nothing is loaded from remote sources (no images or links fetched automatically).
3. Parsers enforce size limits and reject bad input with a clear reason. They never crash the app.

## Article V: Run-file integrity

1. A run is **one `.jsonl` file**: a header line with the run metadata, then one line per graded conversation. The file name contains the run's timestamp. The exact format and name pattern are defined in a spec contract. The format is the app's own and is **not** compatible with the reference repo.
2. Each graded conversation is **appended and flushed as soon as it finishes**, so a run can be **stopped and continued** from where it left off. A truncated last line is detected and discarded, never trusted.
3. **Import** validates the whole file (format and name pattern) before writing anything. Invalid files are rejected with a reason. If a file with the same name already exists, it is replaced only after the user confirms, and never while that run is in progress.
4. Delete asks for confirmation. Export writes only to the location the user chose.
5. No format versioning for now. A format change after release requires amending this article.

## Article VI: Architecture

1. **Pure-Dart core, Flutter UI.** Dataset parsing, the API client, grading, scoring, run storage and import validation live in a core layer that imports no Flutter code and is unit-testable on any machine.
2. **UI state uses Riverpod.** The core does not depend on Riverpod.
3. **JSON models are hand-written** (`fromJson`/`toJson`). No code generation or `build_runner`.
4. Use framework features directly. Don't add wrappers or abstractions until a second real use exists.

## Article VII: Testing

1. **The core is test-first.** Tests are written from the acceptance criteria and contracts, seen failing, then made to pass.
2. **Key screens have widget tests**, using fake core services.
3. **At least one integration test** runs a complete evaluation in the real app against a **local fake OpenAI-compatible server**.
4. **No test ever calls a paid or remote API.**
5. Scoring and import validation have fixture tests, including edge cases: negative points, conversations with no positive criteria, truncated lines, wrong file names, missing fields.
6. A task is done only when `fvm flutter analyze` reports zero issues, `fvm dart format` makes no changes, and all tests pass.

## Article VIII: Cross-platform from day one

1. Every feature must build and pass its tests on **macOS, Windows and Linux**.
2. **CI (GitHub Actions) runs analyze and the tests on all three platforms for every push to `main`.** A red build is fixed before new feature work continues.
3. No hard-coded paths, usernames or OS-specific APIs without a guard. App data goes in the directory the platform provides for it.
4. The two macOS entitlements files stay identical, granting only network client access and files the user selects.
5. Manual verification (`quickstart.md`) happens on macOS. Other platforms rely on CI plus a manual check before a release.

## Article IX: Dependencies

1. Use the Dart and Flutter SDKs first.
2. A third-party package is allowed only if **all** of the following hold:
   - It is a **[Flutter Favorite](https://docs.flutter.dev/packages-and-plugins/favorites)** or a first-party package from the `flutter.dev` / `dart.dev` / `tools.dart.dev` publishers.
   - It supports macOS, Windows and Linux.
   - On macOS, it supports Swift Package Manager (no CocoaPods).
   - It is actively maintained.
   - Its `plan.md` justifies why the SDK alone is not enough.
3. Any exception must be recorded in Complexity Tracking with the alternatives considered, and approved by the project owner.
4. `pubspec.lock` is committed. Upgrading a dependency is a deliberate, separate change.

## Article X: Simplicity

1. No speculative features. Every requirement traces to a user story.
2. **The interface is in English only**, with no localization setup.
3. Prefer the smallest design that meets the spec.

## Article XI: Reproducible and safe toolchain

1. The Flutter version is pinned in `.fvmrc`, and all commands run through `fvm`.
2. A clean clone must build on another Mac using only `./tool/setup.sh` (Xcode is the only manual prerequisite).
3. The setup tooling follows the safety rules in [flutter-desktop.md §5](../docs/reference/flutter-desktop.md):
   - It asks before every change.
   - Homebrew runs with guards.
   - It never edits shell profiles.
   - It never adds a tool that shadows existing commands.
   - It checks at the end that nothing else changed.

## Article XII: Workflow and repo hygiene

1. **Commit directly to `main`** in small commits whose messages reference the feature and task (`001: T012 …`). CI must stay green.
2. Never commit datasets, API keys, `.env` files, signing material or run files (all enforced by `.gitignore`).
3. Documentation changes ship together with the change they describe (README, `docs/reference/`, specs).

---

## Governance

- Amendments are proposed as a change to this file, with the reason. They take effect once the project owner approves them.
- Versioning: **major** for removing or redefining a principle, **minor** for adding one, **patch** for wording.
- Each amendment adds an entry to the log below.

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-10-17 | Initial version, approved by the project owner |
| 1.1.0 | 2026-10-17 | III.1: the key may be reused within a session (for example on Continue). It is re-entered only after a restart. Still memory-only. Approved by the project owner |
