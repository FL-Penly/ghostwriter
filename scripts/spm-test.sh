#!/bin/bash
# Runs the GhostwriterKit tests with the Command Line Tools only (no Xcode).
# The CLT ship Testing.framework and XCTest outside the default search paths, so they are passed in by hand.
# Usage: scripts/spm-test.sh [swift test arguments, e.g. --filter CaptureTests]
set -euo pipefail
cd "$(dirname "$0")/../Packages/GhostwriterKit"
DEV=$(xcode-select -p)
F=$DEV/Library/Developer/Frameworks
L=$DEV/Library/Developer/usr/lib
FLAGS=(-Xswiftc "-F$F" -Xlinker "-F$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L")
[ -d "$F/Testing.framework" ] || FLAGS=()  # A full Xcode finds them on its own.
# Resolving the kit on its own drops the app's pins from its Package.resolved; put them back afterwards.
trap 'git checkout --quiet -- Package.resolved 2>/dev/null || true' EXIT
swift test "${FLAGS[@]}" "$@"
