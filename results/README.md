# results/

Run files committed for **auditing and sampling** (Constitution XII.2).

- **What goes here:** run files exported from the app (**Runs** → select a run → **Export**), unchanged. Their names look like `healthbench-run-YYYYMMDD-HHMMSS.jsonl`.
- **Self-contained:** each file holds the run settings and, for every graded conversation, the whole dataset record (conversation, every criterion with its points and tags, reference answer, tags), the model's reply and each grade with the grader's explanation. Reading or analysing a file never needs the dataset. Format: [specs/002-evaluation-core/contracts/run-file.md](../specs/002-evaluation-core/contracts/run-file.md).
- **Checked automatically:** `test/project/results_folder_test.dart` (run by `fvm flutter test` and CI) fails if any file here isn't a valid run file, or is too large for GitHub (keep each file under 95 MB; a full 5,000-conversation run can approach that).
- **Byte for byte:** `.gitattributes` stops git from converting line endings here, so the committed copy is exactly what the app exported.
- **No secrets:** run files never contain the API key (spec 002 FR-008).
- **To view one in the app:** **Runs** → **Import** → choose the file.

Model output in these files is unreviewed and is not medical advice.
