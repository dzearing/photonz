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

# Extra flags for every build this script makes, the tests' and the
# legibility check's alike, so the two stay one build. CI sets
# --disable-index-store (.github/workflows/ci.yml).
read -r -a build_flags <<< "${PHOTONZ_BUILD_FLAGS:-}"

# `swift build` or `swift test [list]` with the flags every build here
# shares, so building first and testing with --skip-build is one build.
swiftpm() {
  local cmd=("$1"); shift
  [[ "${cmd[0]}" == "test" && "${1:-}" == "list" ]] && { cmd+=(list); shift; }
  local fw=()
  if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    FW="$DEV_DIR/Library/Developer/Frameworks"
    LIB="$DEV_DIR/Library/Developer/usr/lib"
    fw=(-Xswiftc -F"$FW" -Xlinker -F"$FW"
        -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB")
  fi
  swift "${cmd[@]}" ${fw[@]+"${fw[@]}"} ${build_flags[@]+"${build_flags[@]}"} "$@"
}

# The suites marked `.serialized`, as Module.Type, read from the test sources.
serialized_suites() {
  local f mod
  for f in Tests/*/*.swift Tests/*/*/*.swift; do
    [[ -f "$f" ]] || continue
    mod="${f#Tests/}"; mod="${mod%%/*}"
    awk -v mod="$mod" '
      /@Suite/ { held = ""; inSuite = 1 }
      inSuite { held = held $0 " " }
      inSuite && match($0, /(struct|class|enum|actor)[ \t]+[A-Za-z_][A-Za-z0-9_]*/) {
        decl = substr($0, RSTART, RLENGTH); sub(/^(struct|class|enum|actor)[ \t]+/, "", decl)
        if (held ~ /\.serialized/) print mod "." decl
        inSuite = 0
      }' "$f"
  done | LC_ALL=C sort -u
}

# A suite as a --filter or --skip pattern: itself and every test in it.
unit_pattern() {
  printf '^%s(/|$)' "$(printf '%s' "$1" | sed 's/[][\.()*+?^$|{}]/\\&/g')"
}

# --shard K/N runs only the K-th of N slices of the suite, so several machines
# can share one run: GitHub's runners have three cores each, and the whole
# suite on one of them was 21 minutes of tests however it was ordered
# (2026-10-26), so CI and release run it as three jobs at once. Every suite
# type in every test target goes to one slice, so the N slices together are
# exactly the whole suite and a new suite lands in one by itself. They are
# dealt heaviest first, each to the slice carrying least so far, by the
# weights in Scripts/test-weights.tsv (measured by Scripts/test-weights.sh;
# a suite it does not list weighs a little), so the slices finish together.
# The checks after the tests (video kit, legibility) run in slice 1, which
# starts with their weight already on it.
shard=""
args=()
while (( $# )); do
  case "$1" in
    --shard) shard="${2:-}"; shift; (( $# )) && shift ;;
    --shard=*) shard="${1#--shard=}"; shift ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
shard_filters=()
shard_index=1
if [[ -n "$shard" ]]; then
  if ! [[ "$shard" =~ ^([0-9]+)/([0-9]+)$ ]] \
      || (( BASH_REMATCH[1] < 1 || BASH_REMATCH[1] > BASH_REMATCH[2] )); then
    echo "==> --shard wants K/N with 1 <= K <= N, e.g. --shard 2/3 (got '$shard')."
    exit 2
  fi
  shard_index=${BASH_REMATCH[1]}
  shard_count=${BASH_REMATCH[2]}
fi

# A target that imports one of our modules without listing it in Package.swift
# is not rebuilt when that module changes shape, and its tests then fail on
# correct code (2026-09-25, 2026-10-02). Caught here, before a build can go
# stale, rather than after a runner has chased the red.
if ! gaps="$(node Scripts/check-direct-imports.mjs)"; then
  echo "$gaps"
  exit 1
fi

# The slice's suites, as one --filter each. Listing builds the tests first.
shard_units=()
if [[ -n "$shard" ]]; then
  if ! listing="$(swiftpm test list 2>&1)"; then
    echo "$listing" | tail -40
    echo "==> Could not list the tests to cut slice $shard."
    exit 1
  fi
  weights=Scripts/test-weights.tsv
  [[ -f "$weights" ]] || weights=/dev/null
  while IFS= read -r unit; do
    shard_units+=("$unit")
    shard_filters+=(--filter "$(unit_pattern "$unit")")
  done < <(printf '%s\n' "$listing" \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*Tests\.' \
    | sed -E 's#/.*##' | LC_ALL=C sort -u \
    | awk -F'\t' -v k="$shard_index" -v n="$shard_count" '
        FNR == NR { if ($0 !~ /^#/ && NF >= 2) weight[$1] = $2 + 0; next }
        { units[++count] = $1; w[count] = ($1 in weight) ? weight[$1] : 0.1 }
        END {
          # Heaviest first, then by name, so every slice deals the same way.
          for (i = 2; i <= count; i++) {
            u = units[i]; x = w[i]
            for (j = i - 1; j >= 1 && (w[j] < x || (w[j] == x && units[j] > u)); j--) {
              units[j + 1] = units[j]; w[j + 1] = w[j]
            }
            units[j + 1] = u; w[j + 1] = x
          }
          load[1] = 40   # the video kit and legibility checks
          for (i = 1; i <= count; i++) {
            best = 1
            for (s = 2; s <= n; s++) if (load[s] < load[best]) best = s
            load[best] += w[i]
            if (best == k) print units[i]
          }
        }' "$weights" -)
  echo "==> Slice $shard: $(( ${#shard_filters[@]} / 2 )) suites."
  # Never a green slice that ran nothing: a listing this cannot read is an
  # error, not an empty slice.
  if (( ${#shard_filters[@]} == 0 )); then
    echo "$listing" | tail -20
    echo "==> Found no suites for slice $shard in the test listing above."
    exit 1
  fi
fi

# How many tests run at once: most of the cores, never all of them. A test
# whose body waits on the Mac's text recogniser, HEIF writer or movie encoder
# holds one of Swift's shared pool threads while it waits, and from macOS 27
# those frameworks need a free thread on that same pool to answer: with every
# pool thread held by a waiting test, nothing answers and the run parks for
# good (2026-10-26, three runs out of three; RecogniserLane.swift says how it
# was measured). Leaving a quarter of the pool free means a waiting test always
# has a thread to be answered on. Set it yourself to override.
if [[ -z "${SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH:-}" ]]; then
  cores="$(sysctl -n hw.activecpu 2>/dev/null || echo 4)"
  export SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=$(( cores - (cores + 3) / 4 ))
  (( SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH < 1 )) && export SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1
fi

# On a Mac with cores to spare, the whole suite (or a whole slice) is four
# `swift test` runs side by side on the one build made first:
#
#   * the suites marked `.serialized`. In one run, each next test of such a
#     suite joined the back of a queue of fourteen thousand, so those suites
#     crawled for the whole run and then finished alone for its last 80
#     seconds (2026-10-27: 277 s of tests, the last five suites serialized);
#   * PhotonzCoreTests. Its ten thousand small tests were dealt last and were
#     the run's last 50 seconds, every slot busy, while for most of the two
#     minutes before it the slots were held by render, media and text-reading
#     tests waiting on the GPU, the encoder or the recogniser and the helper
#     used 4 to 8 of the 16 cores;
#   * the heaviest of the rest, every suite Scripts/test-weights.tsv weighs at
#     ten seconds or more. One run deals its suites in no useful order, and
#     the heavy ones (a whole window separated, the agent's element scan, the
#     caliper sweep) were dealt as late as 130 s in and decided when it
#     ended; in a run of their own they all start at once;
#   * everything else, printed as it runs.
#
# Each run has its own pool, so the width above holds in each and no run can
# park another.
#
# The serialized suites named ...PerfTests, the stopwatch suites, are held
# back from all four and run last, on their own, three at a time, once every
# other run and the checks beside them have finished. Read beside the rest, a
# budget read whatever the rest was doing at that moment: 29.4 ms against 28
# for code that reads 8 alone (2026-10-27), a brush tile at 3.7 s against 3
# that reads 0.7 alone, the dearest chart at 64 ms against 55 that reads 9
# (releases v0.20.0 and v0.21.0). A same-moment ruler does not rescue that:
# the rulers slow down more than the work they are beside, so a gate that
# divides by one passes a real doubling under that load. Quiet, the budgets
# are tight enough that twice the work fails, and the timing run is a few
# seconds of the whole. Three at a time and they read what they read alone:
# the brush grid read 2060 ms four at a time, twice running, against 1490 to
# 1610 three or two at a time and 1500 alone (2026-10-30).
# Declare a new stopwatch suite `.serialized` and name it ...PerfTests and it
# lands there by itself.
#
# A run given its own arguments (--filter, -c release, ...) stays one run,
# exactly as asked, and so does a Mac with fewer than eight cores (GitHub's
# three core runners, where the tests were already CPU-bound in one run), or
# PHOTONZ_TEST_ONE_RUN=1.
split_runs=0
(( $# == 0 )) && [[ "${PHOTONZ_TEST_ONE_RUN:-0}" != "1" ]] \
  && (( $(sysctl -n hw.activecpu 2>/dev/null || echo 4) >= 8 )) && split_runs=1
serial_filters=()
timing_filters=()
core_args=()
heavy_args=()
rest_args=()
rest_runs=1
if (( split_runs )); then
  serial=()
  while IFS= read -r unit; do serial+=("$unit"); done < <(serialized_suites)
  heavy=()
  while IFS= read -r unit; do heavy+=("$unit"); done < <(
    awk -F'\t' '!/^#/ && NF >= 2 && $2 + 0 >= 10 && $1 !~ /^PhotonzCoreTests\./ { print $1 }' \
      Scripts/test-weights.tsv 2>/dev/null | LC_ALL=C sort -u)
  is_serialized() { printf '%s\n' ${serial[@]+"${serial[@]}"} | grep -qxF "$1"; }
  is_heavy() { printf '%s\n' ${heavy[@]+"${heavy[@]}"} | grep -qxF "$1"; }
  # A serialized stopwatch suite: it runs last, alone.
  is_timing() { [[ "$1" == *PerfTests ]] && is_serialized "$1"; }
  if [[ -n "$shard" ]]; then
    # This slice's own suites, split between the runs.
    for unit in ${shard_units[@]+"${shard_units[@]}"}; do
      if is_timing "$unit"; then timing_filters+=(--filter "$(unit_pattern "$unit")")
      elif is_serialized "$unit"; then serial_filters+=(--filter "$(unit_pattern "$unit")")
      elif [[ "$unit" == PhotonzCoreTests.* ]]; then core_args+=(--filter "$(unit_pattern "$unit")")
      elif is_heavy "$unit"; then heavy_args+=(--filter "$(unit_pattern "$unit")")
      else rest_args+=(--filter "$(unit_pattern "$unit")"); fi
    done
    (( ${#rest_args[@]} )) || rest_runs=0
  else
    core_args=(--filter '^PhotonzCoreTests\.')
    rest_args=(--skip '^PhotonzCoreTests\.')
    for unit in ${serial[@]+"${serial[@]}"}; do
      if is_timing "$unit"; then timing_filters+=(--filter "$(unit_pattern "$unit")")
      else serial_filters+=(--filter "$(unit_pattern "$unit")"); fi
      core_args+=(--skip "$(unit_pattern "$unit")")
      rest_args+=(--skip "$(unit_pattern "$unit")")
    done
    for unit in ${heavy[@]+"${heavy[@]}"}; do
      is_serialized "$unit" && continue
      heavy_args+=(--filter "$(unit_pattern "$unit")")
      rest_args+=(--skip "$(unit_pattern "$unit")")
    done
  fi
fi

# The whole output is kept only so the last lines can be looked at for a crash.
# Everything from the main run is still printed as it happens; the other
# runs are printed when they end.
log="$(mktemp -t photonz-test-XXXXXX)"
serial_log="$(mktemp -t photonz-test-serial-XXXXXX)"
core_log="$(mktemp -t photonz-test-core-XXXXXX)"
heavy_log="$(mktemp -t photonz-test-heavy-XXXXXX)"
timing_log="$(mktemp -t photonz-test-timing-XXXXXX)"
checks_log="$(mktemp -t photonz-test-checks-XXXXXX)"
parked="$(mktemp -t photonz-test-parked-XXXXXX)"
trap 'rm -f "$log" "$serial_log" "$core_log" "$heavy_log" "$timing_log" "$checks_log" "$parked"
      for p in ${watch_pid:-} ${serial_pid:-} ${core_pid:-} ${heavy_pid:-} ${checks_pid:-}; do kill "$p" 2>/dev/null; done' EXIT

# A run that goes quiet AND idle is stopped, with the tests it is parked in
# named, rather than left to sit. From 2026-10-10 the whole run sat at 0% CPU
# for ten to twenty minutes at a time, every runner waited it out, and nothing
# said where it was stuck until somebody ran `sample` by hand (the cause, text
# reads starving Swift's shared pool, is in Sources/PhotonzRender/RecogniserLane.swift).
#
# Quiet is no new output from either run for PHOTONZ_TEST_QUIET_LIMIT seconds
# (default 180). Idle is the test helpers using under two seconds of CPU
# between them across that time. A slow test is busy, so it is never stopped
# however quiet it is. Drill it with
#
#     PHOTONZ_TEST_PARK_DRILL=1 PHOTONZ_TEST_QUIET_LIMIT=30 Scripts/test.sh --filter ParkedRunDrill
quiet_limit="${PHOTONZ_TEST_QUIET_LIMIT:-180}"

# The test helpers this run started, found down our own process tree so another
# worktree's run on the same Mac is never touched.
our_helpers() {
  ps -A -o pid=,ppid=,comm= | awk -v root="$$" '
    { parent[$1] = $2; name[$1] = $3 }
    END {
      for (p in parent) {
        if (name[p] !~ /swiftpm-testing-helper$/) continue
        for (q = parent[p]; q > 1; q = parent[q]) if (q == root) { print p; break }
      }
    }' | sort -n | tr '\n' ' '
}

# CPU seconds the processes named have used between them, from ps's
# [[dd-]hh:]mm:ss.cc.
cpu_seconds() {
  local pid total=0
  for pid in "$@"; do
    total=$(( total + $(ps -o time= -p "$pid" 2>/dev/null | awk '{
      n = split($1, part, /[-:]/); s = 0
      for (i = 1; i <= n; i++) s = s * 60 + part[i]
      print int(s)
    }') + 0 ))
  done
  echo "$total"
}

watch_for_a_parked_run() {
  local size=-1 quiet=0 helpers="" cpu_then=0
  while sleep 10; do
    local now_size now_helpers
    now_size=$(cat "$log" "$serial_log" "$core_log" "$heavy_log" "$timing_log" 2>/dev/null | wc -c)
    now_helpers=$(our_helpers)
    if [[ "$now_size" != "$size" || "$now_helpers" != "$helpers" || -z "${now_helpers// /}" ]]; then
      size=$now_size; helpers=$now_helpers; quiet=0
      # shellcheck disable=SC2086
      [[ -n "${helpers// /}" ]] && cpu_then=$(cpu_seconds $helpers)
      continue
    fi
    quiet=$((quiet + 10))
    (( quiet < quiet_limit )) && continue
    local cpu_now; cpu_now=$(cpu_seconds $helpers)
    if (( cpu_now - cpu_then >= 2 )); then
      # Busy, just quiet. Start the clock again from here.
      quiet=0; cpu_then=$cpu_now; continue
    fi
    local stamp shots=() helper
    stamp=$(date +%Y%m%d-%H%M%S)
    for helper in $helpers; do
      shots+=("${TMPDIR:-/tmp}/photonz-test-parked-$stamp-$helper.txt")
      sample "$helper" 2 -file "${shots[${#shots[@]}-1]}" >/dev/null 2>&1
    done
    {
      echo
      echo "==> The test run has printed nothing for ${quiet}s and its helper used no CPU"
      echo "    in that time, so it is parked, not slow. Stopping it. Tests it was in:"
      cat "${shots[@]}" 2>/dev/null \
        | grep -oE '[A-Za-z0-9_]+Tests\.[A-Za-z0-9_]+\(|[A-Za-z0-9_]+Tests\.swift:[0-9]+' \
        | sed 's/($/()/' | sort | uniq -c | sort -rn | head -20 | sed 's/^/      /'
      echo "    Waiting in:"
      cat "${shots[@]}" 2>/dev/null \
        | grep -oE 'VNRecognizeTextRequest|CGImageDestinationFinalize|copyNextSampleBuffer|AVAssetReader[A-Za-z]*|FigSemaphoreWaitRelative|_dispatch_semaphore_wait_slow|_dispatch_group_wait_slow' \
        | sort | uniq -c | sort -rn | head -8 | sed 's/^/      /'
      echo "    The whole sample: ${shots[*]}"
      echo
    } | tee -a "$parked"
    # shellcheck disable=SC2086
    kill $helpers 2>/dev/null
    sleep 5
    # shellcheck disable=SC2086
    kill -9 $helpers 2>/dev/null
    return
  done
}

# The video kit (Sources/Photonz/VideoKit) must stand on its own: every video
# surface assembles it, and the gallery that draws it beside the mocks compiles
# it with nothing else. A typecheck of the kit alone is the guard that it never
# starts reading app state (`Scripts/video-kit-gallery.sh`). The one pure
# core file the kit leans on, the tile grids' column math, comes along.
#
# Every word and icon on every shared control is legible against what is drawn
# behind it, in every state, light and dark, over what can be behind it (the
# user, 2026-09-30: "I do not want white on white or black on black cases
# EVER"). The debug build the tests use draws the shipped controls and
# measures them: Sources/Photonz/DesignSystem/LegibilitySheet.swift says how,
# LegibilityCatalogue.swift lists what it draws. Next, at its defaults.
#
# Both run in slice 1 (or the whole suite) only. With split runs they go
# beside the tests, on the build already made; otherwise after them, after a
# `swift build` of the app.
after_checks() {
  local ok=0
  if ! swiftc -typecheck -parse-as-library -swift-version 6 \
      Sources/Photonz/VideoKit/*.swift Sources/PhotonzCore/TileGridPlan.swift \
      Scripts/video-kit-gallery.swift; then
    echo "==> The video kit no longer compiles on its own: a piece in Sources/Photonz/VideoKit reaches into the app."
    ok=1
  fi
  if [[ "${1:-}" != "built" ]] && ! swift build ${build_flags[@]+"${build_flags[@]}"} >/dev/null 2>&1; then
    echo "==> The app would not build for the legibility check."
    ok=1
  elif ! .build/debug/Photonz --legibility-sheet "${TMPDIR:-/tmp}/photonz-legibility" \
      -experiments.release next -experiments.next.flags defaults; then
    echo "==> A word or icon is unreadable against what is behind it (listed above)."
    ok=1
  fi
  return "$ok"
}

# PHOTONZ_TEST_EVENTS=<folder> keeps each run's swift-testing event stream
# there (rest, core, heavy, serial and timing .jsonl): when every test started and ended, which
# is how the split runs were measured.
events() {
  [[ -n "${PHOTONZ_TEST_EVENTS:-}" ]] || return 0
  mkdir -p "$PHOTONZ_TEST_EVENTS"
  rm -f "$PHOTONZ_TEST_EVENTS/$1.jsonl"
  printf '%s\n' --event-stream-version 0 --event-stream-output-path "$PHOTONZ_TEST_EVENTS/$1.jsonl"
}

# Runs the tests once, and with split runs the checks beside them. Sets status.
run_suite() {
  : > "$log"; : > "$serial_log"; : > "$core_log"; : > "$heavy_log"; : > "$timing_log"; : > "$checks_log"
  serial_pid=""; core_pid=""; heavy_pid=""; checks_pid=""; checks_status=0; checks_done=0
  if (( ! split_runs )); then
    swiftpm test ${shard_filters[@]+"${shard_filters[@]}"} "$@" 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    return
  fi
  swiftpm build --build-tests 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  (( status == 0 )) || return
  if (( shard_index == 1 )); then
    after_checks built > "$checks_log" 2>&1 &
    checks_pid=$!
  fi
  # shellcheck disable=SC2046
  if (( ${#serial_filters[@]} )); then
    swiftpm test --skip-build --ignore-lock $(events serial) "${serial_filters[@]}" > "$serial_log" 2>&1 &
    serial_pid=$!
  fi
  # shellcheck disable=SC2046
  if (( ${#core_args[@]} )); then
    swiftpm test --skip-build --ignore-lock $(events core) "${core_args[@]}" > "$core_log" 2>&1 &
    core_pid=$!
  fi
  # shellcheck disable=SC2046
  if (( ${#heavy_args[@]} )); then
    swiftpm test --skip-build --ignore-lock $(events heavy) "${heavy_args[@]}" > "$heavy_log" 2>&1 &
    heavy_pid=$!
  fi
  if (( rest_runs )); then
    # shellcheck disable=SC2046
    swiftpm test --skip-build --ignore-lock $(events rest) ${rest_args[@]+"${rest_args[@]}"} 2>&1 | tee -a "$log"
    status=${PIPESTATUS[0]}
  fi
  local run_status
  if [[ -n "$core_pid" ]]; then
    wait "$core_pid"; run_status=$?
    core_pid=""
    echo
    echo "==> PhotonzCoreTests, run beside the rest:"
    cat "$core_log"
    (( status == 0 )) && status=$run_status
  fi
  if [[ -n "$heavy_pid" ]]; then
    wait "$heavy_pid"; run_status=$?
    heavy_pid=""
    echo
    echo "==> The heaviest suites, run beside the rest:"
    cat "$heavy_log"
    (( status == 0 )) && status=$run_status
  fi
  if [[ -n "$serial_pid" ]]; then
    wait "$serial_pid"; run_status=$?
    serial_pid=""
    echo
    echo "==> The suites that run one test at a time, run beside the rest:"
    cat "$serial_log"
    (( status == 0 )) && status=$run_status
  fi
  if [[ -n "$checks_pid" ]]; then
    wait "$checks_pid"; checks_status=$?
    checks_pid=""; checks_done=1
  fi
  # The stopwatch suites, last and alone: nothing else of this run is left.
  # shellcheck disable=SC2046
  if (( ${#timing_filters[@]} )); then
    SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=$(( SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH < 3 ? SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH : 3 )) \
      swiftpm test --skip-build --ignore-lock $(events timing) "${timing_filters[@]}" > "$timing_log" 2>&1
    run_status=$?
    echo
    echo "==> The stopwatch suites (...PerfTests), run last with nothing beside them:"
    cat "$timing_log"
    (( status == 0 )) && status=$run_status
  fi
}

watch_for_a_parked_run &
watch_pid=$!

run_suite "$@"

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
  grep -qE 'unexpected signal code (10|11)|signal code (10|11)|Segmentation fault|Bus error' "$log" "$serial_log" "$core_log" "$heavy_log" "$timing_log"
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
  PHOTONZ_TEST_REBUILT=1 run_suite "$@"
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

if (( status == 0 && shard_index == 1 )); then
  if (( checks_done )); then
    cat "$checks_log"
    (( checks_status == 0 )) || status=1
  elif ! after_checks; then
    status=1
  fi
fi

exit "$status"
