# Plan: 004 run file management

**Status:** Approved · In progress · **Date:** 2026-10-17 · **Spec:** [spec.md](spec.md) (Approved) · **Constitution:** v1.0.0

## Technical context

| Item | Choice |
|---|---|
| New dependencies | None. `file_selector` (already used) provides `openFile` and `getSaveLocation` |
| Permissions | None new. `files.user-selected.read-write` already covers the open and save dialogs (NFR-003) |
| Core additions | `lib/core/run_library.dart`: `checkImport`, `importRun`, `exportRun`, `deleteRun`, plus `RunActiveException` |
| UI additions | An Import button in the runs list header. Export and Delete in the run detail header. Delete on skipped files. Confirmation dialogs and result messages (snack bars) |

## Design decisions

1. **Validation reuses the run-file reader.** `checkImport` runs `readRunFile` on the chosen file in another isolate (NFR-001). It returns either the valid contents and the target path (`<runs>/<same file name>`), with whether that name already exists, or the rejection reason. No separate validator means import can never accept something the app can't read.
2. **Import is atomic.** The file is copied to `<target>.importing`, re-validated there, then renamed over the target. A crash or a full disk never leaves a half-written run under a valid name. A stray `.importing` file isn't a `.jsonl`, so the list ignores it.
3. **Active runs are protected in the core.** `deleteRun`, `exportRun` and `importRun` (replace) throw `RunActiveException` if the target is in the active-run registry. The UI also hides or disables the actions, but the core is the guarantee.
4. **Export is a byte copy** (`File.copy`) to the location the user picked, so the copy is identical to the stored file (FR-002).
5. **Importing a file that is already in the app's storage** (the source path equals the target) is reported as "This run is already in the app" and nothing is changed.
6. **Testing seams:** `importPickerProvider` (open dialog) and `exportLocationProvider` (save dialog) can be overridden in tests, like the dataset picker.
7. **After any action**, `runsProvider` is refreshed. A delete clears the selection, and an import selects the imported run.

## Constitution check

| Article | Result | Notes |
|---|---|---|
| III Privacy | ✅ | Files hold no key (002). Exported copies are identical |
| IV Untrusted content | ✅ | Full validation before writing. Errors are shown, never crashes |
| V Run-file integrity | ✅ | V.3 (validate first, replace after confirmation, never while running) and V.4 (delete confirms; export only to the chosen location) are implemented as written |
| VI Architecture | ✅ | File operations are in the pure-Dart core. The UI only calls them |
| VII Testing | ✅ | Core tests first. Widget tests use the picker seams |
| VIII/IX/X | ✅ | Cross-platform `dart:io`, no new packages, no extras |

**Complexity Tracking:** none.

## Phases

1. Core operations, test-first: import (valid, invalid, same name, replace, active, own folder, cut-off tail), export, delete (active refused).
2. UI: seams, buttons, dialogs and messages, with widget tests.
3. Checks, CI, and a quickstart for your manual test with the real dialogs.
