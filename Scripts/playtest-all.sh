#!/bin/bash
# Runs every scripted walk in Scripts/playtest, one after another, and prints a
# line per walk saying whether it passed. The point is repeatability: a walk
# that only passes the first time it is ever run on a machine is worse than no
# walk, so run this twice in a row and expect the same answers both times.
#
#   Scripts/playtest-all.sh --no-build a b  only the walks whose names match
#   Scripts/playtest-all.sh --no-build      reuse the built probe
#   PHOTONZ_SWEEP=1 Scripts/playtest-all.sh  all of them (see the gate below)
#
# Exits 0 when every walk passed. Never touches "dist/Photonz Dev.app".
#
# The whole set is now 322 walks, about 52 minutes, and it is GATED behind
# PHOTONZ_SWEEP=1. That is not a build flag, it is a guard rail: a task runner
# has its background work killed at 600s, and eight of the twenty recorded
# runner failures are a runner that started this script and was terminated
# waiting for it. Runners ask for a sweep instead, and the go loop runs it
# between tasks where nothing can kill it:
#
#   queue/bin/sweep.sh request "<why you want the whole set>"
#
# Naming walks (the third form above) is not gated: a handful of walks is
# seconds of work and is what you should be running while you build.
set -uo pipefail
cd "$(dirname "$0")/.."

BUILD=1
PATTERNS=()
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    *) PATTERNS+=("$arg") ;;
  esac
done

# The whole set costs about 52 minutes, which is five times the 600s ceiling on
# a task runner's background work, so running it from inside a task ends with
# the runner terminated and its task handed back unfinished. Point whoever did
# that at the way that survives instead of letting them start the run.
if (( ${#PATTERNS[@]} == 0 )) && [[ "${PHOTONZ_SWEEP:-0}" != 1 ]]; then
  cat >&2 <<'EOM'
!! Refusing to run all 300+ walks here: it takes about 52 minutes, and a task
!! runner's background work is terminated at 600s, so this run would be killed
!! and the task that started it would be handed back unfinished.
!!
!! Ask the go loop for a sweep instead. It runs between tasks, where nothing
!! kills it, and files a task naming any walk that fails:
!!
!!     queue/bin/sweep.sh request "<why you want the whole set>"
!!     queue/bin/sweep.sh status        # what the last sweep found
!!
!! While you are building, run only the walks you touched. Each is ~10s:
!!
!!     Scripts/playtest.sh Scripts/playtest/<name>.json --no-build
!!     Scripts/playtest-all.sh --no-build <name-fragment>
!!
!! If you are a person at a terminal and you really do want to sit through the
!! whole set, re-run with PHOTONZ_SWEEP=1.
EOM
  exit 2
fi

# Build the PROBE BUNDLE, which is the thing every walk below then runs
# against. A plain `swift build` here would warm a debug product nothing in
# this script ever launches, and the run would quietly report on whatever
# bundle happened to be sitting in dist/ (found 2026-09-05).
if [[ $BUILD == 1 ]]; then
  Scripts/probe-app.sh --quit >/dev/null 2>&1
  echo "==> Building the probe bundle..."
  Scripts/build-app.sh --probe >/dev/null || { echo "!! probe build failed"; exit 1; }
fi

PASSED=0
FAILED=()
# How long the run took, and how long each walk in it took, because "the full
# run takes about four hours" was a guess nobody could check. Every walk prints
# its own seconds and the run prints its total, so a walk that has started
# dragging its feet is visible in the same output that says it passed.
RUN_BEGAN=$SECONDS
SLOWEST=""
SLOWEST_S=0
for walk in Scripts/playtest/*.json; do
  name="$(basename "$walk" .json)"
  if (( ${#PATTERNS[@]} )); then
    match=0
    for p in "${PATTERNS[@]}"; do [[ "$name" == *"$p"* ]] && match=1; done
    (( match )) || continue
  fi
  printf '%-40s ' "$name"
  WALK_BEGAN=$SECONDS
  if out="$(Scripts/playtest.sh "$walk" --no-build 2>&1)"; then
    verdict="ok"
    PASSED=$((PASSED + 1))
  else
    reason="$(printf '%s' "$out" | sed -n 's/.*"error" : "\(.*\)",*$/\1/p' | head -1)"
    verdict="FAILED  ${reason:-no done.json}"
    FAILED+=("$name")
  fi
  TOOK=$((SECONDS - WALK_BEGAN))
  printf '%4ds  %s\n' "$TOOK" "$verdict"
  if (( TOOK > SLOWEST_S )); then SLOWEST_S=$TOOK; SLOWEST="$name"; fi
done

TOTAL=$((SECONDS - RUN_BEGAN))
RAN=$((PASSED + ${#FAILED[@]}))
echo
echo "==> $PASSED passed, ${#FAILED[@]} failed"
(( ${#FAILED[@]} == 0 )) || printf '    %s\n' "${FAILED[@]}"
printf '==> %d walks in %dm %02ds' "$RAN" $((TOTAL / 60)) $((TOTAL % 60))
(( RAN > 0 )) && printf ', %ds each on average' $((TOTAL / RAN))
[[ -n "$SLOWEST" ]] && printf '; slowest %s at %ds' "$SLOWEST" "$SLOWEST_S"
echo
exit $(( ${#FAILED[@]} == 0 ? 0 : 1 ))
