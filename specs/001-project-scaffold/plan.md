# Plan: 001 project scaffold

**Status:** Approved · **Date:** 2026-10-17 · **Spec:** [spec.md](spec.md) (Approved) · **Constitution:** v1.0.0

## Technical context

| Item | Choice |
|---|---|
| SDK | Flutter 3.47.7 / Dart 3.13.5, pinned in `.fvmrc`. `environment: sdk: ^3.13.5` |
| Targets | macOS (deployment target 12.0, universal binary), Windows, Linux (GTK 3) |
| Dart package | `healthbench`, `version: 0.1.0+1`, `publish_to: none` |
| Dependencies | **None** besides the Flutter SDK. Dev: `flutter_test` and `integration_test` (SDK), `flutter_lints` (first-party) |
| State management | None needed yet. Riverpod arrives with the first feature that has state |
| Storage / network | None in 001 |
| CI | GitHub Actions, using only GitHub-owned actions. Matrix: macOS, Windows, Linux |

Research and alternatives: [research.md](research.md). Checks: [contracts/project-rules.md](contracts/project-rules.md). Manual validation: [quickstart.md](quickstart.md).

## Constitution check

| Article | Result | Notes |
|---|---|---|
| I Spec first | ✅ | Approved spec. This plan awaits review |
| II Scoring fidelity | ✅ n/a | No scoring in 001 |
| III Privacy and secrets | ✅ | No network or telemetry code. Entitlements allow outgoing network only, for later features |
| IV Untrusted content | ✅ n/a | No external content |
| V Run-file integrity | ✅ n/a | No run files |
| VI Architecture | ✅ | `lib/core/` is pure Dart, enforced by rule PR-1. JSON n/a. No wrappers |
| VII Testing | ✅ | Test-first: project-rules, unit and widget tests are written failing first, plus one integration test. No remote calls |
| VIII Cross-platform | ✅ | CI on all three OSes for every push. Paths are relative to the repo. Entitlements stay identical where it matters (PR-3, PR-4) |
| IX Dependencies | ✅ | Zero third-party runtime packages. `window_manager` and `package_info_plus` were avoided (R4, R5) |
| X Simplicity | ✅ | One Dart package. English only. Default icon |
| XI Toolchain | ✅ | CI reads `.fvmrc`. `setup.sh` Step 7 (`pub get`) applies from now on |
| XII Workflow | ✅ | Commits to `main` referencing task IDs |

**Complexity Tracking:** none. There are no deviations.

## Project structure (after 001)

```
lib/
  main.dart                 # runApp(const HealthBenchApp())
  app.dart                  # MaterialApp: title, light/dark theme, ThemeMode.system
  core/
    app_info.dart           # appName, appVersion (pure Dart)
  ui/
    home_screen.dart        # shows appName + appVersion
test/
  core/app_info_test.dart           # T-core
  ui/home_screen_test.dart          # T-home
  project/                          # PR-1 … PR-8 (plain Dart, dart:io)
    architecture_test.dart          # PR-1
    version_sync_test.dart          # PR-2
    macos_config_test.dart          # PR-3, PR-4, PR-5, PR-6
    identity_test.dart              # PR-7, PR-8
integration_test/
  app_test.dart                     # T-launch
macos/ windows/ linux/              # generated runners + edits below
.github/workflows/ci.yml            # contract: CI workflow
analysis_options.yaml  pubspec.yaml  pubspec.lock  .metadata
```

## Design

1. **Generate, then copy** (R1). Run `flutter create --empty` with the org and project name in a temp folder, then copy only the selected files into the repo.
2. **Native edits** (R2–R4):
   - **macOS:** set `PRODUCT_NAME = HealthBench Evals`, and set `contentMinSize` 960×640 in `MainFlutterWindow.swift`. Add the two permissions to both entitlements files.
   - **Windows:** set the window title, set `FileDescription` and `ProductName`/`CompanyName` per R2, and handle `WM_GETMINMAXINFO` scaled by DPI.
   - **Linux:** set `APPLICATION_ID` with hyphens, set the window and header-bar titles, and set the minimum-size geometry hints.
3. **Dart:**
   - `app_info.dart` holds the two constants.
   - `HealthBenchApp` builds Material 3 light and dark themes from one seed colour, with `ThemeMode.system`.
   - `HomeScreen` is a centred column with the name (headline) and "Version 0.1.0", laid out so it can't overflow at 960×640.
4. **Lints** (R10): `analysis_options.yaml` includes `flutter_lints`, the strict analyzer modes and the extra rules. The platform folders stay excluded.
5. **CI** (R11, R12): as specified in the contract.
6. **Docs:**
   - README: replace "Getting started" with run and test instructions (FR-013).
   - CLAUDE.md "Current status": the app code now exists.

## Implementation phases (detailed in tasks.md)

1. **Setup:** generate and copy the project, `pub get`, commit the untouched generated baseline (so later diffs show only our edits).
2. **Tests first:** project-rules tests, T-core and T-home. Run them and see them fail.
3. **US1/US4:** core constants, app, home screen, then T-core and T-home pass.
4. **US3:** entitlements and signing checks pass.
5. **US1/US5:** native names, IDs and minimum sizes. PR-7 and PR-8 pass.
6. **Integration test:** T-launch, locally on macOS.
7. **US2:** the CI workflow. Push, then check all three platforms are green.
8. **Polish:** README and CLAUDE.md, `setup.sh --check` passes, then quickstart Q1–Q9.

## Testing approach

- Run locally on macOS: `fvm dart format`, `fvm flutter analyze`, `fvm flutter test`, `fvm flutter test integration_test -d macos`.
- Windows and Linux are checked by CI (Article VIII.5).
- The project-rules tests resolve paths from the repo root (the `flutter test` working directory) and use only `dart:io`.

## Spec issues found during planning (resolved 2026-10-17)

- **S1. US3 scenario 3 can't be tested in 001.** It says a release build "makes an outgoing HTTPS request" that isn't blocked. But 001 has no networking code, and US5 scenario 3 *forbids* network requests at launch. **Approved amendment (applied to spec.md):** change US3 scenario 3 to "**Given** a release build, **when** its signed permissions are inspected, **then** outgoing network access is granted." This is checked by quickstart Q5 and rule PR-3. The real outgoing request is then verified in feature 002, the first feature that uses the network.
- **S2. Linux identifier (information only).** FR-003 is kept as written: Linux uses the hyphenated ID, which is valid for GTK (R2). Flutter strips hyphens by default, so the plan overrides that, and rule PR-7 guards it.
