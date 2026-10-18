# Tasks: 005 dataset management

**Status:** Done (owner sign-off 2026-10-18) · **Plan:** [plan.md](plan.md) · Depends on 006 T002 (`seeded_random.dart`)

- [x] T001 Tests first: `test/core/dataset_library_test.dart`: pinned list; download (ok, mismatch rejected, cancel, HTTP error, no partial file); add (valid, invalid, same file, name clash); sample (deterministic, byte-identical lines, order, out-of-range N, sample of a sample); index; delete
- [x] T002 Implement `lib/core/dataset_library.dart`. T001 passes
- [x] T003 Providers: `datasetHostProvider`, `addFilePickerProvider`, `datasetLibraryProvider` (list and refresh), download state per official file
- [x] T004 Datasets view (third rail destination): Official section with download, progress and cancel; Library section with Sample… (N, seed 40) and Delete; Add file…. Widget tests
- [x] T005 New run: library dropdown plus "Choose file…"; Continue auto-selects by SHA-256; delete is refused for the active run's dataset. Widget tests
- [x] T006 Integration test: download from the local fake host, sample, run on the sample, in the real app
- [x] T007 Docs (README: datasets inside the app; the curl steps become optional), dist zip rebuilt, checks, CI
- [x] T008 Quickstart for the owner: a real download of the three files, sample, run

## Owner sign-off (2026-10-18)

The owner signed off and closed this feature on 2026-10-18. The automated checks pass in CI on macOS, Windows and Linux. The manual checks in the quickstart were not recorded here as performed; they stay available as a checklist.
