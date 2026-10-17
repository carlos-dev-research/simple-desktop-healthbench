# Feature: Project scaffold

**Status:** Approved · **Date:** 2026-10-17 · **Constitution:** v1.0.0

## Summary

Create the empty desktop application that every later feature builds on. A
developer can clone the repository on macOS, run the documented setup, and
launch a native app window. Every change pushed to `main` is checked
automatically on macOS, Windows and Linux. The app starts with the minimum
operating-system permissions it will need (outgoing network access and files
the user picks), and the project layout keeps the evaluation logic separate
from the user interface from the first commit. The app has no evaluation
features yet; the window shows only the app's name and version.

## User stories

### US1 (P1): Build and launch on a clean Mac

As a **developer**, I want to clone the repository, run the setup and launch the
app, so that I can start working on features without any manual configuration.

Acceptance scenarios:
1. **Given** a Mac with Xcode installed and the setup script completed, **when** the developer runs the documented launch command, **then** a native app window opens within 60 seconds and shows the app's display name and version.
2. **Given** a developer with no personal Apple signing identity, **when** they build and launch the app, **then** it builds and runs without any change to project files.
3. **Given** the project, **when** the setup script runs its final verification, **then** every check passes, including the checks on app permissions and dependency management.

### US2 (P1): Automated checks on all three platforms

As the **project owner**, I want every push to `main` to be checked
automatically on macOS, Windows and Linux, so that no platform silently breaks
(Constitution, Article VIII).

Acceptance scenarios:
1. **Given** a push to `main`, **when** the automated checks run, **then** for each of macOS, Windows and Linux they report pass or fail for: static analysis (zero issues), formatting (no changes needed), all tests, and a release build.
2. **Given** a change that introduces an analysis issue, a formatting difference, or a failing test, **when** it is pushed, **then** the check fails on every platform where the problem occurs, and the failure names the step that failed.
3. **Given** the checks, **when** they set up the toolchain, **then** they use exactly the Flutter version pinned for the project (the same one developers use).

### US3 (P1): Least-privilege macOS permissions

As a **user**, I want the app to ask the operating system only for the
permissions it needs, so that it can't reach anything else on my Mac.

Acceptance scenarios:
1. **Given** the macOS app, **when** its permissions are inspected, **then** it can make outgoing network connections and read and write files the user chose, and nothing else. In particular, it cannot accept incoming network connections in release builds.
2. **Given** debug and release builds, **when** their user-granted permissions are compared, **then** they are identical. The only exceptions are the debugging allowances the development tools require, which exist only in debug builds.
3. **Given** a release build, **when** it makes an outgoing HTTPS request, **then** the request is not blocked by the sandbox. This is checked in the manual validation steps.

### US4 (P2): Core and UI kept apart

As a **developer**, I want the project structure to keep the evaluation logic
(the core) separate from the user interface, and to enforce that separation
automatically, so that the core stays testable without a device (Constitution,
Article VI).

Acceptance scenarios:
1. **Given** the project, **when** the tests run, **then** a check fails if any core code depends on the UI framework.
2. **Given** the project, **when** the tests run, **then** at least one example of each test kind runs: a core unit test, a UI (widget) test, and an integration test that launches the real app. This proves each kind works on every platform.

### US5 (P3): Desktop window basics

As a **user**, I want the app window to behave like a normal desktop app, so
that it is comfortable to use.

Acceptance scenarios:
1. **Given** the app is running, **when** the system appearance is light or dark, **then** the app follows it.
2. **Given** the app window, **when** the user resizes it, **then** it cannot be made smaller than the minimum size, and the content never overflows at that size.
3. **Given** the app, **when** it is launched, **then** it makes no network requests and sends no telemetry (Constitution, Article III).

## Functional requirements

- **FR-001** The app MUST build and launch on macOS, Windows and Linux from a clean clone, with the documented setup as the only preparation.
- **FR-002** The window title and home screen MUST show the display name **"HealthBench Evals"**. The home screen MUST also show the app version.
- **FR-003** The app MUST use the application identifier **`io.github.carlos-dev-research.healthbench`** on every OS. This identifier decides where the app stores its data, so changing it later would orphan users' runs.
- **FR-004** The macOS app MUST request only outgoing network access and access to files the user selects, and these MUST be the same in debug and release builds (apart from debug-only development allowances).
- **FR-005** Building MUST NOT require a personal code-signing identity, and project files MUST NOT contain one.
- **FR-006** Every push to `main` MUST trigger automated checks on macOS, Windows and Linux: static analysis, formatting, tests, and a release build. The result of each step MUST be visible.
- **FR-007** The automated checks MUST use the Flutter version pinned for the project.
- **FR-008** An automated test MUST fail if core code depends on the UI framework.
- **FR-009** The test suite MUST include at least one passing core unit test, one widget test, and one integration test that launches the app.
- **FR-010** The app MUST follow the system's light or dark appearance.
- **FR-011** The window MUST have a minimum size of **960 × 640** logical pixels.
- **FR-012** The project MUST NOT use CocoaPods, and the setup script's final verification MUST pass with the project present.
- **FR-013** The README MUST explain how to launch the app and run the tests.

## Non-functional requirements

- **NFR-001** The automated checks SHOULD finish within 15 minutes per platform.
- **NFR-002** The app MUST make no network requests and collect no telemetry at launch.
- **NFR-003** Static analysis MUST use the official Flutter lint rules or stricter.
- **NFR-004** The app MUST work on both Apple Silicon and Intel Macs.

## Key entities

None. This feature contains no domain data.

## Edge cases

- A developer has no Apple Developer account or signing team.
- Linux check machines lack the GUI libraries needed to build or to run the integration test.
- Integration tests on the check machines have no visible display and must still run, or be explicitly skipped with a reason.
- A fork or a contributor's clone has a different Flutter version installed globally. The pinned version must still be used.
- A push breaks only one platform. That platform's check must fail even if the others pass.

## Out of scope

- Any evaluation, results, dataset or run-file features (planned for features 002–005).
- Installers, packaging, code signing for distribution, notarization, app stores and auto-update.
- iOS, Android and web targets.
- Localization: the interface is English only (Constitution, Article X).
- A custom app icon. The default icon is kept for now.
- Downloadable build artifacts from the automated checks. The checks only report pass or fail; publishing builds belongs to a later release feature.

## Clarifications

### 2026-10-17
- **Q:** Display name? → **A:** "HealthBench Evals" (FR-002).
- **Q:** Application identifier? → **A:** `io.github.carlos-dev-research.healthbench` (FR-003).
- **Q:** Minimum window size? → **A:** 960 × 640 (FR-011).
- **Q:** Should the automated checks publish downloadable builds? → **A:** No, pass/fail only (Out of scope).
- **Q:** App icon? → **A:** Keep the default icon for now (Out of scope).
