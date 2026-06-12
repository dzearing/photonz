#!/bin/bash
# Runs the full test suite. Works with full Xcode or with CommandLineTools alone.
#
# With CommandLineTools, swift-testing's Testing.framework is not on the default
# search paths, so we pass them explicitly. With full Xcode this is unnecessary
# and plain `swift test` is used.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV_DIR="$(xcode-select -p)"

if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
  FW="$DEV_DIR/Library/Developer/Frameworks"
  LIB="$DEV_DIR/Library/Developer/usr/lib"
  exec swift test \
    -Xswiftc -F"$FW" \
    -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
else
  exec swift test "$@"
fi
