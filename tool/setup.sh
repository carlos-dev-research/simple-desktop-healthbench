#!/usr/bin/env bash
#
# tool/setup.sh: prepare a Mac to build and run simple-desktop-healthbench.
#
# Each step explains WHAT it checks and WHY, and asks before changing
# anything. Running it again is safe: steps that are already done are skipped.
#
# Usage:
#   ./tool/setup.sh           interactive: asks before each change
#   ./tool/setup.sh --check   only report what is missing; installs nothing. (The Flutter
#                             tool itself may refresh the git-ignored .dart_tool/ folder.)
#   ./tool/setup.sh --yes     answer "yes" to every question (CI / unattended).
#                             sudo may still ask for your password.
#
# Environment overrides:
#   FLUTTER_VERSION=3.47.7    use this Flutter version instead of .fvmrc / latest stable
#   XCODE_PATH=/Applications/Xcode-beta.app   use a specific Xcode install
#
# What it may change on your Mac is listed in the plan it prints before
# starting, and in README → "What the setup changes and how to undo it".
# It never edits your shell profile and never upgrades or removes tools you
# already have. The last step re-checks everything read-only and compares
# Homebrew and your PATH against a snapshot taken before anything ran.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="$ROOT/Brewfile"
FVMRC="$ROOT/.fvmrc"
MIN_XCODE_MAJOR=15          # Flutter's documented minimum for macOS desktop
MIN_FREE_GB=10              # Flutter SDK + git cache + build artifacts take about 5 GB
FLUTTER_RELEASES_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json"

# Homebrew guard rails: install exactly what the preview shows and nothing else.
#   NO_AUTO_UPDATE              don't refresh Homebrew first (the install matches the preview)
#   NO_INSTALL_CLEANUP          don't run 'brew cleanup' (it would delete old versions of ALL formulae)
#   NO_INSTALLED_DEPENDENTS_CHECK  don't upgrade or reinstall other installed formulae
#   NO_INSTALL_UPGRADE          don't upgrade a listed formula that is already installed
BREW_GUARDS="HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_ENV_HINTS=1"

# Commands whose PATH resolution must not change (the final step compares them).
WATCHED_COMMANDS="ruby gem bundle python3 pip3 node npm openssl git clang make cmake swift java dart flutter pod"

ASSUME_YES=0
CHECK_ONLY=0
PROBLEMS=0
VERIFY_PASSED=0
VERIFY_FAILED=0
CHANGES=""                  # what this run changed, one "description|undo command" per line

usage() { sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
  case "$arg" in
    -y|--yes)   ASSUME_YES=1 ;;
    -c|--check) CHECK_ONLY=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- output helpers

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

step()    { printf '\n%s==> Step %s: %s%s\n' "$BOLD" "$1" "$2" "$RESET"; }
why()     { for line in "$@"; do printf '    %s%s%s\n' "$DIM" "$line" "$RESET"; done; }
ok()      { printf '    %s✔ %s%s\n' "$GREEN" "$*" "$RESET"; }
warn()    { printf '    %s! %s%s\n' "$YELLOW" "$*" "$RESET"; }
problem() { printf '    %s✘ %s%s\n' "$RED" "$*" "$RESET"; PROBLEMS=$((PROBLEMS + 1)); }
die()     { printf '\n%s✘ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

# Show a command, then run it.
run() { printf '    %s$ %s%s\n' "$BOLD" "$*" "$RESET"; "$@"; }

# Remember a change for the summary: changed "what was done" "how to undo it".
changed() { CHANGES="${CHANGES}$1|$2"$'\n'; }

# Ask a yes/no question. Always "no" in --check mode, always "yes" with --yes.
confirm() {
  if [ "$CHECK_ONLY" = 1 ]; then return 1; fi
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi
  local reply=""
  printf '    %s? %s [y/N] %s' "$BOLD" "$1" "$RESET"
  read -r reply </dev/tty || return 1
  case "$reply" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# Run Homebrew with the guard rails above.
brew_guarded() { env $BREW_GUARDS brew "$@"; }

# Run Flutter / Dart through FVM from the repo root, so the version in .fvmrc is used.
flutter_fvm() { (cd "$ROOT" && fvm flutter "$@"); }
dart_fvm()    { (cd "$ROOT" && fvm dart "$@"); }

# Formula names listed as  brew "name"  in the Brewfile.
brewfile_formulae() { sed -n 's/^[[:space:]]*brew[[:space:]]*"\([^"]*\)".*/\1/p' "$BREWFILE"; }

# Flutter version pinned in .fvmrc (empty if none).
pinned_version() {
  if [ -f "$FVMRC" ]; then
    sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FVMRC" | head -1
  fi
}

# .fvmrc with FVM's automatic edits of other files turned off: the repo
# already ignores .fvm/ and ships its own .vscode/settings.json.
write_fvmrc() {
  cat > "$FVMRC" <<EOF
{
  "flutter": "$1",
  "updateGitIgnore": false,
  "updateVscodeSettings": false,
  "updateMelosSettings": false,
  "runPubGetOnSdkChanges": false
}
EOF
}

# Print the version of the current Flutter stable release, read from Google's
# official release index. Uses only curl and osascript (JavaScript for
# Automation), which every Mac has.
latest_stable_flutter() {
  local json
  json="$(mktemp)"
  if ! curl -fsSL "$FLUTTER_RELEASES_URL" -o "$json"; then rm -f "$json"; return 1; fi
  osascript -l JavaScript -e '
    function run(argv) {
      var text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
      var data = JSON.parse(text);
      var hash = data.current_release.stable;
      for (var i = 0; i < data.releases.length; i++) {
        if (data.releases[i].hash === hash) return data.releases[i].version;
      }
      return "";
    }' "$json"
  rm -f "$json"
}

# Final-verification results.
pass() { ok "$*"; VERIFY_PASSED=$((VERIFY_PASSED + 1)); }
fail() { printf '    %s✘ %s%s\n' "$RED" "$*" "$RESET"; VERIFY_FAILED=$((VERIFY_FAILED + 1)); }

# Snapshot of installed Homebrew formulae/casks with versions, one per line, sorted.
brew_snapshot() {
  if have brew; then
    { brew list --formula --versions 2>/dev/null | sed 's/^/formula /'
      brew list --cask --versions 2>/dev/null | sed 's/^/cask /'; } | LC_ALL=C sort
  fi
}

# Where each watched command resolves, using the PATH the script started with
# (the same PATH as your terminal), so the script's own PATH tweaks don't count.
path_snapshot() {
  local cmd
  for cmd in $WATCHED_COMMANDS; do
    printf '%s %s\n' "$cmd" "$(PATH="$ORIG_PATH" command -v "$cmd" 2>/dev/null || echo '-')"
  done
}

# True if FVM's cache already has this Flutter version. The output is captured
# first: piping straight into 'grep -q' can fail under pipefail.
fvm_has_version() {
  local list
  list="$(fvm list 2>/dev/null || true)"
  case "$list" in *"$1"*) return 0 ;; *) return 1 ;; esac
}

# ============================================================ 0. preflight
printf '%ssimple-desktop-healthbench: macOS development setup%s\n' "$BOLD" "$RESET"

if [ "$(id -u)" = 0 ]; then
  die "Don't run this script with sudo or as root: files in your home folder would end up owned by root. Run it as yourself; it asks for sudo only where needed."
fi
if [ "$(uname -s)" != "Darwin" ]; then
  die "This script is for macOS. Windows and Linux setup is described in docs/reference/flutter-desktop.md."
fi

if [ "$CHECK_ONLY" = 1 ]; then
  printf '%s(check mode: nothing will be installed or changed)%s\n' "$DIM" "$RESET"
else
  cat <<EOF

This script can make the changes below. Each one is asked separately; nothing else is touched.

  System-wide (needs sudo)
    - Select Xcode as the active developer directory (xcode-select)
    - Accept the Xcode license / install Xcode's first-launch components (only if not done yet)
  Homebrew (only what's missing; no upgrades, no cleanup, nothing removed)
    - Install Homebrew itself, if it isn't installed
    - Install: $(brewfile_formulae | tr '\n' ' ')(plus their dependencies, shown before installing)
  Your home folder
    - FVM cache with the Flutter SDK (~/fvm by default, about 3-5 GB)
    - Flutter/Dart tool settings (~/.flutter, ~/.dart-tool, ~/.config/flutter), package cache (~/.pub-cache)
  This repository
    - .fvmrc (pinned Flutter version, committed) and .fvm/ (link to the SDK, git-ignored)

  Never: edits to ~/.zshrc or other shell profiles, upgrades or removal of installed tools, CocoaPods.
EOF
  if ! confirm "Continue?"; then echo "Nothing changed."; exit 0; fi
fi

# Snapshot before any change, so the final step can prove nothing else moved.
ORIG_PATH="$PATH"
SNAP_DIR="$(mktemp -d)"
trap 'rm -rf "$SNAP_DIR"' EXIT
brew_snapshot > "$SNAP_DIR/brew.before"
path_snapshot > "$SNAP_DIR/path.before"

# ============================================================ 1. macOS
step 1 "macOS and disk space"
why "Flutter desktop apps for macOS can only be built on a Mac."
ok "macOS $(sw_vers -productVersion) on $(uname -m)"
free_gb="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
if [ -n "$free_gb" ] && [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
  warn "Only ${free_gb} GB free in your home volume; Flutter needs about 5 GB. Free some space first."
else
  ok "${free_gb} GB free"
fi

# ============================================================ 2. Xcode
step 2 "Xcode (the full app, not only the Command Line Tools)"
why "Flutter builds the macOS app with 'xcodebuild', which only exists in the full Xcode app." \
    "The smaller 'Command Line Tools' package is not enough."

XCODE_APP="${XCODE_PATH:-}"
if [ -z "$XCODE_APP" ]; then
  current_dev="$(xcode-select -p 2>/dev/null || true)"
  case "$current_dev" in
    *.app/Contents/Developer) XCODE_APP="${current_dev%/Contents/Developer}" ;;
  esac
fi
if [ -z "$XCODE_APP" ] && [ -d /Applications/Xcode.app ]; then
  XCODE_APP=/Applications/Xcode.app
fi
if [ -z "$XCODE_APP" ] || [ ! -d "$XCODE_APP" ]; then
  die "Xcode not found. Install it from the Mac App Store (or developer.apple.com/xcode), open it once, then run this script again. If it is somewhere else, set XCODE_PATH=/path/to/Xcode.app."
fi
XCODE_DEV="$XCODE_APP/Contents/Developer"
XCODEBUILD="$XCODE_DEV/usr/bin/xcodebuild"
XCODE_VERSION="$(plutil -extract CFBundleShortVersionString raw "$XCODE_APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
ok "Found Xcode $XCODE_VERSION at $XCODE_APP"
case "$XCODE_VERSION" in
  [0-9]*)
    if [ "${XCODE_VERSION%%.*}" -lt "$MIN_XCODE_MAJOR" ]; then
      warn "Xcode $XCODE_VERSION is older than $MIN_XCODE_MAJOR; update it from the App Store if builds fail."
    fi ;;
esac

# 2a. Make it the active developer directory.
previous_dev="$(xcode-select -p 2>/dev/null || echo none)"
if [ "$previous_dev" = "$XCODE_DEV" ]; then
  ok "Xcode is the active developer directory"
else
  why "" "The active developer directory is: $previous_dev" \
      "Switching it to Xcode changes where the /usr/bin developer tools (git, clang, make, swift," \
      "xcrun) come from. Tools installed by Homebrew, conda, etc. are not affected." \
      "If you have existing CMake/C++ build folders configured against the Command Line Tools," \
      "they may need to be re-configured. Undo at any time: sudo xcode-select -s \"$previous_dev\""
  if confirm "Switch the active developer directory to $XCODE_DEV? (needs sudo)"; then
    run sudo xcode-select -s "$XCODE_DEV"
    changed "Active developer directory: $previous_dev -> $XCODE_DEV" "sudo xcode-select -s \"$previous_dev\""
    ok "Switched"
  else
    problem "Xcode is not the active developer directory: run  sudo xcode-select -s \"$XCODE_DEV\""
  fi
fi

# 2b. Accept the license. Xcode tools refuse to run until it is accepted.
if DEVELOPER_DIR="$XCODE_DEV" "$XCODEBUILD" -license check >/dev/null 2>&1; then
  ok "Xcode license accepted"
else
  why "" "Apple requires the Xcode license to be accepted before its build tools will run." \
      "To read it first, run  sudo xcodebuild -license  yourself instead."
  if confirm "Accept the Xcode license now? (needs sudo)"; then
    run sudo env DEVELOPER_DIR="$XCODE_DEV" "$XCODEBUILD" -license accept
    changed "Accepted the Xcode license" "(cannot be undone; it has no effect outside Xcode)"
    ok "License accepted"
  else
    problem "Xcode license not accepted: run  sudo xcodebuild -license"
  fi
fi

# 2c. First-launch components: system packages Xcode installs on its first run.
if DEVELOPER_DIR="$XCODE_DEV" "$XCODEBUILD" -checkFirstLaunchStatus >/dev/null 2>&1; then
  ok "Xcode first-launch components installed"
else
  why "" "Xcode installs extra system components the first time it runs (the same as opening" \
      "Xcode.app once); builds can fail without them."
  if confirm "Install Xcode's first-launch components? (needs sudo)"; then
    run sudo env DEVELOPER_DIR="$XCODE_DEV" "$XCODEBUILD" -runFirstLaunch
    changed "Installed Xcode first-launch components" "(part of Xcode; removed with Xcode)"
    ok "First-launch components installed"
  else
    problem "Xcode first launch not finished: run  sudo xcodebuild -runFirstLaunch"
  fi
fi

# ============================================================ 3. Homebrew
step 3 "Homebrew (package manager)"
why "Installs the command-line tools listed in the repo's Brewfile."

if ! have brew; then
  # Installed but not on PATH in this shell (common in fresh terminals / CI).
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then eval "$("$candidate" shellenv)"; break; fi
  done
fi
if have brew; then
  ok "Homebrew $(brew --version 2>/dev/null | awk 'NR==1 {print $2}')"
else
  why "" "Homebrew is not installed. Its official installer (https://brew.sh) is downloaded and run;" \
      "it explains what it does and asks for your password itself. Afterwards it tells you to add" \
      "one line to your shell profile; that step is up to you."
  if confirm "Run the official Homebrew installer?"; then
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [ -x "$candidate" ]; then eval "$("$candidate" shellenv)"; break; fi
    done
    have brew || die "Homebrew was installed but 'brew' is not on PATH. Open a new terminal and run this script again."
    changed "Installed Homebrew" "see https://github.com/homebrew/install#uninstall-homebrew"
    ok "Homebrew installed"
  else
    problem "Homebrew is missing: install it from https://brew.sh"
  fi
fi

# ============================================================ 4. Brewfile tools
step 4 "Project tools from the Brewfile"
why "FVM (Flutter Version Management) installs the exact Flutter version pinned in .fvmrc," \
    "so everyone builds with the same SDK. It doesn't replace or affect any other Flutter on" \
    "this machine. It adds two commands to Homebrew's bin folder: 'fvm' and 'dartaotruntime'."

if ! have brew; then
  problem "Skipped: needs Homebrew"
else
  missing=""
  for formula in $(brewfile_formulae); do
    if brew list --formula "$formula" >/dev/null 2>&1; then
      ok "$formula already installed (left as is, not upgraded)"
    else
      missing="$missing $formula"
    fi
  done
  if [ -n "$missing" ]; then
    why "" "Preview of exactly what Homebrew would install (nothing is upgraded or cleaned up):"
    brew_guarded install --dry-run $missing 2>/dev/null \
      | sed -n '/^==> Would/,$p' | grep -v -e 'Downloading' -e 'Already downloaded' | sed 's/^/      /' || true
    if confirm "Install${missing}?"; then
      run env $BREW_GUARDS brew install $missing
      changed "Installed with Homebrew:${missing}" "brew uninstall${missing} && brew autoremove"
    else
      problem "Missing:${missing}: run  brew install${missing}"
    fi
  fi
fi

# ============================================================ 5. Flutter SDK (via FVM)
step 5 "Flutter SDK, pinned with FVM"
why "The Flutter version is stored in .fvmrc (committed), so another Mac gets the same version." \
    "If .fvmrc doesn't exist yet, the current stable release is pinned."

FLUTTER_READY=0
WANT_VERSION="${FLUTTER_VERSION:-}"
VERSION_SOURCE="FLUTTER_VERSION"
if [ -z "$WANT_VERSION" ]; then
  WANT_VERSION="$(pinned_version)"
  VERSION_SOURCE=".fvmrc"
fi
if [ -z "$WANT_VERSION" ]; then
  VERSION_SOURCE="latest stable"
  WANT_VERSION="$(latest_stable_flutter || true)"
fi

if [ -z "$WANT_VERSION" ]; then
  problem "Could not determine a Flutter version (no .fvmrc and the release index was unreachable). Set FLUTTER_VERSION=x.y.z and retry."
elif ! have fvm; then
  problem "Skipped: needs FVM (step 4). Wanted Flutter $WANT_VERSION ($VERSION_SOURCE)"
else
  ok "Wanted Flutter $WANT_VERSION ($VERSION_SOURCE)"

  # 5a. Pin the version in .fvmrc first, with FVM's edits of other files turned off.
  if [ "$(pinned_version)" = "$WANT_VERSION" ]; then
    ok ".fvmrc pins Flutter $WANT_VERSION"
  else
    why "" "Writes .fvmrc (commit it) pinning Flutter $WANT_VERSION."
    if confirm "Pin this repo to Flutter $WANT_VERSION?"; then
      write_fvmrc "$WANT_VERSION"
      changed "Wrote .fvmrc (Flutter $WANT_VERSION)" "git checkout -- .fvmrc  (or delete it)"
      ok "Pinned"
    else
      problem "Repo not pinned: rerun this script, or set FLUTTER_VERSION"
    fi
  fi

  # 5b. Download the SDK into FVM's cache.
  if fvm_has_version "$WANT_VERSION"; then
    ok "Flutter $WANT_VERSION is in the FVM cache"
  else
    why "" "Downloads Flutter $WANT_VERSION into FVM's cache in your home folder (about 3-5 GB" \
        "with its git cache). Nothing outside that folder and this repo is changed."
    if confirm "Download Flutter $WANT_VERSION with FVM?"; then
      (cd "$ROOT" && run fvm install "$WANT_VERSION" --skip-pub-get)
      changed "Downloaded Flutter $WANT_VERSION into the FVM cache" "fvm remove $WANT_VERSION"
    else
      problem "Flutter $WANT_VERSION not installed: run  fvm install $WANT_VERSION"
    fi
  fi

  # 5c. Link the SDK into .fvm/ (git-ignored) so VS Code finds it via .vscode/settings.json.
  if [ -e "$ROOT/.fvm/flutter_sdk" ]; then
    ok ".fvm/flutter_sdk links to the SDK"
  elif fvm_has_version "$WANT_VERSION" && [ "$(pinned_version)" = "$WANT_VERSION" ]; then
    if confirm "Create the .fvm/ link to the SDK for editors?"; then
      if (cd "$ROOT" && run fvm use "$WANT_VERSION" --force --skip-pub-get); then
        changed "Created .fvm/ link to the SDK" "rm -rf .fvm"
      else
        warn "'fvm use' failed. 'fvm flutter' still works; only editors may not find the SDK."
      fi
      # Restore our settings in case fvm rewrote .fvmrc without them.
      write_fvmrc "$WANT_VERSION"
    else
      warn "No .fvm/ link: VS Code may not find the SDK. 'fvm flutter' still works."
    fi
  fi

  if [ "$(pinned_version)" = "$WANT_VERSION" ] && flutter_fvm --version >/dev/null 2>&1; then
    FLUTTER_READY=1
    ok "$(flutter_fvm --version 2>/dev/null | head -1)"
  fi
fi

# ============================================================ 6. Flutter tool settings
step 6 "Flutter tool settings (optional)"
if [ "$FLUTTER_READY" != 1 ]; then
  problem "Skipped: needs the pinned Flutter SDK (step 5)"
else
  # 6a. Analytics: a privacy choice, so it's always asked, even with --yes.
  why "Flutter and Dart send anonymous usage statistics to Google unless you opt out." \
      "This is a per-user setting; it doesn't affect the app or other developers."
  if [ "$CHECK_ONLY" != 1 ] && [ "$ASSUME_YES" != 1 ] && confirm "Turn off Flutter/Dart usage analytics?"; then
    run flutter_fvm --disable-analytics
    run dart_fvm --disable-analytics
    changed "Turned off Flutter/Dart analytics" "fvm flutter --enable-analytics && fvm dart --enable-analytics"
  else
    ok "Analytics setting left unchanged"
  fi

  # 6b. Pre-download macOS engine files, so the first build works offline and starts faster.
  why "" "Downloads the Flutter engine files for macOS builds now (inside the SDK folder)," \
      "instead of during the first build."
  if confirm "Pre-download the macOS build artifacts?"; then
    run flutter_fvm precache --macos
  else
    ok "Skipped (they download automatically on the first build)"
  fi
fi

# ============================================================ 7. Project dependencies
step 7 "Project packages (pub get)"
if [ ! -f "$ROOT/pubspec.yaml" ]; then
  ok "No pubspec.yaml yet (the Flutter project hasn't been created). Nothing to do."
elif [ "$FLUTTER_READY" != 1 ]; then
  problem "Skipped: needs the pinned Flutter SDK (step 5)"
elif [ -f "$ROOT/.dart_tool/package_config.json" ] \
     && ! [ "$ROOT/pubspec.yaml" -nt "$ROOT/.dart_tool/package_config.json" ] \
     && ! [ "$ROOT/pubspec.lock" -nt "$ROOT/.dart_tool/package_config.json" ]; then
  # pub get writes pubspec.lock and package_config.json in the same second,
  # so "not newer" (not "older") is the up-to-date test.
  ok "Packages are up to date with pubspec.yaml and pubspec.lock"
else
  why "Downloads the Dart packages at the exact versions in pubspec.lock (into ~/.pub-cache)."
  if confirm "Run 'flutter pub get'?"; then
    run flutter_fvm pub get
  else
    problem "Packages not fetched: run  fvm flutter pub get"
  fi
fi
if [ -f "$ROOT/macos/Podfile" ]; then
  warn "macos/Podfile exists: some plugin requires CocoaPods. This project avoids CocoaPods" \
       "(see docs/reference/flutter-desktop.md). Replace that plugin, or install CocoaPods knowingly."
fi

# ============================================================ 8. flutter doctor
step 8 "Verify with 'flutter doctor'"
if [ "$FLUTTER_READY" != 1 ]; then
  problem "Skipped: needs the pinned Flutter SDK (step 5)"
else
  why "Checks the whole toolchain. For this desktop app only the Flutter, Xcode and" \
      "'Connected device (macOS)' lines matter. Android, Chrome, iOS and CocoaPods warnings can be ignored."
  flutter_fvm doctor -v || true
  devices="$(flutter_fvm devices 2>/dev/null || true)"
  case "$devices" in
    *[Mm]ac[Oo][Ss]*) ok "macOS is available as a build target" ;;
    *) problem "macOS is not listed by 'flutter devices'" ;;
  esac
fi

# ============================================================ 9. final verification
step 9 "Final verification (read-only, changes nothing)"
why "Re-checks every result from the steps above, and compares Homebrew and your PATH" \
    "with the snapshot taken before step 1, to make sure nothing else on this Mac changed."

# 9a. Toolchain.
why "" "Toolchain:"
if [ "$(xcode-select -p 2>/dev/null || true)" = "$XCODE_DEV" ]; then
  pass "Active developer directory is Xcode ($XCODE_DEV)"
else
  fail "Active developer directory is $(xcode-select -p 2>/dev/null || echo none), not Xcode"
fi
if DEVELOPER_DIR="$XCODE_DEV" "$XCODEBUILD" -license check >/dev/null 2>&1; then
  pass "Xcode license accepted"
else
  fail "Xcode license not accepted"
fi
if DEVELOPER_DIR="$XCODE_DEV" "$XCODEBUILD" -checkFirstLaunchStatus >/dev/null 2>&1; then
  pass "Xcode first-launch components installed"
else
  fail "Xcode first-launch components missing"
fi
if xcrun --find xcodebuild >/dev/null 2>&1; then
  pass "xcrun finds xcodebuild"
else
  fail "xcrun cannot find xcodebuild"
fi
if PATH="$ORIG_PATH" command -v fvm >/dev/null 2>&1; then
  pass "fvm is on your terminal's PATH ($(fvm --version 2>/dev/null || echo '?'))"
else
  fail "fvm is not on your terminal's PATH"
fi

# 9b. Flutter SDK matches the pin.
why "" "Flutter SDK:"
pinned="$(pinned_version)"
if [ -z "$pinned" ]; then
  fail ".fvmrc is missing or has no \"flutter\" version"
else
  pass ".fvmrc pins Flutter $pinned"
  for key in updateGitIgnore updateVscodeSettings updateMelosSettings; do
    if grep -q "\"$key\"[[:space:]]*:[[:space:]]*false" "$FVMRC"; then
      pass ".fvmrc: $key is false (FVM won't edit other files)"
    else
      fail ".fvmrc: $key is not false; FVM may edit repo files"
    fi
  done
  if have fvm; then
    machine="$(flutter_fvm --version --machine 2>/dev/null || true)"
    actual="$(printf '%s' "$machine" | sed -n 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    actual="${actual%%$'\n'*}"
    if [ "$actual" = "$pinned" ]; then
      pass "fvm flutter runs Flutter $actual (matches .fvmrc)"
    else
      fail "fvm flutter runs '${actual:-nothing}', expected $pinned"
    fi
    devices="$(flutter_fvm devices 2>/dev/null || true)"
    case "$devices" in
      *[Mm]ac[Oo][Ss]*) pass "macOS is available as a build target" ;;
      *) fail "macOS is not listed by 'fvm flutter devices'" ;;
    esac
  else
    fail "Cannot check the Flutter SDK: fvm is missing"
  fi
fi

# 9c. Project files.
why "" "Project:"
if [ -f "$ROOT/macos/Podfile" ]; then
  fail "macos/Podfile exists: a plugin requires CocoaPods (not allowed by the project rules)"
else
  pass "No CocoaPods Podfile"
fi
if [ -d "$ROOT/macos/Runner" ]; then
  for file in DebugProfile Release; do
    ent="$ROOT/macos/Runner/$file.entitlements"
    for key in com.apple.security.network.client com.apple.security.files.user-selected.read-write; do
      if [ -f "$ent" ] && grep -q "$key" "$ent"; then
        pass "$file.entitlements has $key"
      else
        fail "$file.entitlements lacks $key (see docs/reference/flutter-desktop.md §2)"
      fi
    done
  done
else
  pass "No macos/ folder yet (entitlements are checked once the project is created)"
fi

# 9d. Git hygiene: nothing secret or machine-specific gets committed.
if have git && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  why "" "Git:"
  if git -C "$ROOT" check-ignore -q .fvm/flutter_sdk; then pass ".fvm/ is git-ignored"; else fail ".fvm/ is NOT git-ignored"; fi
  for path in .fvmrc .vscode/settings.json; do
    if git -C "$ROOT" check-ignore -q "$path"; then fail "$path is git-ignored but must be committed"; else pass "$path will be committed"; fi
  done
  tracked="$(git -C "$ROOT" ls-files --cached --others --exclude-standard 2>/dev/null || true)"
  secrets="$(printf '%s\n' "$tracked" \
    | grep -E '(^|/)(\.env(\..+)?|key\.properties|Local\.xcconfig|AuthKey_.*\.p8|\.netrc)$|\.(pem|key|p8|p12|pfx|jks|keystore|mobileprovision|provisionprofile)$' \
    | grep -v '\.env\.example$' || true)"
  if [ -z "$secrets" ]; then
    pass "No secret-looking files are tracked or about to be committed"
  else
    fail "Secret-looking files would be committed: $(printf '%s' "$secrets" | tr '\n' ' ')"
  fi
fi

# 9e. Nothing else on the Mac changed.
why "" "The rest of your Mac (compared with the snapshot from before step 1):"
brew_snapshot > "$SNAP_DIR/brew.after"
path_snapshot > "$SNAP_DIR/path.after"
removed_or_changed="$(LC_ALL=C comm -23 "$SNAP_DIR/brew.before" "$SNAP_DIR/brew.after")"
added="$(LC_ALL=C comm -13 "$SNAP_DIR/brew.before" "$SNAP_DIR/brew.after")"
if [ -z "$removed_or_changed" ]; then
  pass "No Homebrew package was upgraded, downgraded or removed"
else
  fail "Homebrew packages changed or removed (before → see 'brew list --versions'):"
  printf '%s\n' "$removed_or_changed" | sed 's/^/        /'
fi
if [ -n "$added" ]; then
  why "  Newly installed by Homebrew (expected: fvm and dartaotruntime):"
  printf '%s\n' "$added" | sed 's/^/        /'
fi
path_changes="$(diff "$SNAP_DIR/path.before" "$SNAP_DIR/path.after" | sed -n 's/^> //p' || true)"
if [ -z "$path_changes" ]; then
  pass "These commands still resolve to the same place: $WATCHED_COMMANDS"
else
  fail "Commands that now resolve somewhere else on your PATH:"
  printf '%s\n' "$path_changes" | while read -r cmd now; do
    before="$(sed -n "s|^$cmd ||p" "$SNAP_DIR/path.before")"
    printf '        %s: %s -> %s\n' "$cmd" "$before" "$now"
  done
fi
if [ "$VERIFY_FAILED" -eq 0 ]; then
  ok "Final verification: all $VERIFY_PASSED checks passed"
else
  problem "Final verification: $VERIFY_FAILED of $((VERIFY_PASSED + VERIFY_FAILED)) checks failed"
fi

# ============================================================ summary
printf '\n%s==> Summary%s\n' "$BOLD" "$RESET"
if [ -n "$CHANGES" ]; then
  why "Changed in this run (and how to undo each):"
  printf '%s' "$CHANGES" | while IFS='|' read -r what undo; do
    [ -n "$what" ] || continue
    printf '      - %s\n          undo: %s\n' "$what" "$undo"
  done
else
  why "Nothing was changed in this run."
fi
if [ "$PROBLEMS" -eq 0 ]; then
  ok "Everything is ready."
  why "Run Flutter through FVM so the pinned version is used:" \
      "  fvm flutter run -d macos"
else
  problem "$PROBLEMS item(s) need attention (see the ✘ lines above). Fix them, or rerun this script without --check."
  exit 1
fi
