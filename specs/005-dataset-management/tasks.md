# Tasks: 005 dataset management

**Status:** Draft, pending approval · **Plan:** [plan.md](plan.md) · Depends on 006 T002 (`seeded_random.dart`)

- [ ] T001 Tests first: `test/core/dataset_library_test.dart`: pinned list; download (ok, mismatch rejected, cancel, HTTP error, no partial file); add (valid, invalid, same file, name clash); sample (deterministic, byte-identical lines, order, out-of-range N, sample of a sample); index; delete
- [ ] T002 Implement `lib/core/dataset_library.dart`. T001 passes
- [ ] T003 Providers: `datasetHostProvider`, `addFilePickerProvider`, `datasetLibraryProvider` (list and refresh), download state per official file
- [ ] T004 Datasets view (third rail destination): Official section with download, progress and cancel; Library section with Sample… (N, seed 40) and Delete; Add file…. Widget tests
- [ ] T005 New run: library dropdown plus "Choose file…"; Continue auto-selects by SHA-256; delete is refused for the active run's dataset. Widget tests
- [ ] T006 Integration test: download from the local fake host, sample, run on the sample, in the real app
- [ ] T007 Docs (README: datasets inside the app; the curl steps become optional), dist zip rebuilt, checks, CI
- [ ] T008 Quickstart for the owner: a real download of the three files, sample, run
