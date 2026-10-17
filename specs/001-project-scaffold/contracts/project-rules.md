# Contract: project rules and CI

These are the checks feature 001 puts in place. Every later feature must keep them passing.

## Project-rules tests (`test/project/`, plain Dart, run on every OS)

| ID | Rule | Requirement |
|---|---|---|
| PR-1 | No file under `lib/core/` imports `package:flutter/…`, `dart:ui` or `package:flutter_riverpod/…` | FR-008, Art. VI |
| PR-2 | `appVersion` in `lib/core/app_info.dart` equals the `version:` in `pubspec.yaml` (without the `+build` part) | FR-002 |
| PR-3 | `DebugProfile.entitlements` and `Release.entitlements` both contain `app-sandbox`, `network.client` and `files.user-selected.read-write` | FR-004 |
| PR-4 | `Release.entitlements` contains no other keys. `DebugProfile.entitlements` may also contain only `cs.allow-jit` and `network.server` | FR-004, US3 |
| PR-5 | `macos/Runner.xcodeproj/project.pbxproj` contains no `DEVELOPMENT_TEAM` | FR-005 |
| PR-5b | The Runner **Release** build configuration sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`, so ad-hoc signing does not inject `get-task-allow` into release builds *(added during T023)* | FR-004, US3 |
| PR-6 | `macos/Podfile` does not exist | FR-012 |
| PR-7 | The macOS `PRODUCT_BUNDLE_IDENTIFIER` and the Linux `APPLICATION_ID` both equal `io.github.carlos-dev-research.healthbench`, and the Windows `CompanyName`/`ProductName` equal `io.github.carlos-dev-research` / `healthbench` | FR-003 |
| PR-8 | The display name "HealthBench Evals" appears in macOS `PRODUCT_NAME`, in the Windows window title and `FileDescription`, in the Linux window title, and in `appName` | FR-002 |

## App tests

| ID | Kind | Checks | Requirement |
|---|---|---|---|
| T-core | Unit | `appName == 'HealthBench Evals'`, and `appVersion` is a valid `x.y.z` version | FR-009 |
| T-home | Widget | The home screen shows the name and version. There are no overflow errors at 960 × 640, in both light and dark themes | FR-002, FR-010, FR-011, US5 |
| T-launch | Integration | The real app launches, and the name and version are visible | FR-001, FR-009 |

## CI workflow (`.github/workflows/ci.yml`)

- **Triggers:** `push` to `main`, and `workflow_dispatch`.
- **Matrix:** `macos-latest`, `windows-latest`, `ubuntu-latest`. `fail-fast: false`, so one platform's failure doesn't hide the others.
- **Steps per OS:** each one is named so it shows in the results (FR-006):

1. Checkout
2. Read the Flutter version from `.fvmrc`
3. Install Flutter (cached)
4. Linux only: install system packages
5. `flutter pub get`
6. `dart format --output=none --set-exit-if-changed .`
7. `flutter analyze --fatal-infos`
8. `flutter test` (unit, widget and project rules)
9. `flutter test integration_test -d <os>` (on Linux, run under `xvfb-run`)
10. `flutter build <os> --release`
11. macOS only: `lipo -archs` includes `arm64` and `x86_64` (NFR-004)

- Uses only GitHub-owned actions (`actions/checkout`, `actions/cache`).
- Target duration: 15 minutes or less per platform (NFR-001).
