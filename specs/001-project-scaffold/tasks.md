# Tasks: 001 project scaffold

**Status:** Done (owner sign-off 2026-10-18) · **Plan:** [plan.md](plan.md) · **Contract:** [contracts/project-rules.md](contracts/project-rules.md)

Legend: `[P]` = can run in parallel (different files, no unfinished dependency) · `[USn]` = user story · *(FR/PR/T ids)* = what the task satisfies.
Tick a task only when its tests pass. Every commit message starts with `001: Txxx`.

## Phase 1: Setup

- [x] T001 Generate the project in a scratch folder: `flutter create --platforms=macos,windows,linux --org io.github.carlos-dev-research --project-name healthbench --empty`, using Flutter 3.47.7 *(R1)*
- [x] T002 Copy `lib/`, `macos/`, `windows/`, `linux/`, `pubspec.yaml`, `pubspec.lock`, `.metadata` and `analysis_options.yaml` into the repo. Leave out `.idea/`, `*.iml`, its `README.md` and its root `.gitignore` *(R1)*
- [x] T003 Run `fvm flutter pub get`, `fvm flutter analyze` and `fvm flutter build macos --debug` to confirm the untouched baseline builds. Commit it as "001: T001–T003 generated baseline" *(FR-001)*

## Phase 2: Foundational

- [x] T004 Set `analysis_options.yaml`: `flutter_lints`, strict-casts / strict-inference / strict-raw-types, the R10 rules, and platform folders excluded. Run `fvm flutter analyze` until it reports 0 issues *(NFR-003)*
- [x] T005 Set the `pubspec.yaml` description to "Run and browse HealthBench evaluations." and keep `version: 0.1.0+1` *(FR-002)*
- [x] T006 Create the folders `lib/core/`, `lib/ui/`, `test/core/`, `test/ui/`, `test/project/` and `integration_test/`. Add `integration_test` (SDK) to `dev_dependencies` *(FR-009)*

## Phase 3: Tests first (they must fail before Phase 4)

- [x] T007 [P] [US4] `test/project/architecture_test.dart`: rule PR-1 (`lib/core/**` has no Flutter, `dart:ui` or Riverpod imports) *(FR-008)*
- [x] T008 [P] [US1] `test/project/version_sync_test.dart`: rule PR-2 (`appVersion` equals the pubspec version) *(FR-002)*
- [x] T009 [P] [US3] `test/project/macos_config_test.dart`: rules PR-3 to PR-6 (entitlements contain exactly what's allowed, no `DEVELOPMENT_TEAM`, no Podfile) *(FR-004, FR-005, FR-012)*
- [x] T010 [P] [US1] `test/project/identity_test.dart`: rules PR-7 and PR-8 (identifiers and display name on all three OSes) *(FR-002, FR-003)*
- [x] T011 [P] [US4] `test/core/app_info_test.dart`: T-core *(FR-009)*
- [x] T012 [P] [US5] `test/ui/home_screen_test.dart`: T-home (shows the name and version, no overflow at 960×640 in light and dark) *(FR-002, FR-010, FR-011)*
- [x] T013 Run `fvm flutter test` and confirm T007–T012 **fail** for the expected reasons. Record the output in the commit message *(Art. VII)*

## Phase 4: US1/US4 core and UI

- [x] T014 [US4] `lib/core/app_info.dart`: `appName = 'HealthBench Evals'` and `appVersion = '0.1.0'`, pure Dart. T008 and T011 now pass *(FR-002)*
- [x] T015 [US1] `lib/app.dart`: `HealthBenchApp` (`MaterialApp`, title `appName`, Material 3 light and dark themes from one seed colour, `ThemeMode.system`) *(FR-010)*
- [x] T016 [US1] `lib/ui/home_screen.dart`: name (headline) and "Version 0.1.0", centred, cannot overflow. `lib/main.dart` runs `HealthBenchApp`. T012 now passes *(FR-002, FR-011)*
- [x] T017 [US4] Confirm T007 passes (the core has no Flutter imports) *(FR-008)*

## Phase 5: US3 macOS permissions

- [x] T018 [US3] Add `com.apple.security.network.client` and `com.apple.security.files.user-selected.read-write` to `macos/Runner/DebugProfile.entitlements` **and** `macos/Runner/Release.entitlements`. T009 now passes *(FR-004)*
- [x] T019 [US3] Confirm `project.pbxproj` still has `CODE_SIGN_IDENTITY = "-"` and no `DEVELOPMENT_TEAM`. Build once with no signing identity configured *(FR-005)*

## Phase 6: US1/US5 native names, identifiers and window size

- [x] T020 [P] [US1] macOS: in `macos/Runner/Configs/AppInfo.xcconfig`, set `PRODUCT_NAME = HealthBench Evals` and set the copyright line. In `macos/Runner/MainFlutterWindow.swift`, set `contentMinSize` to 960×640 *(FR-002, FR-011)*
- [x] T021 [P] [US1] Windows: in `windows/runner/main.cpp`, set the window title to "HealthBench Evals". In `windows/runner/Runner.rc`, set `CompanyName`, `ProductName`, `FileDescription` and `LegalCopyright` per R2. In `windows/runner/flutter_window.cpp`, handle `WM_GETMINMAXINFO` for 960×640 logical pixels, scaled by DPI *(FR-002, FR-003, FR-011)*
- [x] T022 [P] [US1] Linux: in `linux/CMakeLists.txt`, set `APPLICATION_ID "io.github.carlos-dev-research.healthbench"`. In `linux/runner/my_application.cc`, set the header-bar and window titles to "HealthBench Evals" and add the 960×640 minimum geometry hint *(FR-002, FR-003, FR-011)*
- [x] T023 Run `fvm flutter test`: all tests from T007–T012 pass. Run `fvm flutter run -d macos` and check the title, name and version by hand *(FR-001)*

## Phase 7: Integration test and CI (US1, US2)

- [x] T024 [US1] `integration_test/app_test.dart`: T-launch (launch the app, find the name and version). Run it with `fvm flutter test integration_test -d macos` *(FR-001, FR-009)*
- [x] T025 [US2] `.github/workflows/ci.yml` as the contract specifies: matrix of 3 OSes, `fail-fast: false`, version read from `.fvmrc`, Flutter cloned and cached, Linux packages and xvfb, then format, analyze, tests, integration test, release build, and `lipo` on macOS *(FR-006, FR-007, NFR-001, NFR-004)*
- [x] T026 [US2] Push to `main` and check that all three jobs are green, each step is named, and each job takes 15 minutes or less. Fix any platform-specific failures (Windows and Linux are only checked here) *(FR-006, FR-001)*

## Phase 8: Polish and verification

- [x] T027 [P] README: replace "Getting started" with how to run the app and the tests, and add the CI status badge *(FR-013)*
- [x] T028 [P] CLAUDE.md "Current status": the app code exists; add the project-rules tests to the conventions *(Art. XII.3)*
- [x] T029 Run `./tool/setup.sh --check`: Step 7 runs `pub get`, and Step 9 passes all checks including entitlements *(FR-012, US1-3)*
- [x] T030 Run quickstart Q1–Q10 on macOS (Q10 at least the local part, which covers US2-2) and record the results at the bottom of this file. If the owner signs off, set spec and tasks to **Done** *(Verify phase)*

## Dependencies

```
T001 → T002 → T003 → T004–T006 → T007–T012 [P] → T013
T013 → T014 → T015 → T016 → T017
T013 → T018 → T019
T013 → T020, T021, T022 [P] → T023
T016 + T023 → T024 → T025 → T026
T026 → T027, T028 [P] → T029 → T030
```

## Traceability

| Requirement | Tasks |
|---|---|
| FR-001 | T003, T023, T024, T026 |
| FR-002 | T005, T008, T010, T012, T014, T016, T020–T022 |
| FR-003 | T010, T021, T022 |
| FR-004 | T009, T018 |
| FR-005 | T009, T019 |
| FR-006 / FR-007 | T025, T026 |
| FR-008 | T007, T017 |
| FR-009 | T006, T011, T012, T024 |
| FR-010 | T012, T015 |
| FR-011 | T012, T016, T020–T022 |
| FR-012 | T009, T029 |
| FR-013 | T027 |
| NFR-001 / NFR-004 | T025, T026 |
| NFR-002 | T016 (no network code), Q7 |
| NFR-003 | T004 |

## Analyze pass (2026-10-17)

- Every FR-001…FR-013 and NFR-001…NFR-004 maps to at least one task (see Traceability).
- Every user story has tasks: US1 8, US2 2, US3 3, US4 4, US5 1, plus quickstart Q3, Q4 and Q7.
- Gap fixed: US2-2 (a failure names its step) was only in quickstart Q10, which T030 now includes.
- Note: T007–T013 are committed locally but not pushed until T026, so `main` on GitHub never has failing tests.
- No `[NEEDS CLARIFICATION]` markers remain.

## Verification log

*(filled in by T030)*

## Automated verification (2026-10-18)

Everything in this feature's manual checks that tests can reach is now automated: see the "Already verified automatically" section of [003 quickstart](../003-evaluation-ui/quickstart.md). T030 stays open until the owner has checked the visual items and a real-endpoint run.

## Owner sign-off (2026-10-18)

The owner signed off and closed this feature on 2026-10-18. The automated checks pass in CI on macOS, Windows and Linux. The owner then tested the v0.2.0 release app with a real endpoint (`openai/gpt-oss-20b` on Groq, as model and grader): two 50-conversation runs completed, on HealthBench Consensus (score 0.880) and HealthBench Hard (score 0.201). Their run files are in [results/](../../results/). The quickstart rows were not ticked one by one; it stays available as a checklist.
