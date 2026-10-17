# simple-desktop-healthbench

A cross-platform desktop app (macOS, Windows, Linux), built with Flutter, for
running **[HealthBench](https://arxiv.org/abs/2505.08775)** evaluations of
language models and exploring the results.

> **Status: early planning.** There is no application code yet. The project
> uses spec-driven development (see [Development](#development)), so features
> appear here once their specs are written and approved.

**Install:** see [Installation (macOS)](#installation-macos): one script that asks before each change.

## What it does

HealthBench (OpenAI, 2025) is a benchmark of 5,000 realistic health
conversations. Each one has rubric criteria written by physicians. The app will:

1. Send each conversation to a **model under test** through any
   **OpenAI-compatible API**, such as OpenAI, Groq, Ollama, vLLM or LM Studio.
2. Ask a **grader model** whether the reply meets each criterion.
3. **Score** the reply with the official formula: the points earned (penalties
   subtract) divided by the maximum positive points. The run's score is the mean
   across conversations, clipped to 0–1.
4. **Save** each run as a file in the app's own storage (the sandbox on macOS).
   From inside the app, you can **delete** a run file, **export** it to any
   folder you choose, or **import** a run file you saved earlier. Import accepts
   only files that match the app's run-file format and naming pattern.
   The format is based on the
   [predecessor dashboard](https://github.com/carlos-dev-research/evals-healthbench-dashboard)'s
   format, with small changes, so it is not compatible with it.
5. **Show** the results: a list of runs, summary tiles, the score
   distribution, and for each conversation the dialogue, the model's reply and a
   breakdown of every graded criterion.

### Planned scope

This scope is still to be confirmed in specs.

- New-run screen: connection settings, models, reasoning effort, dataset, an
  optional conversation limit, live progress and cancel.
- Results browser with delete, export and import for each run file.
- Dataset management: list, download and sample subsets of `oss_eval`, `hard`
  and `consensus`.
- Improvements over the reference: per-theme and per-axis breakdowns, a
  bootstrap confidence interval, optional concurrent requests, and a native
  desktop app with no local web server.

Full domain notes: [docs/reference/healthbench.md](docs/reference/healthbench.md).

## Dataset

The dataset is **not** included, and `healthbench/` is git-ignored. Download the
files you need into `healthbench/`:

```sh
mkdir -p healthbench
BASE=https://openaipublic.blob.core.windows.net/simple-evals/healthbench
curl -L -o healthbench/2025-05-07-06-14-12_oss_eval.jsonl  $BASE/2025-05-07-06-14-12_oss_eval.jsonl   # 5,000 conversations
curl -L -o healthbench/hard_2025-05-08-21-00-10.jsonl      $BASE/hard_2025-05-08-21-00-10.jsonl       # 1,000 (hard)
curl -L -o healthbench/consensus_2025-05-09-20-00-46.jsonl $BASE/consensus_2025-05-09-20-00-46.jsonl  # consensus
```

The files are also available on Hugging Face as
[`openai/healthbench`](https://huggingface.co/datasets/openai/healthbench) (MIT).

## Installation (macOS)

One script, [`tool/setup.sh`](tool/setup.sh), prepares a Mac to build the app.
It **explains each step, asks before every change**, and finishes by checking
that nothing else on your Mac was changed.

**Time:** about 10–20 minutes, mostly the Flutter download.
**Disk:** about 3 GB. The script warns if you have less than 10 GB free.
**You need:** an administrator account (for `sudo`) and an internet connection.

### What gets installed

| Component | Version | Why | Where |
|---|---|---|---|
| **Xcode** (the full app) | 15 or later | Flutter builds the macOS app with `xcodebuild`, which only exists in full Xcode. The Command Line Tools alone are not enough | `/Applications/Xcode.app` (you install this yourself, step 1) |
| **Homebrew** | any | Installs FVM. If it's missing, the script offers to install it | `/opt/homebrew` |
| **[FVM](https://fvm.app)** + `dartaotruntime` | 4.x | Installs the **exact Flutter version pinned in `.fvmrc`**, so every Mac builds with the same SDK. It adds only the `fvm` and `dartaotruntime` commands | Homebrew |
| **Flutter SDK** (includes Dart) | pinned in [`.fvmrc`](.fvmrc) (currently 3.47.7) | The framework and build tools | `~/fvm/versions/<version>` |

**Not installed:**
- **CocoaPods.** It isn't needed: Flutter 3.44+ uses Swift Package Manager for macOS plugins. Homebrew's CocoaPods would also put its own `ruby` and `openssl` ahead of yours on your PATH.
- **Android Studio, Chrome tooling, iOS setup.** Only the macOS desktop target is needed.

### Step 1: Install Xcode

1. Install **Xcode** from the Mac App Store (it's large, so allow time for the download).
2. Open it once and let it finish installing components, then quit it.

### Step 2: Get the code

```sh
git clone https://github.com/carlos-dev-research/simple-desktop-healthbench.git
cd simple-desktop-healthbench
```

### Step 3 (optional): Preview what's missing

```sh
./tool/setup.sh --check
```

This changes nothing. Each item is shown as ✔ (ready) or ✘ (missing).

### Step 4: Run the setup

Run it in your own terminal (VS Code's built-in terminal works). Don't use
`sudo`; the script asks for your password only where it needs it.

```sh
./tool/setup.sh
```

First it prints a **plan** of everything it might change and asks
**"Continue?"**. Then it asks about each change separately. Pressing **Enter**
means *no*, which skips that change.

| # | Step | What it asks | What happens if you say yes |
|---|---|---|---|
| 1 | macOS and disk | — | Only checks |
| 2 | Xcode | *Switch the active developer directory to Xcode? (needs sudo)* | Runs `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Type your **Mac login password**; nothing shows while you type. If the Xcode license or first-launch components are missing, it asks about those as well |
| 3 | Homebrew | *Run the official Homebrew installer?* (only if Homebrew is missing) | Runs the installer from https://brew.sh |
| 4 | Brewfile | Shows a **preview** first, then asks *Install fvm?* | `brew install fvm`, with nothing else upgraded, cleaned up or removed |
| 5 | Flutter | *Pin this repo to Flutter X?*, *Download Flutter X with FVM?*, *Create the .fvm/ link?* | Writes `.fvmrc`, downloads the SDK (the slow step), and links it into `.fvm/` for VS Code |
| 6 | Optional settings | *Turn off Flutter/Dart usage analytics?*, *Pre-download the macOS build artifacts?* | Both are your choice. Pre-downloading makes the first build faster |
| 7 | Project packages | *Run 'flutter pub get'?* (once the app code exists) | Downloads the Dart packages listed in `pubspec.lock` |
| 8 | `flutter doctor` | — | Prints a toolchain report (see below) |
| 9 | **Final verification** | — | **Read-only** checks (see below) |

The script is safe to run again: anything already done is skipped.

### Step 5: Check the result

**Step 9 (Final verification)** should end with
`✔ Final verification: all N checks passed`. It checks that:
- Xcode is selected, its license is accepted, and `xcrun` finds `xcodebuild`.
- `fvm flutter` runs exactly the version in `.fvmrc`, and macOS is available as a build target.
- No CocoaPods `Podfile` exists, and no secret-looking files are about to be committed.
- **No Homebrew package was upgraded, downgraded or removed**, compared with a snapshot taken before step 1.
- **`ruby`, `python3`, `openssl`, `node`, `git`, `clang` and similar commands still resolve to the same place** on your PATH.

These **`flutter doctor` warnings are expected** and can be ignored:

| Warning | Why it's fine |
|---|---|
| `[!] Android toolchain …` | We don't build for Android |
| `! CocoaPods not installed` | On purpose: Swift Package Manager is used instead |
| Errors about wireless iPhone/iPad devices | Xcode looking for nearby iOS devices; not related to this app |
| `Chrome`, `iOS` notes | Not used |

The line that matters is `• macOS (desktop) • macos • darwin-arm64` (or `darwin-x64` on Intel Macs).

### Step 6: Restart VS Code

Restart VS Code (and install the **Dart** and **Flutter** extensions if you
haven't). The repo's [`.vscode/settings.json`](.vscode/settings.json) points
the extensions at `.fvm/flutter_sdk`, so they use the pinned SDK.

### Using Flutter day to day

Always run Flutter through FVM inside this repo, so the pinned version is used:

```sh
fvm flutter --version        # should print the version in .fvmrc
fvm flutter run -d macos     # once the app code exists
fvm flutter test
```

If you'd like to type plain `flutter`, the script deliberately leaves that to
you. Run `fvm global <version>`, then add
`export PATH="$HOME/fvm/default/bin:$PATH"` to your `~/.zshrc` yourself.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `Xcode not found` | Install Xcode (step 1). If it's not in `/Applications`, run `XCODE_PATH=/path/to/Xcode.app ./tool/setup.sh` |
| Password prompt shows nothing | Normal for `sudo`; type it and press Enter |
| `Could not determine a Flutter version` | You're offline and there's no `.fvmrc`. Reconnect, or run `FLUTTER_VERSION=3.47.7 ./tool/setup.sh` |
| `brew install` fails with "formula not found" | Your Homebrew list of available packages is stale (the script doesn't refresh it). Run `brew update` yourself, then rerun the script |
| Step 9 reports a changed package or command | Nothing else should have changed. The output shows what changed (before → after). Undo it with the table below, and please open an issue |
| VS Code can't find the Flutter SDK | Check that `.fvm/flutter_sdk` exists (rerun the script), then restart VS Code |
| Anything else | Rerun `./tool/setup.sh --check` and read the ✘ lines; each one tells you the command that fixes it |

### What the setup changes and how to undo it

The script's summary also prints these undo commands, for the changes made in that run.

| Change | Where | Undo |
|---|---|---|
| Active developer directory switched to Xcode | System-wide (`xcode-select`) | `sudo xcode-select -s <previous path>` (the script prints it; usually `/Library/Developer/CommandLineTools`) |
| `fvm` + `dartaotruntime` installed | Homebrew | `brew uninstall fvm && brew autoremove` |
| Flutter SDK and its git cache | `~/fvm` | `fvm remove <version>`, or delete `~/fvm` |
| Flutter/Dart settings and package cache | `~/.config/flutter`, `~/.dart-tool`, `~/.pub-cache` (and `~/.flutter` on some versions) | Delete those folders |
| Pinned version and SDK link | `.fvmrc` (committed), `.fvm/` (git-ignored) | `rm -rf .fvm` |
| App data (runs), once the app exists | `~/Library/Containers/<bundle-id>/` | Delete that folder. Removing the app alone does not delete it |

Never changed: `~/.zshrc` and other shell profiles, versions of tools you
already have, and anything outside the locations above.

### Windows and Linux

The app targets these too, but the setup script is macOS-only for now. You'll need:
- **Windows:** Flutter (via FVM) and Visual Studio with *Desktop development with C++*.
- **Linux:** Flutter (via FVM) and `clang cmake ninja-build pkg-config libgtk-3-dev`.

Details: [docs/reference/flutter-desktop.md](docs/reference/flutter-desktop.md).

### Running evaluations

You'll need an **OpenAI-compatible endpoint and API key** (OpenAI, Groq, a
local Ollama or vLLM server, …), plus the HealthBench dataset (see
[Dataset](#dataset)). Browsing results needs neither.

## Development

This repo follows **spec-driven development**. Every feature moves through
`spec.md` (what and why), `plan.md` (how), `tasks.md` (steps) and finally the
implementation, and each step is reviewed before the next one starts. Specs are
in [`specs/`](specs/), and the workflow is described in [CLAUDE.md](CLAUDE.md).

## Caveats

- Model output is **unreviewed and is not medical advice**.
- Scores from random subsets, or from a grader other than OpenAI's, are **not
  comparable** to published HealthBench numbers. Grading a model with itself is
  less reliable than using an independent, stronger grader.
- API keys are used only to call the endpoint you configure. They are never
  written to run files.

## License

Apache-2.0. See [LICENSE](LICENSE). The HealthBench dataset is published by
OpenAI under the MIT license.
