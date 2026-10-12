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

# A target that imports one of our modules without listing it in Package.swift
# is not rebuilt when that module changes shape, and its tests then fail on
# correct code (2026-09-25, 2026-10-02). Caught here, before a build can go
# stale, rather than after a runner has chased the red.
if ! gaps="$(node Scripts/check-direct-imports.mjs)"; then
  echo "$gaps"
  exit 1
fi

# The whole output is kept only so the last lines can be looked at for a crash.
# Everything is still printed as it happens.
log="$(mktemp -t photonz-test-XXXXXX)"
parked="$(mktemp -t photonz-test-parked-XXXXXX)"
trap 'rm -f "$log" "$parked"; [[ -n "${watch_pid:-}" ]] && kill "$watch_pid" 2>/dev/null' EXIT

# A run that goes quiet AND idle is stopped, with the tests it is parked in
# named, rather than left to sit. From 2026-10-10 the whole run sat at 0% CPU
# for ten to twenty minutes at a time, every runner waited it out, and nothing
# said where it was stuck until somebody ran `sample` by hand (the cause, text
# reads starving Swift's shared pool, is in Sources/PhotonzRender/RecogniserLane.swift).
#
# Quiet is no new output for PHOTONZ_TEST_QUIET_LIMIT seconds (default 180).
# Idle is the test helper using under two seconds of CPU across that time. A
# slow test is busy, so it is never stopped however quiet it is. Drill it with
#
#     PHOTONZ_TEST_PARK_DRILL=1 PHOTONZ_TEST_QUIET_LIMIT=30 Scripts/test.sh --filter ParkedRunDrill
quiet_limit="${PHOTONZ_TEST_QUIET_LIMIT:-180}"

# The test helper this run started, found down our own process tree so another
# worktree's run on the same Mac is never touched.
our_helper() {
  ps -A -o pid=,ppid=,comm= | awk -v root="$$" '
    { parent[$1] = $2; name[$1] = $3 }
    END {
      for (p in parent) {
        if (name[p] !~ /swiftpm-testing-helper$/) continue
        for (q = parent[p]; q > 1; q = parent[q]) if (q == root) { print p; exit }
      }
    }'
}

# CPU seconds a process has used, from ps's [[dd-]hh:]mm:ss.cc.
cpu_seconds() {
  ps -o time= -p "$1" 2>/dev/null | awk '{
    n = split($1, part, /[-:]/); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + part[i]
    print int(s)
  }'
}

watch_for_a_parked_run() {
  local size=-1 quiet=0 helper="" cpu_then=0
  while sleep 10; do
    local now_size now_helper
    now_size=$(wc -c < "$log" 2>/dev/null || echo 0)
    now_helper=$(our_helper)
    if [[ "$now_size" != "$size" || "$now_helper" != "$helper" || -z "$now_helper" ]]; then
      size=$now_size; helper=$now_helper; quiet=0
      [[ -n "$helper" ]] && cpu_then=$(cpu_seconds "$helper")
      continue
    fi
    quiet=$((quiet + 10))
    (( quiet < quiet_limit )) && continue
    local cpu_now; cpu_now=$(cpu_seconds "$helper")
    if (( cpu_now - cpu_then >= 2 )); then
      # Busy, just quiet. Start the clock again from here.
      quiet=0; cpu_then=$cpu_now; continue
    fi
    local shot="${TMPDIR:-/tmp}/photonz-test-parked-$(date +%Y%m%d-%H%M%S).txt"
    sample "$helper" 2 -file "$shot" >/dev/null 2>&1
    {
      echo
      echo "==> The test run has printed nothing for ${quiet}s and its helper used no CPU"
      echo "    in that time, so it is parked, not slow. Stopping it. Tests it was in:"
      grep -oE '[A-Za-z0-9_]+Tests\.[A-Za-z0-9_]+\(|[A-Za-z0-9_]+Tests\.swift:[0-9]+' "$shot" \
        | sed 's/($/()/' | sort | uniq -c | sort -rn | head -20 | sed 's/^/      /'
      echo "    Waiting in:"
      grep -oE 'VNRecognizeTextRequest|CGImageDestinationFinalize|copyNextSampleBuffer|AVAssetReader[A-Za-z]*|FigSemaphoreWaitRelative|_dispatch_semaphore_wait_slow|_dispatch_group_wait_slow' "$shot" \
        | sort | uniq -c | sort -rn | head -8 | sed 's/^/      /'
      echo "    The whole sample: $shot"
      echo
    } | tee -a "$parked"
    kill "$helper" 2>/dev/null
    sleep 5
    kill -9 "$helper" 2>/dev/null
    return
  done
}

watch_for_a_parked_run &
watch_pid=$!

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

kill "$watch_pid" 2>/dev/null
wait "$watch_pid" 2>/dev/null
if [[ -s "$parked" ]]; then
  echo "==> Stopped: the run was parked, not failing. The tests above are where it sat."
  exit 4
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
