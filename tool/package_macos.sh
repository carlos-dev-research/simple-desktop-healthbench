#!/usr/bin/env bash
#
# tool/package_macos.sh: build the macOS release app and put a ready-to-use
# zip in dist/ (Constitution XII.2):
#
#   dist/HealthBench-Evals-macOS-v<version>.zip
#
# The version comes from pubspec.yaml. ditto keeps the .app bundle intact
# (symlinks, permissions, code signature). An existing zip for the same
# version is replaced. Run from anywhere: ./tool/package_macos.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only" >&2; exit 1; }

version="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' pubspec.yaml | head -1)"
[ -n "$version" ] || { echo "No version in pubspec.yaml" >&2; exit 1; }

app="build/macos/Build/Products/Release/HealthBench Evals.app"
zip="dist/HealthBench-Evals-macOS-v${version}.zip"

echo "==> Building HealthBench Evals ${version} (release)"
fvm flutter build macos --release

echo "==> Checking the app"
codesign --verify --deep --strict "$app"
archs="$(lipo -archs "$app/Contents/MacOS/HealthBench Evals")"
echo "    signature ok · architectures: $archs"

echo "==> Packaging $zip"
mkdir -p dist
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

echo "==> Verifying the zip unpacks to a valid app"
check="$(mktemp -d)"
trap 'rm -rf "$check"' EXIT
ditto -x -k "$zip" "$check"
codesign --verify --deep --strict "$check/HealthBench Evals.app"

echo "    $(du -h "$zip" | cut -f1)  $zip"
