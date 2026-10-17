# Quickstart: validating 001 on macOS

Manual checks for the acceptance scenarios that automated tests can't fully cover.
Run them from the repo root on a Mac where `./tool/setup.sh` has completed.

| # | Scenario | Steps | Expected |
|---|---|---|---|
| Q1 | US1-1 Launch | `fvm flutter run -d macos`, and time it | A window titled **HealthBench Evals** opens within 60 s. The home screen shows the name and `0.1.0` |
| Q2 | US1-3 Setup check | `./tool/setup.sh --check` | Step 9: all checks pass, including both entitlements files and "No CocoaPods Podfile" |
| Q3 | US5-2 Minimum size | Drag the window corner as small as it will go | It stops at 960 × 640. Nothing overflows (no yellow and black stripes) |
| Q4 | US5-1 Theme | System Settings → Appearance → Light / Dark, with the app open | The app switches theme immediately |
| Q5 | US3-1 Permissions | `fvm flutter build macos --release`, then `codesign -d --entitlements - "build/macos/Build/Products/Release/HealthBench Evals.app"` | Only `app-sandbox`, `network.client` and `files.user-selected.read-write` |
| Q6 | US3-3 Outgoing network (amended) | Same `codesign` output as Q5 | Contains `com.apple.security.network.client` = true. The real request is verified in feature 002 |
| Q7 | US5-3 No network at launch | Launch the release app with a network monitor (for example Little Snitch or LuLu), or check that `lib/` contains no networking code | No connections are attempted |
| Q8 | NFR-004 Universal | `lipo -archs "build/macos/Build/Products/Release/HealthBench Evals.app/Contents/MacOS/HealthBench Evals"` | `x86_64 arm64` |
| Q9 | US2 CI | Push to `main`, then open the Actions tab | Three jobs (macOS, Windows, Linux), each with named steps, all green, each within 15 minutes |
| Q10 | US2-2 Red build (optional) | Locally: add a formatting error, then run `fvm dart format --output=none --set-exit-if-changed .` and revert. In CI, run the workflow manually (`workflow_dispatch`) on a scratch branch that contains the error | The command exits non-zero. In CI, all three jobs fail at the **format** step |
