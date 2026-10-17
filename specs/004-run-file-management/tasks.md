# Tasks: 004 run file management

**Status:** Draft, pending approval · **Plan:** [plan.md](plan.md)

- [ ] T001 [US1–US3] `test/core/run_library_ops_test.dart` first:
  - checkImport: a valid file; rejected files (pattern, content, a dataset file); a name that already exists; a source already in the runs folder; a cut-off tail.
  - importRun: copies the file and leaves the original as is; replace; refuses while active; no `.importing` file left behind.
  - exportRun: byte-identical copy; refused while active.
  - deleteRun: removes the file; refused while active. *(FR-002–FR-006)*
- [ ] T002 Implement the core operations and `RunActiveException` in `lib/core/run_library.dart`. T001 passes
- [ ] T003 UI seams `importPickerProvider` and `exportLocationProvider` in `lib/ui/state/providers.dart` *(plan 6)*
- [ ] T004 [US3] Import button in the runs list header: pick, check, ask before replacing, import, refresh, select, show the result. Widget tests *(FR-001, FR-004–FR-008)*
- [ ] T005 [US1, US2] Export and Delete in the run detail header (hidden while running); confirmation dialog; Delete on skipped files; result messages. Widget tests *(FR-001–FR-003, FR-007, FR-008)*
- [ ] T006 Full checks, push, CI green on all three OSes; README usage and CLAUDE status
- [ ] T007 Quickstart for the owner, with the real dialogs: export to Desktop, delete, import the exported copy back, import an invalid file, and the same-name replace prompt
