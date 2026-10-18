# Flutter desktop reference

Platform facts that plans and tasks for this app need. **Decisions belong in a
feature's `plan.md`, not here.** Package names below are *candidates* to check
on pub.dev during planning. Confirm each one is maintained and supports all three
desktop platforms before adopting it.

Docs: https://docs.flutter.dev/platform-integration/desktop

Versions at the time of writing (October 2026): **Flutter 3.47 stable / Dart 3.13**.
The next stable release (3.50) is expected in November 2026. Pin the versions the
project actually uses in `pubspec.yaml` (`environment:`). Commit `pubspec.lock`,
because this is an app.

---

## 1. Targets and toolchains

| OS | Build toolchain | Notes |
|---|---|---|
| macOS | Xcode (full app, not just Command Line Tools). **No CocoaPods** | `./tool/setup.sh` does the Xcode setup. Since Flutter 3.44, macOS plugins come through **Swift Package Manager** by default. CocoaPods is only a fallback for plugins without SwiftPM support (see §4) |
| Windows | Visual Studio (not VS Code) with the **"Desktop development with C++"** workload | Builds only on Windows |
| Linux | `clang cmake ninja-build pkg-config libgtk-3-dev` (+ `libsecret-1-dev` if a keyring plugin is used) | Builds only on Linux |

Each desktop target can only be built **on its own OS**. Use CI (for example,
GitHub Actions with macOS, Windows and Ubuntu runners) to build and test the
platforms you are not working on.

Common commands:

```sh
flutter doctor -v                      # check the toolchain
flutter devices                        # should list "macos" (or windows/linux)
flutter create --platforms=macos,windows,linux --org <reverse.domain> .
flutter run -d macos                   # debug run
flutter build macos                    # release build (windows / linux likewise)
flutter analyze                        # static analysis (must be clean)
dart format .                          # formatting
flutter test                           # unit + widget tests
flutter test integration_test          # integration tests on the desktop device
```

---

## 2. macOS sandbox and entitlements (important)

macOS builds are **sandboxed by default**. The entitlements are in
`macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`.
**Make the same change in both files.** Edit them directly; Xcode's UI may update
only one.

This app needs:
- `com.apple.security.network.client` for **outgoing HTTP to model APIs**. Without
  it, requests fail with `SocketException: Connection failed (OS Error: Operation not permitted, errno = 1)`.
  A common trap is that it works in debug but fails in release.
- `com.apple.security.files.user-selected.read-write` for choosing a dataset file or results folder through the system dialog.
- Optionally, `com.apple.security.files.downloads.read-write` if datasets are saved to Downloads.

Inside the sandbox, the app's own storage is under
`~/Library/Containers/<bundle-id>/Data/...`. Use the platform directory API
instead of hard-coding paths. A folder outside the container that the user
picks would need a **security-scoped bookmark** for access to persist across
launches. That is one reason runs are stored inside the container (§2.1).

### 2.1 Where runs are stored (decided)

Runs are stored **inside the app's own storage** (the sandbox container on
macOS), in the **app's own run-file format**. That format is a revision of the
reference format and is deliberately **not compatible** with it (see
[healthbench.md §6](healthbench.md)). The format itself is defined in the first
storage feature's `data-model.md` and `contracts/`.

For each run file, the app offers:
- **Delete**: removes the run file from the app's storage.
- **Export**: saves a copy of the run file to a location the user chooses.
- **Import**: adds a run file back in, such as one exported earlier, saved from another machine, or kept from an older session. It is accepted **only if it matches the run-file format and file-name pattern**. Files that don't match are rejected with a clear reason, and nothing is half-imported.

None of this needs permanent access to user folders.

| OS | App support directory (`getApplicationSupportDirectory()`) |
|---|---|
| macOS (sandboxed) | `~/Library/Containers/<bundle-id>/Data/Library/Application Support/<bundle-id>/` |
| Windows | `%APPDATA%\<company>\<app>\` |
| Linux | `~/.local/share/<app-id>/` (XDG data home) |

Implications:
- **Export** uses the native *save* dialog (`file_selector` `getSaveLocation`), and **import** uses the *open* dialog (`openFile`, filtered to the run-file extension). Both use only files the user picked, which needs `com.apple.security.files.user-selected.read-write` and nothing broader.
- **Import** copies the file into the container. The original is never moved or changed. Validate the whole file (structure, required fields, value types, file-name pattern) before writing anything. Treat its content as untrusted: Markdown is rendered safely, and huge files and lines are size-limited.
- **Delete** asks for confirmation, and it cannot apply to a run that is still in progress.
- Debug builds are sandboxed too, so `fvm flutter run` writes to the same container as a release build with the same bundle id.
- Deleting the `.app` does **not** delete the container. The README tells users how to remove their data.
### 2.2 Run-file decisions (2026-10-17)

| Topic | Decision |
|---|---|
| Format | **One `.jsonl` file per run.** It has a header line with the run metadata (models, effort, dataset, status; **never** the API key), then **one line per graded conversation, appended and flushed as each finishes** |
| Stop / continue | A run can be **stopped** and later **continued where it left off**: the app skips conversations already in the file and appends the rest. The API key is held in memory only: it is reused within the same app session and must be entered again after the app is closed (constitution III.1). When continuing, a truncated last line (from a crash or force-quit) is detected and discarded rather than breaking the file |
| File name | Must contain the run's **timestamp**. The exact pattern (prefix, timestamp format, extension) is fixed in the storage contract, and import checks it |
| Import name clash | If a run file with the **same name** already exists, ask the user, then **replace** it after they confirm. Replacing is not allowed while that run is in progress |
| Format versioning | **Not for now.** There is no `formatVersion` field. Revisit if the format changes after release |

Settled in [004 spec](../../specs/004-run-file-management/spec.md) (Clarifications): an imported run that was stopped part-way can be **continued** with the same Continue action, given the same dataset (checked by SHA-256).

Distributing outside the App Store needs the Hardened Runtime and notarization
(an Apple Developer ID). That is out of scope until a release spec covers it.

---

## 3. Cross-platform concerns relevant to this app

| Concern | Guidance | Candidate packages |
|---|---|---|
| App data location | Runs go in the app support directory (§2.1). Never hard-code paths | `path_provider` |
| File and folder pickers | Native dialogs. On macOS this needs the sandbox entitlement above | `file_selector` |
| HTTP to OpenAI-compatible APIs | Plain JSON over HTTPS (`POST {baseUrl}/chat/completions`). Implement retries, backoff and timeouts ourselves rather than relying on an SDK | `http`, `dio` |
| Secrets (API key) | If the key is ever stored, use the OS keychain or credential store, never plain prefs. Linux needs libsecret | `flutter_secure_storage` |
| Non-secret settings | Small key/value preferences | `shared_preferences` |
| Large JSONL parsing / scoring | The oss_eval file is tens of MB. Parse and aggregate off the UI isolate | `Isolate.run` (dart:isolate) |
| Long-running runs | Network I/O is async and doesn't need an isolate. Keep the UI responsive and stream progress events. Write each result line **immediately** (append + flush) | dart:io `IOSink` |
| Markdown rendering | Model output is untrusted. Render without raw HTML and without loading remote images | check the current status of `flutter_markdown` vs `flutter_markdown_plus` / `markdown_widget` |
| Charts (histogram, breakdowns) | Plain widgets or `CustomPaint` may be enough | `fl_chart` |
| Window size and title | Minimum size, remembering position | `window_manager` |
| State management | Choose in the first plan and record it in the constitution | `provider`, `riverpod`, `bloc`, or plain `ChangeNotifier`/`ValueNotifier` |
| Models and JSON | Hand-written `fromJson`/`toJson` vs code generation | `json_serializable`, `freezed` |
| Linting | Start from the official lints and tighten later | `flutter_lints` |

Desktop UX expectations: keyboard shortcuts (`Shortcuts`/`Actions`), focus
traversal, hover states, resizable layouts, text selection in conversation
views, and light and dark themes (Material 3).

---

## 4. Native dependencies: Swift Package Manager only (no CocoaPods)

- Since Flutter 3.44, macOS (and iOS) plugins are integrated with **Swift Package Manager** by default. Flutter falls back to CocoaPods only for plugins that lack SwiftPM support.
- **Project rule:** only adopt plugins that support SwiftPM on macOS. Check each candidate package during planning. If a plugin generates `macos/Podfile`, `tool/setup.sh` warns about it.
- Why it matters: installing CocoaPods through Homebrew pulls in Homebrew's `ruby` and `openssl@4`. These are linked into `/opt/homebrew/bin`, which comes **before** `/usr/bin` on PATH, so they silently replace `ruby`/`gem`/`bundle` and `openssl` in every terminal. On top of that, the CocoaPods registry becomes read-only on 2 December 2026.

## 5. Development machine safety (setup script rules)

`tool/setup.sh` must never surprise the developer's machine. Any change to it must keep these rules:

- Ask before each change. Never edit shell profiles. Never run as root.
- Homebrew runs with `HOMEBREW_NO_AUTO_UPDATE`, `HOMEBREW_NO_INSTALL_CLEANUP`, `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` and `HOMEBREW_NO_INSTALL_UPGRADE` set. The user sees a `--dry-run` preview first. Installed tools are never upgraded or removed.
- Only add a Brewfile entry after checking what it links into PATH (`brew info`, `--dry-run`). Formulae that shadow system or existing commands (ruby, python, openssl, node, git…) are not acceptable.
- `.fvmrc` turns off FVM's automatic edits of `.gitignore`, `.vscode/settings.json` and Melos config. The repo ships those files itself.
- The summary lists every change made, with its undo command.

## 6. Testing layers

- **Unit tests** (`test/`): the parser, scorer, JSON extraction, retry policy and storage format. These are pure Dart with no Flutter imports, and they run fastest.
- **Widget tests** (`test/`): screens with fake services.
- **Integration tests** (`integration_test/`): the real app on the desktop device, using a **local fake OpenAI-compatible server** so tests never call a paid API.
- **Golden tests**: optional. They are fragile across operating systems, so if used, generate them on one OS only.
- Keep fixtures in `test/fixtures/`: a handful of dataset lines, valid run files, and **invalid** run files (wrong pattern, missing fields, bad types, truncated) for the import validation tests.
