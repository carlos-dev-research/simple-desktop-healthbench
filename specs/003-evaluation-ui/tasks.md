# Tasks: 003 evaluation UI

**Status:** Approved (delegated) · In progress · **Plan:** [plan.md](plan.md)

- [x] T001 Add the dependencies `flutter_riverpod`, `path_provider`, `file_selector` and `markdown`. macOS build creates no Podfile; all rule tests pass *(R1)*
- [x] T002 [P] Core `run_summary.dart`: tests first (counts, positive/negative met, histogram bins including <0 and 1.0, earned/possible, search) *(FR-011, FR-012)*
- [x] T003 [P] Core `run_library.dart`: tests first (newest first, rejected files with reasons, missing folder, non-run files ignored) *(FR-009, FR-010)*
- [x] T004 Markdown renderer `lib/ui/markdown/markdown_view.dart`: widget tests first (headings, lists, emphasis, code, tables; HTML stays literal; links not tappable; images as text) *(FR-015)*
- [x] T005 State: `providers.dart`, `runs_controller.dart`, `run_controller.dart` (start, resume, stop, progress; one run at a time; remembered form fields without the key) with tests *(FR-003, FR-004, FR-006–FR-008, FR-014)*
- [x] T006 Shell, with the navigation rail, the app name and version, and the notes footer. Replace `home_screen.dart` and move its tests *(FR-001, FR-016, 001 FR-002)*
- [x] T007 Runs view, run detail, histogram, conversation list (search, sort, paging) and conversation view, with widget tests *(US3)*
- [x] T008 New-run form (validation, dataset picker seam, count shown), progress panel, stop, and the Continue dialog, with widget tests *(US1, US2, US4)*
- [x] T009 Integration test `integration_test/evaluation_flow.dart`: fill the form, run against the fake server, finish, open the run and a conversation *(NFR-004)*
- [x] T010 Docs (README usage, CLAUDE status), full checks, push, CI green on all three OSes
- [ ] T011 Hand over to the owner: quickstart for the first UI test, including a real endpoint on the release build (carries 001 US3-3)

## Automated verification (2026-10-18)

Everything in this feature's manual checks that tests can reach is now automated: see the "Already verified automatically" section of [003 quickstart](../003-evaluation-ui/quickstart.md). T011 stays open until the owner has checked the visual items and a real-endpoint run.

