# Quickstart: 005 dataset management

Manual checks on the release app (`dist/HealthBench-Evals-macOS-v0.2.0.zip`),
for what the tests can't reach: the real download host and the real file
dialog. Everything else is covered automatically (see the end of this file).

| # | Steps | Expected |
|---|---|---|
| D1 | **Datasets** → **Download** next to *HealthBench (main)* | Progress bar with a percentage and **Cancel**. When done: "Downloaded · 5000 conversations", and the file appears under **Library** as *Official* |
| D2 | Download *HealthBench Hard* and *HealthBench Consensus* | "Downloaded · 1000 conversations" and "Downloaded · 3671 conversations" |
| D3 | Start a download, press **Cancel** | "Download cancelled"; no partial file in the library |
| D4 | **Sample…** on the main file, size 100, seed 40 → **Create** | `2025-05-07-06-14-12_oss_eval_N100_seed40.jsonl`, *Sample of …*, 100 conversations. Repeating with the same size and seed reports the same file |
| D5 | **Add file…** → an old N100 file of your own | *Added file*, with its conversation count. A non-HealthBench file is refused with a reason |
| D6 | **New run** → **Dataset from the library** → the sample → run 2 conversations against a real endpoint | The run completes. Its detail shows the score ± bootstrap, the median and the std dev |
| D7 | Stop a run, then **Continue** | The run's dataset is already selected; only the missing conversations are graded |
| D8 | **Delete** a library dataset not in use | Asks first, then removes it. Runs made with it still open |

## Already verified automatically

- Download verification (size, SHA-256, conversation count), cancel, HTTP errors, no partial files: `test/core/dataset_library_test.dart`.
- Samples (deterministic, original lines in original order, size limits), add, index, delete: same file.
- Datasets view, New-run dropdown, Continue auto-selection: `test/ui/datasets_view_test.dart`.
- Download → sample → run on the sample in the real sandboxed app, on macOS, Windows and Linux: `integration_test/datasets_flow.dart` (CI).
