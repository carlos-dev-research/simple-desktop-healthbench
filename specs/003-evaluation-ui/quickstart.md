# Quickstart: the owner's first UI test

This is the end of the delegation (002 plan). It also covers the pending manual checks from 001 (Q1, Q3, Q4) and 002 (Q2–Q4).

**You need:**
- the HealthBench files in `healthbench/` (already downloaded);
- an OpenAI-compatible endpoint and key, for example Groq: `https://api.groq.com/openai/v1` with `openai/gpt-oss-20b`.

## Launch

```sh
cd ~/Documents/Projects/simple-desktop-healthbench
fvm flutter build macos --release
open "build/macos/Build/Products/Release/HealthBench Evals.app"
```

(`fvm flutter run -d macos` works too, as a debug build with hot reload.)

## Checks

| # | What to do | Expected | Covers |
|---|---|---|---|
| U1 | Look at the window | Title and menu bar say **HealthBench Evals**. The rail shows the name and **Version 0.1.0**. The notes footer is at the bottom | 001 Q1, 003 FR-016 |
| U2 | Drag a window corner as small as it goes | It stops at about 960 × 640, with no yellow and black stripes anywhere | 001 Q3 |
| U3 | System Settings → Appearance, Light ↔ Dark | The app follows immediately | 001 Q4 |
| U4 | **New run**: press **Start run** with nothing filled in | Each field says what's missing, and nothing starts | 003 US1-2 |
| U5 | Fill in the base URL, your key, the model and grader (`openai/gpt-oss-20b`, effort low). **Choose dataset file…** → `healthbench/2025-05-07-06-14-12_oss_eval.jsonl`. Max conversations **3**. Start | The file name and "5000 conversations" show after choosing. The progress panel shows the bars, "graded n of m criteria", the elapsed time and the score so far | 003 US1, US2; **release-build outgoing network (001 US3-3)**; 002 Q2 |
| U6 | When it finishes: **Open results** | The new run appears at the top of **Runs** with its score. The tiles, the histogram and 3 conversations are shown | 003 US3 |
| U7 | Open a conversation | The messages, the reply rendered as Markdown (tables, lists) and the rubric table with earned / missed / penalty / avoided are shown | 003 US3-4, US5 |
| U8 | Search for a word in a reply; sort by lowest score | The list filters and re-orders | 003 US3-3 |
| U9 | Start a new run with max **10**, then press **Stop** after 2 conversations | It says "Stopping after this conversation…", then *stopped* | 003 US2-2, 002 Q3 |
| U10 | **Runs** → that run → **Continue (n left)** → enter the key and choose the same dataset | It resumes and grades only the missing ones, ending *completed* 10/10 | 003 US4, 002 Q3 |
| U11 | Continue a stopped run but choose the **hard** dataset | Refused: "The dataset file differs…" | 003 US4-3 |
| U12 | Start a run with a wrong key | It stops at once as *failed* (authentication), and nothing is saved | 002 Q4 |
| U13 | Quit the app, reopen it, open **New run** | The base URL and models are remembered. **The key field is empty** | 003 US1-4 |
| U14 | Optional: in Terminal, `grep -r "<your key>" ~/Library/Containers/io.github.carlos-dev-research.healthbench/` | No matches | 002 Q5 |

Tell Claude what passed and what didn't. Screenshots of anything odd help.

## Where the data is

`~/Library/Containers/io.github.carlos-dev-research.healthbench/Data/Library/Application Support/io.github.carlos-dev-research.healthbench/runs/`

Deleting, exporting and importing runs from inside the app comes in feature 004.
