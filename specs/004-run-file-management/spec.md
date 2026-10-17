# Feature: Run file management

**Status:** Approved · **Date:** 2026-10-17 · **Constitution:** v1.0.0

## Summary

From the Runs view, the user can **delete** a run, **export** it to a
location of their choice, and **import** a run file into the app. Imported
files can be ones exported earlier, saved on another machine, or kept from an
older session. Import accepts only files that match the app's run-file
format and name pattern. Everything else is rejected with the reason.

Decisions already recorded: [flutter-desktop.md §2.1–2.2](../../docs/reference/flutter-desktop.md), Constitution Article V.3–V.4.

## User stories

### US1 (P1): Export a run

As an **evaluator**, I want to save a copy of a run file wherever I choose, so
that I can keep it, share it, or move it to another machine.

Acceptance scenarios:
1. **Given** a selected run that is not running, **when** the user chooses **Export**, **then** the system save dialog opens, proposing the run's file name.
2. **Given** a location is chosen, **when** the export finishes, **then** a byte-identical copy of the run file is written there, and the app confirms it with the path. The run in the app is unchanged.
3. **Given** the user cancels the dialog, **when** it closes, **then** nothing happens.
4. **Given** a run that is running, **when** it is selected, **then** Export is not available until it stops.

### US2 (P1): Delete a run

As an **evaluator**, I want to remove runs I no longer need, so that the list
stays useful.

Acceptance scenarios:
1. **Given** a selected run that is not running, **when** the user chooses **Delete**, **then** a confirmation names the run and says it can't be undone.
2. **Given** the user confirms, **when** the deletion finishes, **then** the file is removed from the app's storage, the run disappears from the list, and nothing is selected.
3. **Given** the user cancels, **when** the dialog closes, **then** nothing changes.
4. **Given** a run that is running, **when** it is selected, **then** Delete is not available.
5. **Given** a skipped (invalid) file in the list, **when** the user chooses to delete it, **then** it can be deleted the same way.

### US3 (P1): Import a run

As an **evaluator**, I want to bring a run file into the app, so that I can
browse (and continue) runs from earlier sessions or other machines.

Acceptance scenarios:
1. **Given** the Runs view, **when** the user chooses **Import**, **then** the system open dialog opens, filtered to `.jsonl` files.
2. **Given** a file that matches the run-file format and name pattern, **when** it is imported, **then** a copy is placed in the app's storage, it appears in the list and is selected, and the original file is untouched.
3. **Given** a file that doesn't match (wrong name pattern, invalid content, or a dataset file instead of a run), **when** it is imported, **then** it is rejected with the validation reason, naming the line where relevant, and nothing is written.
4. **Given** a run with the same file name already exists, **when** the file is imported, **then** the user is asked whether to replace it. Confirming replaces it, and cancelling leaves everything unchanged.
5. **Given** the existing run with that name is running, **when** the same name is imported, **then** the import is refused.
6. **Given** a file whose last line was cut off, **when** it is imported, **then** it is accepted like any other run file: the incomplete line is ignored, as when reading.

## Functional requirements

- **FR-001** The Runs view MUST offer **Import** at all times, and **Export** and **Delete** for the selected run.
- **FR-002** Export MUST use the system save dialog and write only to the chosen location. The copy MUST be identical to the stored file.
- **FR-003** Delete MUST ask for confirmation, and MUST NOT be possible while the run is running.
- **FR-004** Import MUST validate the whole file with the same rules as reading a run file (contracts/run-file.md RF-1 … RF-9) **before** writing anything.
- **FR-005** Import MUST copy the file into the app's storage and never modify or move the original.
- **FR-006** Import with a name that already exists MUST ask before replacing, and MUST refuse while that run is running.
- **FR-007** After any of the three actions, the runs list MUST reflect the change immediately.
- **FR-008** Every outcome (success, cancelled, rejected with reason, failure such as a full disk) MUST be shown to the user.

## Non-functional requirements

- **NFR-001** Importing or exporting a 5,000-conversation run must not freeze the interface.
- **NFR-002** Files the user picks are untrusted input (Constitution IV). Validation never crashes the app.
- **NFR-003** The app needs no new macOS permissions. It already has access to files the user selects.

## Key entities

- **Run file**: as defined in feature 002.
- **Import candidate**: a user-chosen file, either valid (with its run id) or rejected (with a reason).

## Edge cases

- Exporting onto an existing file at the destination: the system dialog asks to overwrite.
- Importing a file that is open in another program, or unreadable.
- Importing a run file into the app's own storage folder.
- Deleting the run that is shown in the progress panel from this session.
- The disk is full during an export or an import.

## Out of scope

- Importing the reference repo's `results/` format (Constitution V).
- Exporting or importing several runs at once.
- Exporting to other formats (CSV, a report).

## Clarifications

### 2026-10-17 (approved by the owner)
- **Q:** Can an imported run that was stopped part-way be continued? → **A:** Yes, with the same **Continue** action. It needs the same dataset file (checked by SHA-256), like any run.
- **Q:** Delete one at a time or several? → **A:** One at a time for now.
