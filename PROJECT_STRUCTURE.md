# Project structure

A map of every folder and file in this repository: what it is, and why it's
there. Use it to find your way around when reviewing or overseeing the
project. For what the app does and how to use it, see [README.md](README.md).

Paths are links, so you can open them directly. Folders and files that git
ignores (they exist only on your machine) are listed at the end.

## Routes: where to look for…

| Question | Start here | Then |
|---|---|---|
| What does the app do, and how do I use it? | [README.md](README.md) | [images/](images/) for screenshots |
| What are the non-negotiable rules of the project? | [specs/constitution.md](specs/constitution.md) | [CLAUDE.md](CLAUDE.md) for how the AI agent applies them |
| What was each feature supposed to do? | `specs/NNN-*/spec.md` (user stories, requirements, acceptance criteria) | `plan.md` for how it was built, `tasks.md` for what was done and verified |
| Why was a technical choice made? | `specs/NNN-*/research.md` (options considered, decision, rationale) | `plan.md` → *Complexity Tracking* for any deviation from the constitution |
| What are HealthBench's rules (dataset, grading, scoring)? | [docs/reference/healthbench.md](docs/reference/healthbench.md) | [lib/core/scoring.dart](lib/core/scoring.dart) and [test/core/scoring_test.dart](test/core/scoring_test.dart) |
| What is inside a run file? | [specs/002-evaluation-core/contracts/run-file.md](specs/002-evaluation-core/contracts/run-file.md) | [lib/core/run_file.dart](lib/core/run_file.dart), and real examples in [results/](results/) |
| Is the API key ever written anywhere? | Constitution, Article III | [test/core/no_secrets_test.dart](test/core/no_secrets_test.dart) |
| How do I know the code does what the spec says? | `specs/NNN-*/tasks.md` (each task names its requirement) | [test/](test/), [integration_test/](integration_test/), and the CI run on GitHub |
| How do I check it by hand? | `specs/NNN-*/quickstart.md` (manual checklists) | the app zips in [dist/](dist/) |
| What results were produced? | [results/](results/) | import one into the app: **Runs** → **Import** |

## Top level

| Path | What it is |
|---|---|
| [README.md](README.md) | The front page: the experiment, what the app does, setup, usage, dataset, development |
| [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) | This map |
| [CLAUDE.md](CLAUDE.md) | Instructions for AI coding agents: the spec-driven workflow, current status, decisions already made, engineering conventions, commit rules |
| [LICENSE](LICENSE) | The license: Apache 2.0 |
| [Brewfile](Brewfile) | The Homebrew packages the macOS setup script may install (FVM) |
| [pubspec.yaml](pubspec.yaml) | The Dart/Flutter package: name, version (`0.2.0`), dependencies |
| [pubspec.lock](pubspec.lock) | Exact dependency versions, committed so every machine builds the same thing |
| [analysis_options.yaml](analysis_options.yaml) | Lint rules for `flutter analyze` |
| [.fvmrc](.fvmrc) | The pinned Flutter version, used by FVM |
| [.metadata](.metadata) | Flutter's own record of how the project was created |
| [.gitignore](.gitignore) | What git ignores: build output, the dataset, local signing, secrets |
| [.gitattributes](.gitattributes) | Keeps `results/` files byte for byte (no line-ending conversion) |
| [.github/workflows/ci.yml](.github/workflows/ci.yml) | CI on GitHub: format, analyze, all tests, integration tests and a release build, on macOS, Windows and Linux |
| [.vscode/settings.json](.vscode/settings.json) | Points VS Code at the FVM-pinned Flutter SDK |

## `specs/`: the source of truth

Spec-driven development: every behaviour of the app traces back to a spec here.
Each feature folder follows the same phases, in this order:

| File | Phase | What it answers |
|---|---|---|
| `spec.md` | Specify, clarify | **What and why**: user stories, requirements, acceptance criteria, edge cases, out of scope, and a dated log of clarifications. No technology |
| `research.md` | Plan | Options considered, decision and rationale (not every feature needed one) |
| `plan.md` | Plan | **How**: technical context, constitution check, structure, design, testing approach |
| `data-model.md` | Plan | Entities, fields, validation, state transitions |
| `contracts/` | Plan | Exact interfaces at file and module boundaries |
| `tasks.md` | Tasks, implement | The ordered task list, ticked as each task's tests passed, and the owner's sign-off |
| `quickstart.md` | Verify | Step-by-step manual checks for a person |

| Path | What it is |
|---|---|
| [specs/constitution.md](specs/constitution.md) | The project's principles (v1.2.0). Every plan is checked against it |
| [specs/001-project-scaffold/](specs/001-project-scaffold/) | The empty app on three OSes, sandboxing, identity, and the project-rules tests. [contracts/project-rules.md](specs/001-project-scaffold/contracts/project-rules.md) lists those rules (PR-1…PR-8) |
| [specs/002-evaluation-core/](specs/002-evaluation-core/) | The engine, ported from the reference Python toolkit: reading datasets, calling models, grading, scoring, run files, stop and continue. Contracts: [run-file.md](specs/002-evaluation-core/contracts/run-file.md) (the file format), [chat-completions.md](specs/002-evaluation-core/contracts/chat-completions.md) (the API calls), [core-api.md](specs/002-evaluation-core/contracts/core-api.md) (what the UI may use) |
| [specs/003-evaluation-ui/](specs/003-evaluation-ui/) | The desktop interface: new run, live progress, runs list, run detail, conversations, continue |
| [specs/004-run-file-management/](specs/004-run-file-management/) | Export, import and delete of run files |
| [specs/005-dataset-management/](specs/005-dataset-management/) | The Datasets view: verified downloads of the official files, samples, adding your own files |
| [specs/006-score-statistics/](specs/006-score-statistics/) | Median, standard deviation and bootstrap standard deviation of a run's score |

## `docs/reference/`: shared knowledge

Background that the specs cite instead of repeating.

| Path | What it is |
|---|---|
| [docs/reference/healthbench.md](docs/reference/healthbench.md) | HealthBench itself: dataset schema, grading procedure, grader prompt, scoring formulas, and the reference app's features |
| [docs/reference/flutter-desktop.md](docs/reference/flutter-desktop.md) | The platform: toolchains, macOS sandbox and entitlements, run storage decisions, cross-platform concerns, dev-machine safety rules |

## `lib/`: the app's code

Two layers. `lib/core/` is pure Dart with no Flutter (a test enforces this), so
the evaluation logic can be tested without a screen. `lib/ui/` is the Flutter
interface on top of it.

| Path | What it is |
|---|---|
| [lib/main.dart](lib/main.dart) | Entry point: starts the app inside Riverpod's state container |
| [lib/app.dart](lib/app.dart) | Root widget: theme (light and dark, following the system) |

### `lib/core/`: evaluation engine (pure Dart)

| Path | What it is |
|---|---|
| [app_info.dart](lib/core/app_info.dart) | App name and version |
| [dataset.dart](lib/core/dataset.dart) | HealthBench records (conversation, rubric criteria) and reading dataset files with validation |
| [dataset_library.dart](lib/core/dataset_library.dart) | Official files with their pinned size, SHA-256 and count; verified download; adding files; reproducible samples; the library index; delete |
| [settings.dart](lib/core/settings.dart) | Run settings: endpoint, key, models, reasoning effort, timeouts |
| [chat_client.dart](lib/core/chat_client.dart) | Minimal OpenAI-compatible Chat Completions client, with retries and timeouts |
| [grader_prompt.dart](lib/core/grader_prompt.dart) | The reference grader prompt and how it's filled for each criterion |
| [grading.dart](lib/core/grading.dart) | One conversation: generate the reply, grade it against every criterion, read the grader's answer |
| [scoring.dart](lib/core/scoring.dart) | The official HealthBench scoring formulas |
| [runner.dart](lib/core/runner.dart) | A whole run: progress, stop, continue where it left off |
| [run_file.dart](lib/core/run_file.dart) | Writing run files (append-only) and reading them with full validation |
| [run_library.dart](lib/core/run_library.dart) | The runs folder: listing, import, export, delete |
| [run_summary.dart](lib/core/run_summary.dart) | The numbers the results views show (counts, histogram, statistics) |
| [statistics.dart](lib/core/statistics.dart) | Median, sample standard deviation, bootstrap standard deviation |
| [seeded_random.dart](lib/core/seeded_random.dart) | SplitMix64, the deterministic random generator behind samples and the bootstrap |

### `lib/ui/`: desktop interface (Flutter)

| Path | What it is |
|---|---|
| [shell.dart](lib/ui/shell.dart) | The window frame: navigation rail (Runs, New run, Datasets), version, and the notes footer |
| [format.dart](lib/ui/format.dart) | Shared number formatting |
| [state/providers.dart](lib/ui/state/providers.dart) | Shared state: storage folder, current view, the session-only New-run form, test seams for file dialogs |
| [state/runs_controller.dart](lib/ui/state/runs_controller.dart) | The list of run files |
| [state/run_controller.dart](lib/ui/state/run_controller.dart) | The active run: start, stop, continue, one at a time |
| [state/datasets_controller.dart](lib/ui/state/datasets_controller.dart) | The dataset library and downloads in progress |
| [new_run/new_run_view.dart](lib/ui/new_run/new_run_view.dart) | The New-run form |
| [new_run/dataset_field.dart](lib/ui/new_run/dataset_field.dart) | Choosing a dataset: from the library, or with the file dialog |
| [new_run/progress_panel.dart](lib/ui/new_run/progress_panel.dart) | Live progress of the running evaluation |
| [runs/runs_view.dart](lib/ui/runs/runs_view.dart) | The runs list and the selected run |
| [runs/run_detail.dart](lib/ui/runs/run_detail.dart) | One run: summary tiles, histogram, conversations |
| [runs/histogram.dart](lib/ui/runs/histogram.dart) | The score histogram |
| [runs/conversation_view.dart](lib/ui/runs/conversation_view.dart) | One conversation: messages, the reply, and how each criterion was graded |
| [runs/continue_dialog.dart](lib/ui/runs/continue_dialog.dart) | Continuing a stopped run |
| [runs/run_actions.dart](lib/ui/runs/run_actions.dart) | Import, export and delete, with their dialogs |
| [runs/status_chip.dart](lib/ui/runs/status_chip.dart) | Small status label and score bar |
| [datasets/datasets_view.dart](lib/ui/datasets/datasets_view.dart) | The Datasets view: downloads, library, sample dialog |
| [markdown/markdown_view.dart](lib/ui/markdown/markdown_view.dart) | Safe rendering of model output: no HTML, no clickable links, no remote images |

## `test/`: automated tests

Run with `fvm flutter test`. No test calls a paid API: a local fake server
stands in for the models.

| Path | What it is |
|---|---|
| [test/core/](test/core/) | Tests of the engine, one file per core module. Notable: [scoring_test.dart](test/core/scoring_test.dart) (formulas, including negative points), [no_secrets_test.dart](test/core/no_secrets_test.dart) (the key never leaks), [self_contained_test.dart](test/core/self_contained_test.dart) (run files hold every criterion), [statistics_test.dart](test/core/statistics_test.dart) (checked against an independent Python implementation) |
| [test/ui/](test/ui/) | Widget tests of each view: shell, new run, runs, run actions, datasets, Markdown, state |
| [test/project/](test/project/) | **Project-rules tests**: the core stays pure Dart, the version matches, macOS permissions and signing, app identity on every OS, and what `results/` and `dist/` may contain. Never weakened to make a change pass |
| [test/fixtures/](test/fixtures/) | Golden values the tests compare against: scoring, grader prompt and answer parsing (from the reference toolkit), SplitMix64 (from Python) |
| [test/support/](test/support/) | Test helpers: the fake OpenAI-compatible server, dataset builders, run-file builders |

## `integration_test/`: the real app

These start the real, sandboxed app and drive it like a user, against local
fake servers. CI runs them on every OS.

| Path | What it is |
|---|---|
| [all_test.dart](integration_test/all_test.dart) | The single entry point that runs all flows (a desktop app can't be relaunched per file) |
| [launch.dart](integration_test/launch.dart) | The app starts and shows its name and version |
| [network.dart](integration_test/network.dart) | Outgoing network works inside the sandbox |
| [evaluation_flow.dart](integration_test/evaluation_flow.dart) | A full evaluation through the UI |
| [run_files_flow.dart](integration_test/run_files_flow.dart) | Wrong key, form kept across views, stop and continue, export, delete, import |
| [datasets_flow.dart](integration_test/datasets_flow.dart) | Download, sample, and a run on the sample |

## `tool/`: scripts

| Path | What it is |
|---|---|
| [tool/setup.sh](tool/setup.sh) | macOS toolchain setup. Asks before every change; `--check` only reports |
| [tool/package_macos.sh](tool/package_macos.sh) | Builds the release app from a neutral path, checks it has no personal paths, and zips it into `dist/` |
| [tool/try_run.dart](tool/try_run.dart) | Developer-only command-line run of the engine against a real endpoint |
| [tool/ci_failures.dart](tool/ci_failures.dart) | CI helper: turns failed tests into readable GitHub annotations |

## Output folders

| Path | What it is |
|---|---|
| [dist/](dist/) | Ready-to-use macOS app zips, one per version, and a [README](dist/README.md) on opening them. Tested on macOS only |
| [results/](results/) | Run files committed for auditing and sampling, each validated by a test. See its [README](results/README.md) |
| [images/](images/) | Screenshots used in the README |

## Platform folders

Generated by Flutter for each OS, then adjusted. You rarely need to open these.

| Path | What it is |
|---|---|
| [macos/](macos/) | The macOS app. Key files: [Release.entitlements](macos/Runner/Release.entitlements) and [DebugProfile.entitlements](macos/Runner/DebugProfile.entitlements) (sandbox permissions: outgoing network and user-chosen files), [Configs/AppInfo.xcconfig](macos/Runner/Configs/AppInfo.xcconfig) (name and bundle identifier), [MainFlutterWindow.swift](macos/Runner/MainFlutterWindow.swift) (minimum window size, 960 × 640), [Runner.xcodeproj/](macos/Runner.xcodeproj/) (Xcode project; ad-hoc signing, no personal team) |
| [windows/](windows/) | The Windows app: CMake build and the Win32 runner (window title, icon, version info) |
| [linux/](linux/) | The Linux app: CMake build and the GTK runner (application ID, window title) |

## Not in the repository (git-ignored)

These appear on your machine but are never committed.

| Path | What it is |
|---|---|
| `healthbench/` | Dataset files downloaded from the terminal |
| `build/` | Flutter build output, recreated by every build |
| `.dart_tool/`, `.flutter-plugins-dependencies` | Dart and Flutter caches |
| `.fvm/` | FVM's link to the pinned Flutter SDK |
| `macos/Runner/Configs/Local.xcconfig` | Optional personal signing team |
| `*/flutter/ephemeral/`, generated plugin registrants | Files Flutter regenerates for each OS |
