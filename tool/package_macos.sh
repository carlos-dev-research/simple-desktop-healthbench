#!/usr/bin/env bash
#
# tool/package_macos.sh: build the macOS release app from the committed code
# and put a ready-to-use zip in dist/ (Constitution XII.2):
#
#   dist/HealthBench-Evals-macOS-v<version>.zip
#
# Privacy: compiled apps keep the paths they were built from (for crash
# messages). To keep your home folder and username out of the shipped app,
# the build runs from a neutral temporary folder with its own package cache,
# and the script refuses to produce a zip if your home path is found inside.
#
# It builds HEAD (uncommitted changes are not included). The version comes
# from pubspec.yaml. ditto keeps the .app bundle intact (symlinks,
# permissions, code signature). An existing zip for the same version is
# replaced. Run from anywhere: ./tool/package_macos.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only" >&2; exit 1; }

version="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' pubspec.yaml | head -1)"
[ -n "$version" ] || { echo "No version in pubspec.yaml" >&2; exit 1; }
zip="$ROOT/dist/HealthBench-Evals-macOS-v${version}.zip"

if [ -n "$(git status --porcelain -- lib macos pubspec.yaml pubspec.lock)" ]; then
  echo "! Uncommitted app changes are NOT included: the zip is built from $(git rev-parse --short HEAD)."
fi

# Neutral build location: no home folder or username in any compiled path.
work="$(mktemp -d /tmp/healthbench-package.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src"
git archive HEAD | tar -x -C "$work/src"
export PUB_CACHE="$work/pub-cache"

echo "==> Building HealthBench Evals ${version} (release) from $(git rev-parse --short HEAD)"
(cd "$work/src" && fvm flutter pub get >/dev/null && fvm flutter build macos --release)
app="$work/src/build/macos/Build/Products/Release/HealthBench Evals.app"

echo "==> Checking the app"
codesign --verify --deep --strict "$app"
archs="$(lipo -archs "$app/Contents/MacOS/HealthBench Evals")"
echo "    signature ok · architectures: $archs"

echo "==> Privacy check: no personal paths inside the app"
leaks=""
for needle in "$HOME" "/Users/$(id -un)"; do
  found="$(grep -r -l -a -F "$needle" "$app" 2>/dev/null || true)"
  [ -n "$found" ] && leaks="$leaks$found"$'\n'
done
if [ -n "$leaks" ]; then
  echo "✘ Your home path was found in:" >&2
  printf '%s' "$leaks" | sed "s#$work/src/##" >&2
  exit 1
fi
echo "    none found"

echo "==> Packaging dist/$(basename "$zip")"
mkdir -p "$ROOT/dist"
rm -f "$zip"
(cd "$(dirname "$app")" && ditto -c -k --sequesterRsrc --keepParent "HealthBench Evals.app" "$zip")

echo "==> Verifying the zip unpacks to a valid app"
mkdir -p "$work/check"
ditto -x -k "$zip" "$work/check"
codesign --verify --deep --strict "$work/check/HealthBench Evals.app"

echo "    $(du -h "$zip" | cut -f1)  dist/$(basename "$zip")"
