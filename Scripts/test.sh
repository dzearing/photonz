#!/bin/bash
# Runs the full test suite. Works with full Xcode or with CommandLineTools alone.
#
# With CommandLineTools, swift-testing's Testing.framework is not on the default
# search paths, so we pass them explicitly. With full Xcode this is unnecessary
# and plain `swift test` is used.
#
# It also stands between you and ONE failure that is not about the code: a build
# folder holding half-rebuilt pieces that disagree about the shape of a type.
# Add a stored property to Layer, run the tests, and the helper dies with signal
# 11 inside a copy of a Layer while twenty checks report words they never read.
# Nothing there is a bug, and a person reading the red cannot tell. So a run
# that dies that way says so in plain words, throws the build folder away, and
# runs again from scratch; if it dies the same way twice, that is a real crash
# and you are told that too. A run that does not crash pays nothing for any of
# this.
set -uo pipefail
cd "$(dirname "$0")/.."

DEV_DIR="$(xcode-select -p)"

run_tests() {
  if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    FW="$DEV_DIR/Library/Developer/Frameworks"
    LIB="$DEV_DIR/Library/Developer/usr/lib"
    swift test \
      -Xswiftc -F"$FW" \
      -Xlinker -F"$FW" \
      -Xlinker -rpath -Xlinker "$FW" \
      -Xlinker -rpath -Xlinker "$LIB" \
      "$@"
  else
    swift test "$@"
  fi
}

# The whole output is kept only so the last lines can be looked at for a crash.
# Everything is still printed as it happens.
log="$(mktemp -t photonz-test-XXXXXX)"
trap 'rm -f "$log"' EXIT

run_tests "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

# A drill, so the path below is something that has been RUN rather than
# something that was written and hoped for. A stale build folder cannot be
# conjured on demand (adding a stored property to Layer produced it once on
# 2026-09-20 and a clean pass on 2026-09-22), so this pretends the run just
# died that way:
#
#     PHOTONZ_TEST_CRASH_DRILL=1 Scripts/test.sh --filter SomethingSmall
#
# It throws the build folder away and rebuilds for real, which is the whole
# point of drilling it.
if [[ "${PHOTONZ_TEST_CRASH_DRILL:-0}" == "1" && "${PHOTONZ_TEST_REBUILT:-0}" != "1" ]]; then
  echo "PHOTONZ_TEST_CRASH_DRILL: pretending the helper exited with unexpected signal code 11" \
    | tee -a "$log"
  status=1
fi

# Signal 11 is a segmentation fault and signal 10 is a bus error: both are a
# process reading memory laid out differently from the way the code that reads
# it was compiled to expect, which is exactly what a half-rebuilt package does.
# A genuine crash in the app gives the same signals, and that is fine: the
# second run finds it again and says so.
crashed_on_memory() {
  grep -qE 'unexpected signal code (10|11)|signal code (10|11)|Segmentation fault|Bus error' "$log"
}

if (( status != 0 )) && crashed_on_memory && [[ "${PHOTONZ_TEST_REBUILT:-0}" != "1" ]]; then
  cat <<'WHY'

==> The test helper did not fail, it DIED, on a signal that means it read
    memory laid out differently from the way it was compiled to expect.
    Almost always that is this build folder rather than this code: a type
    changed shape and only some of the pieces were rebuilt, so any failures
    printed above are about half a build and not about the app.

    Throwing .build away and running again from scratch. If it dies the same
    way a second time, the crash is real and worth chasing.

WHY
  rm -rf .build
  PHOTONZ_TEST_REBUILT=1 run_tests "$@" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  if (( status != 0 )) && crashed_on_memory; then
    cat <<'WHY'

==> It died the same way on a clean build folder, so this is a real crash in
    the code and not a stale build. `node Scripts/crash-report.mjs --file
    "$(ls -t ~/Library/Logs/DiagnosticReports/*.ips | head -1)"` reads the
    report macOS just wrote.

WHY
  fi
fi

# The video kit (Sources/Photonz/VideoKit) must stand on its own: every video
# surface assembles it, and the gallery that draws it beside the mocks compiles
# it with nothing else. A typecheck of the kit alone is the guard that it never
# starts reading app state (`Scripts/video-kit-gallery.sh`). The one pure
# core file the kit leans on, the tile grids' column math, comes along.
if (( status == 0 )); then
  if ! swiftc -typecheck -parse-as-library -swift-version 6 \
      Sources/Photonz/VideoKit/*.swift Sources/PhotonzCore/TileGridPlan.swift \
      Scripts/video-kit-gallery.swift; then
    echo "==> The video kit no longer compiles on its own: a piece in Sources/Photonz/VideoKit reaches into the app."
    status=1
  fi
fi

# Every word and icon on every shared control is legible against what is drawn
# behind it, in every state, light and dark, over what can be behind it (the
# user, 2026-09-30: "I do not want white on white or black on black cases
# EVER"). The debug build the tests just made draws the shipped controls and
# measures them: Sources/Photonz/DesignSystem/LegibilitySheet.swift says how,
# LegibilityCatalogue.swift lists what it draws. Next, at its defaults.
if (( status == 0 )); then
  if ! swift build >/dev/null 2>&1; then
    echo "==> The app would not build for the legibility check."
    status=1
  elif ! .build/debug/Photonz --legibility-sheet "${TMPDIR:-/tmp}/photonz-legibility" \
      -experiments.release next -experiments.next.flags defaults; then
    echo "==> A word or icon is unreadable against what is behind it (listed above)."
    status=1
  fi
fi

exit "$status"
