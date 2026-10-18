# Feature: Dataset management

**Status:** Draft · **Date:** 2026-10-18 · **Constitution:** v1.2.0

## Summary

The app manages HealthBench datasets itself, instead of relying on the
command line and the file dialog:
- It **downloads** the official files.
- It keeps them in a **dataset library** in its own storage.
- It creates **random subsets** (for example 100 conversations) that are reproducible from a seed.

New runs and Continue pick datasets from the library. Continue finds the
right dataset **automatically**, by its fingerprint, so you no longer
choose the file again. Choosing an external file with the dialog still works.

Reference: the toolkit downloaded files with `curl` and sampled subsets in
`eval.ipynb` (`df.sample(n=100, random_state=40)`). Dataset facts: [healthbench.md §1](../../docs/reference/healthbench.md).

## User stories

### US1 (P1): Download the official datasets

As an **evaluator**, I want to download HealthBench from inside the app, so
that I don't need the command line.

Acceptance scenarios:
1. **Given** the dataset library, **when** it opens, **then** it lists the three official files (oss_eval, hard, consensus), each with its size and whether it's downloaded.
2. **Given** a file isn't downloaded, **when** the user downloads it, **then** progress is shown. When it finishes, the file is read and checked (it must parse, with the expected number of conversations), and it appears as available with its conversation count.
3. **Given** a download fails or is cancelled, **when** it stops, **then** no partial file is left in the library, and the user can retry.
4. **Given** a downloaded file, **when** the app restarts, **then** it is still in the library, and nothing is downloaded again.

### US2 (P1): Use the library in runs

As an **evaluator**, I want to pick a dataset from the library when starting
or continuing a run, so that I don't hunt for files.

Acceptance scenarios:
1. **Given** library datasets, **when** the New-run form opens, **then** the dataset can be chosen from a list of library datasets (name, conversation count). An external file can still be chosen with the dialog.
2. **Given** a run made with a library dataset, **when** the user continues it, **then** the matching dataset (same SHA-256) is selected automatically. If none matches, the user is told which file is needed.

### US3 (P1): Create a reproducible subset

As an **evaluator**, I want to make a random subset of a dataset, so that I
can evaluate cheaply and repeat the same sample later.

Acceptance scenarios:
1. **Given** a library dataset, **when** the user creates a subset with a size N and a seed, **then** a new library dataset with N conversations is created. Its name shows its origin, N and the seed.
2. **Given** the same dataset, N and seed, **when** a subset is created again, **then** it contains exactly the same conversations in the same order (byte-identical file).
3. **Given** N is 0, larger than the dataset, or not a number, **when** the user tries, **then** it is refused with the reason.
4. `[NEEDS CLARIFICATION: must the app reproduce the reference toolkit's pandas subsets exactly (same N and random_state=40 → the same conversations as its old N100/N200 files), or is the app's own seeded sampler enough?]`

### US4 (P2): Manage the library

As an **evaluator**, I want to see and remove datasets, so that storage
doesn't fill up.

Acceptance scenarios:
1. **Given** the library, **when** it opens, **then** each dataset shows its name, its conversation count, its size, its origin (official, subset of X, or added file) and its SHA-256.
2. **Given** a dataset, **when** the user deletes it and confirms, **then** it is removed. Runs that used it are unaffected, because they're self-contained, but continuing them will need the dataset again.
3. `[NEEDS CLARIFICATION: should the user also be able to add their own dataset file into the library (copied in), or only download official files and make subsets?]`

## Functional requirements

- **FR-001** The app MUST download the three official files from `https://openaipublic.blob.core.windows.net/simple-evals/healthbench/`, and from nowhere else (Constitution III.2).
- **FR-002** Downloads MUST show progress, be cancellable, never leave a partial file, and be validated with the dataset reader before they're accepted.
- **FR-003** Library datasets MUST be stored in the app's own storage, and survive restarts.
- **FR-004** The New-run form MUST offer library datasets. The file dialog MUST remain available.
- **FR-005** Continue MUST auto-select the library dataset whose SHA-256 matches the run's dataset, when one exists.
- **FR-006** Subsets MUST be deterministic for (source dataset, N, seed), and MUST keep the source's records unchanged, as whole lines.
- **FR-007** A subset's name MUST record its source, N and seed.
- **FR-008** Deleting a dataset MUST ask for confirmation, and MUST NOT be possible while a run uses it.

## Non-functional requirements

- **NFR-001** Downloading 60 MB and creating subsets must not freeze the interface.
- **NFR-002** No network access except an explicit download.
- **NFR-003** Works the same on macOS, Windows and Linux.

## Key entities

- **Library dataset:** a HealthBench file in the app's storage, with its name, conversation count, size, SHA-256 and origin.
- **Official dataset:** one of the three known files, downloaded or not.
- **Subset:** a library dataset made from another one with N and a seed.

## Edge cases

- The download host is unreachable, or returns an error page instead of the file.
- The disk fills up during a download.
- A subset of a subset.
- Two subsets with the same name: the same source, N and seed give the same file, so it isn't created twice.
- Deleting a dataset while a run uses it.

## Out of scope

- The meta-eval file (it has a different schema; healthbench.md §1).
- Editing datasets.
- Datasets other than HealthBench.

## Clarifications

*(open questions above)*
