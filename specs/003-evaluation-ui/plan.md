# Plan: 003 evaluation UI

**Status:** Approved (delegated) · **Date:** 2026-10-17 · **Spec:** [spec.md](spec.md) · **Constitution:** v1.0.0

The owner delegated all technical decisions until their first UI test (see 002 plan). This feature **is** that UI test.

## Technical context

| Item | Choice |
|---|---|
| New dependencies | `flutter_riverpod`, `path_provider`, `file_selector`, `markdown` (research R1) |
| State | Riverpod `Notifier`s, no code generation. `ProviderScope(retry: none)` |
| Storage | `<app support>/runs/*.jsonl` (sandbox container on macOS). Form fields: session memory only (`newRunFormProvider`; superseded `form.json`, see research R6) |
| Layout | `NavigationRail` (Runs, New run), Material 3, minimum 960 × 640 |
| Core additions | `run_summary.dart` and `run_library.dart` (pure Dart, unit-tested) |

## Constitution check

| Article | Result | Notes |
|---|---|---|
| I | ✅ | Spec decided under delegation, recorded |
| II | ✅ | All numbers come from the core's scoring. Histogram bins as in the reference |
| III | ✅ | Key held only in widget and notifier memory, never on disk. Since Constitution 1.1.0 the Continue dialog is prefilled with the session's key |
| IV | ✅ | Own Markdown renderer: no HTML, no links opened, no images fetched (R3) |
| V | ✅ | Runs are only written through the core's runner |
| VI | ✅ | Logic in the core; UI state in Riverpod; hand-written JSON |
| VII | ✅ | Core first, then widget tests per screen, plus an end-to-end integration test with a fake server |
| VIII | ✅ | `path_provider` paths, first-party plugins on all three OSes, CI |
| IX | ✅ | Two Favorites plus two first-party packages |
| X | ✅ | English only. No breakdowns or file management (later features) |
| XI/XII | ✅ | No new tools. Commits to `main` |

**Complexity Tracking:** none.

## Structure

```
lib/core/run_summary.dart        # RunSummary, ConversationRow, histogramBins
lib/core/run_library.dart        # listRuns(dir) → valid + rejected entries
lib/main.dart                    # ProviderScope(retry: none) → HealthBenchApp
lib/app.dart                     # theme + Shell
lib/ui/shell.dart                # NavigationRail + views + notes footer
lib/ui/format.dart               # score, percent, duration formatting
lib/ui/state/providers.dart      # runsDirectory, datasetPicker, forms store
lib/ui/state/run_controller.dart # active run: start / resume / stop / progress
lib/ui/state/runs_controller.dart# run list + selection
lib/ui/new_run/new_run_view.dart # form + progress panel
lib/ui/new_run/progress_panel.dart
lib/ui/runs/runs_view.dart       # runs table, rejected files, selection
lib/ui/runs/run_detail.dart      # summary tiles, histogram, conversations, Continue
lib/ui/runs/histogram.dart
lib/ui/runs/conversation_view.dart
lib/ui/runs/continue_dialog.dart
lib/ui/markdown/markdown_view.dart
```

The placeholder `ui/home_screen.dart` is removed. Its tests become shell tests: the name and version stay visible in the navigation rail, so 001's FR-002 is still met.

## Phases

1. **Dependencies.** Add the packages, check `pod`-free macOS build, rules green.
2. **Core:** `run_summary` and `run_library`, test-first.
3. **Markdown renderer**, test-first: HTML stays literal, no network.
4. **State:** providers and controllers, unit-tested with a fake server.
5. **Shell and Runs view.** Run detail, histogram, conversation view, with widget tests.
6. **New run view** (form, validation, picker seam, progress panel, stop) and the Continue dialog, with widget tests.
7. **Integration test:** an end-to-end flow with the fake server, running in the sandboxed app.
8. **Docs, CI, quickstart.** Then hand over to the owner for the first UI test.
