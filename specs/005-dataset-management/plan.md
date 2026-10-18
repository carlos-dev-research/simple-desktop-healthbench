# Plan: 005 dataset management

**Status:** Approved · **Date:** 2026-10-18 · **Spec:** [spec.md](spec.md) (Approved) · **Constitution:** v1.2.0

## Technical context

| Item | Choice |
|---|---|
| Storage | `<app support>/datasets/*.jsonl`, plus `<app support>/datasets/library.json`, an index cache (name, origin, count, size, SHA-256, modified time). It's rebuilt for any file that changed |
| Download | `package:http` (already used), streamed to `<name>.part`, then renamed. Cancel aborts the request (`AbortableRequest`) |
| Integrity | Each official file is **pinned** in the code by size, SHA-256 and conversation count. These values were taken from copies whose MD5 matches the host's `Content-MD5`. A download is accepted only if all three match and the dataset reader accepts it |
| Sampling | Feature 006's `SplitMix64` with a partial Fisher–Yates shuffle chooses N indices. The chosen records are written **in their original order, as the original lines byte for byte** |
| New dependencies | None |
| Network | Only the 3 pinned URLs on `openaipublic.blob.core.windows.net`, and only when the user presses Download (NFR-002, Constitution III.2) |

## Pinned official files

| File | Bytes | SHA-256 | Conversations |
|---|---|---|---|
| `2025-05-07-06-14-12_oss_eval.jsonl` | 60,258,154 | `e99dd3c6…ecd2f` | 5,000 |
| `hard_2025-05-08-21-00-10.jsonl` | 12,581,564 | `b0320430…d74e9` | 1,000 |
| `consensus_2025-05-09-20-00-46.jsonl` | 36,921,504 | `fabe3755…969d6` | 3,671 |

## Design decisions

1. **Core: `lib/core/dataset_library.dart`** (pure Dart):
   - `officialDatasets` (the pinned list);
   - `listLibrary(dir)`, which uses the index;
   - `downloadOfficial(...)`, which streams progress, can be cancelled, verifies the file, and never leaves a partial file;
   - `addDatasetFile(src, dir)`, which validates, then copies; the same file already present is reported, and a different file with the same name gets a `-2` suffix;
   - `createSample(source, n, seed, dir)`, named `<source base>_N<n>_seed<seed>.jsonl`; it's deterministic, and an identical existing sample is reused;
   - `deleteDataset(path)`.
2. **The sample keeps the original order and lines.** Diffs stay readable, and records are untouched, so the HealthBench contents are preserved exactly (FR-006).
3. **Default seed: 40**, the same value your toolkit used. The file name always records the seed.
4. **Datasets view:** a third rail destination with two sections.
   - **Official:** one row per file, with a description, size and state (Download / progress + Cancel / Downloaded ✓, 5,000 conversations).
   - **Library:** every dataset with its origin, count, size and a short SHA-256, plus **Sample…** and **Delete** actions. An **Add file…** button sits on top.
5. **New run:** the dataset field becomes a dropdown of library datasets, plus "Choose file…" (the existing dialog). **Continue** auto-selects the library dataset whose SHA-256 matches the run (FR-005).
6. **Delete protection:** `RunController` exposes the dataset path of the active run. Deleting that dataset is refused.
7. **Seams for tests:** `datasetHostProvider` (the base URL; tests point it at the local fake server, which serves pinned-size fixtures) and `addFilePickerProvider`.

## Tests (written first)

- **Core:**
  - download (success; a size, SHA-256 or count mismatch is rejected with no file kept; cancel leaves no `.part`; HTTP error);
  - sampling (deterministic, byte-identical lines, original order, N out of range refused, a sample of a sample);
  - add (valid, invalid with line number, same file, name clash);
  - index rebuilt after a change; delete.
- **Widgets:**
  - the Datasets view states (not downloaded / downloading / downloaded), the sample dialog validation, the delete confirmation;
  - New run's dropdown, and Continue's auto-selection.
- **Integration:** download from the local fake host inside the sandboxed app, then sample, then start a run on the sample.
- The pinned values are checked once against the real host in the quickstart (a real download).

## Constitution check

| Article | Result | Notes |
|---|---|---|
| III Privacy / local-first | ✅ | Network only for an explicit download from the pinned official host |
| IV Untrusted content | ✅ | Downloads and added files are validated (pinned hashes; the dataset reader). Size limits as in 002 |
| VI Architecture | ✅ | Library logic in the core; the UI calls it |
| VII Testing | ✅ | No real downloads in tests (local fake host) |
| VIII Cross-platform | ✅ | `dart:io`/`http` only |
| IX Dependencies | ✅ | None new |

**Complexity Tracking:** none.
