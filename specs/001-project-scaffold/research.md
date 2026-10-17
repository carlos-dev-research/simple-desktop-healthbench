# Research: 001 project scaffold

**Date:** 2026-10-17 · **Flutter:** 3.47.7 / Dart 3.13.5 (pinned in `.fvmrc`)

Method: generated a throwaway project with
`flutter create --platforms=macos,windows,linux --org io.github.carlos-dev-research --project-name healthbench --empty`
in a scratch directory and inspected what it produced. Below are the findings and the decision for each.

---

## R1. How to create the project

| Option | Pros | Cons |
|---|---|---|
| `flutter create .` in the repo | One command | Could overwrite or merge our `.gitignore`, `README.md` and `analysis_options.yaml`. It also generates `.idea/` and `*.iml` files we don't want |
| **Generate in a temp folder, copy the selected files in** | Full control over what enters the repo | One extra step |

**Decision:** generate in a temp folder and copy in `lib/`, `macos/`, `windows/`,
`linux/`, `pubspec.yaml`, `.metadata` and `analysis_options.yaml` (then edit them).
Leave out `.idea/`, `*.iml`, its `README.md` and its root `.gitignore`. The
per-platform `macos/.gitignore`, `windows/.gitignore` and `linux/.gitignore` are kept.

## R2. Application identifier on each OS (FR-003)

Findings from the generated project:

| OS | Where the identifier lives | Generated value | Also decides the data folder? |
|---|---|---|---|
| macOS | `PRODUCT_BUNDLE_IDENTIFIER` (AppInfo.xcconfig) | `io.github.carlos-dev-research.healthbench` ✔ | Yes: `~/Library/Containers/<id>/` |
| Linux | `APPLICATION_ID` (linux/CMakeLists.txt) | `io.github.carlosdevresearch.healthbench` ✘ (**hyphens stripped**) | Yes: `~/.local/share/<application id>/` |
| Windows | `CompanyName` + `ProductName` (Runner.rc) | `io.github.carlos-dev-research` + `healthbench` | Yes: `%APPDATA%\<CompanyName>\<ProductName>\` |

Linux: GLib accepts `-` in application IDs (`g_application_id_is_valid`) but
discourages it. Flutter strips it as a precaution. Flathub's convention would
be `io.github.carlos_dev_research.healthbench`, but packaging is out of scope.

**Decision:** set Linux `APPLICATION_ID` to `io.github.carlos-dev-research.healthbench`
as FR-003 requires. It is valid for GTK. A project-rules test checks that
macOS and Linux use the same ID. If a future Flatpak feature needs underscores,
that feature amends FR-003 and plans how existing data is migrated.

Windows: `CompanyName = "io.github.carlos-dev-research"` and `ProductName = "healthbench"`.
These stay stable because they decide the data folder. The display name goes in
`FileDescription` and the window title instead. Changing the display name later
must never move user data.

## R3. Display name "HealthBench Evals" (FR-002)

| OS | Mechanism | Decision |
|---|---|---|
| macOS | `PRODUCT_NAME` sets the `.app` name, the menu bar name and, by default, the window title | `PRODUCT_NAME = HealthBench Evals` |
| Windows | `window.Create(L"…")` in `runner/main.cpp`, and `FileDescription` in Runner.rc | Both "HealthBench Evals" |
| Linux | `gtk_header_bar_set_title` and `gtk_window_set_title` in `my_application.cc` | "HealthBench Evals" |
| Dart | `MaterialApp.title` and the home screen text | Taken from one constant in the core (`appName`) |

Binary and package names stay `healthbench` (no spaces in executables or Dart package names).

## R4. Minimum window size 960 × 640 (FR-011) without a package

`window_manager` is not a Flutter Favorite (Constitution Article IX), so each
OS's own window API is used in the generated runner code:

| OS | API | Note |
|---|---|---|
| macOS | `contentMinSize = NSSize(width: 960, height: 640)` in `MainFlutterWindow.swift` | Points = logical pixels |
| Windows | Handle `WM_GETMINMAXINFO` in `FlutterWindow::MessageHandler` | Scale by the window's DPI (`GetDpiForWindow / 96`) so it's 960 × 640 *logical* |
| Linux | `gtk_window_set_geometry_hints(window, nullptr, &hints, GDK_HINT_MIN_SIZE)` | GTK uses logical pixels |

Default window size: keep the generated 1280 × 720.

## R5. Showing the app version (FR-002)

| Option | Verdict |
|---|---|
| `package_info_plus` | Adds a plugin with native code on three OSes just to show a string. Rejected (Article IX/X) |
| `--dart-define` at build time | Every build command and CI step must pass it. Easy to forget. Rejected |
| **A constant `appVersion` in the core, plus a test that it equals `version:` in `pubspec.yaml`** | No dependency. Drift is caught by the test suite on every push. **Chosen** |

## R6. Enforcing core/UI separation (FR-008)

| Option | Verdict |
|---|---|
| Separate pure-Dart package (`packages/core`) | The compiler enforces it, but there are two pubspecs, two `pub get`s and more CI steps. More than 001 needs (Article X) |
| Custom analyzer lint plugin | Needs extra packages. Rejected |
| **A test that scans `lib/core/**.dart` and fails on any `package:flutter` or `dart:ui` import** | Simple, runs everywhere. **Chosen.** If the core grows large, a later feature may switch to a separate package |

## R7. Project-rules tests

FR-004, FR-005, FR-008 and FR-012 are rules about the *project files*, not app
behaviour. They are encoded as plain-Dart tests under `test/project/` (they read
files with `dart:io`), so they run on all three CI platforms with no extra tools.
The full list is in [contracts/project-rules.md](contracts/project-rules.md).

## R8. Entitlements (FR-004, US3)

Generated:
- `DebugProfile`: `app-sandbox`, `cs.allow-jit`, `network.server`.
- `Release`: `app-sandbox` only.

`cs.allow-jit` and `network.server` are needed by the Dart VM and debugger in
debug/profile builds. These are the "debug-only development allowances" in US3.

**Decision:** add `network.client` and `files.user-selected.read-write` to **both**
files. A rule test checks that both files grant the same user-facing permissions,
that `network.server` is absent from Release, and that nothing else is granted.

## R9. Signing (FR-005)

The generated project already uses ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`)
and has no `DEVELOPMENT_TEAM`. **Decision:** keep it that way. A rule test
fails if `DEVELOPMENT_TEAM` shows up in `project.pbxproj`.

*Found during T023:* with ad-hoc ("Sign to Run Locally") signing, Xcode injects
`com.apple.security.get-task-allow` into **release** builds too. That entitlement lets other processes
attach to the app. **Decision:** set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` for the Runner
Release configuration only. Debug builds keep it, because the debugger needs it. Guarded by rule PR-5b, and verified
with `codesign`: the release build now has exactly app-sandbox, network.client and files.user-selected.read-write.

## R10. Lints (NFR-003)

The generated project uses `flutter_lints ^6.0.0` (first-party, flutter.dev).
**Decision:** keep it, and add stricter settings:
- `strict-casts`, `strict-inference` and `strict-raw-types`.
- Rules: `prefer_single_quotes`, `prefer_final_locals`, `prefer_const_constructors`, `unawaited_futures`, `directives_ordering`, `always_declare_return_types`, `avoid_dynamic_calls`. (`require_trailing_commas` was dropped during T004: since Dart 3.7 the formatter manages trailing commas itself, and the rule can conflict with `dart format`.)

Keep excluding the native platform folders from analysis.

## R11. CI toolchain (FR-006, FR-007)

| Option | Verdict |
|---|---|
| `subosito/flutter-action` (third-party) | Popular, but it's a supply-chain dependency, and it reads the version from pubspec, not `.fvmrc` |
| FVM in CI | Needs a different installer on each OS |
| **Read the version from `.fvmrc` with `sed`, then `git clone --depth 1 --branch <version>` the official Flutter repo** | Only GitHub-owned actions are used. The exact pin is guaranteed. **Chosen** |

- Actions: `actions/checkout@v7` and `actions/cache@v6` only, both GitHub-owned. The Flutter SDK and pub cache are cached, keyed on the version.
- Runners: `macos-latest`, `windows-latest`, `ubuntu-latest`. Everything runs in bash, which Windows runners provide through Git Bash.
- Linux packages (official list): `clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev`, plus `xvfb` for the integration test, which needs a display.
- Triggers: `push` to `main`, and `workflow_dispatch`.

## R12. Universal macOS binary (NFR-004)

Flutter's macOS release builds contain both architectures by default.
**Decision:** a CI step checks this with `lipo -archs` (it must contain `arm64` and `x86_64`).

## R13. Theme (FR-010)

`MaterialApp` with `theme` and `darkTheme` (Material 3, `ColorScheme.fromSeed`)
and `themeMode: ThemeMode.system`. No packages.
