# Quickstart: 004 with the real dialogs

Rebuild and open the app:

```sh
fvm flutter build macos --release
open "build/macos/Build/Products/Release/HealthBench Evals.app"
```

| # | What to do | Expected |
|---|---|---|
| E1 | **Runs** → select a finished run → **Export** (save icon) → save to Desktop | The save dialog suggests `healthbench-run-….jsonl`. A message confirms the path, and the file appears on the Desktop |
| E2 | Select the same run → **Delete** (bin icon) → **Cancel**, then **Delete** → **Delete** | Cancel keeps it. Delete asks "can't be undone", then the run disappears and "Deleted …" is shown |
| E3 | **Import** → choose the Desktop copy from E1 | It comes back in the list, selected, with the same results. The Desktop file is still there |
| E4 | **Import** the same file again | "Replace existing run?" appears. Replace keeps one copy |
| E5 | **Import** a dataset file from `healthbench/` | "Can't import this file", with the reason (it isn't a run file) |
| E6 | Start a run with a few conversations and select it while it runs | No Export or Delete icons until it stops |
| E7 | Export a stopped run, delete it, import it back, then **Continue** it with the same dataset | It continues from where it stopped |
| E8 | **New run**: fill in everything (key, dataset…), go to **Runs** and back | Every field is still filled in. After quitting and reopening the app, they're all empty |
| E9 | Look at the left rail | **Evals** at the top. A very small **v0.1.0** at the bottom |

## Already verified automatically (2026-10-18)

| Check | Covered by |
|---|---|
| E1 export identical copy, E2 delete with confirmation, E3 import back, E7 continue an imported run | integration `run_files_flow` (in the real app; the dialogs are replaced by fixed paths) |
| E4 replace prompt | widget test `run_actions_test` |
| E5 invalid file explained | widget test `run_actions_test`, core `run_library_ops_test` |
| E6 no export/delete while running | widget test `run_actions_test`, core `run_library_ops_test` |
| E8 form kept / empty after restart | integration `run_files_flow`, widget `new_run_view_test` |
| E9 rail | widget test `shell_test` |

**Still needs you:** the **real system dialogs**: the save dialog in E1 and the open dialog in E3 and E5. Tests can't drive them.

