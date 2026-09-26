#!/bin/bash
# Runs every scripted walk in Scripts/playtest, one after another, and prints a
# line per walk saying whether it passed. The point is repeatability: a walk
# that only passes the first time it is ever run on a machine is worse than no
# walk, so run this twice in a row and expect the same answers both times.
#
#   Scripts/playtest-all.sh --no-build a b  only the walks whose names match
#   Scripts/playtest-all.sh --only <file>   only the walks named in that file,
#                                           one exact name per line
#   Scripts/playtest-all.sh --no-build      reuse the built probe
#   PHOTONZ_SWEEP=1 Scripts/playtest-all.sh  all of them (see the gate below)
#
# Exits 0 when every walk passed, 1 when one failed or crashed, 5 when the run
# WENT BLIND because the app stopped launching, and 3 when the
# Mac's screen was locked: then the walks that look a control up by name were
# refused and the run covered only a part of the set, however many of the rest
# passed. A walk whose APP DIED is reported as a crash, with the frames it died
# in, and counted apart from ordinary failures: a crash used to print the same
# "no done.json" a slow walk prints, and four sweeps in a row read twenty-one
# crashes as seven slow walks (2026-09-17 night).
# Never touches "dist/Photonz Dev.app".
#
# The whole set is now about 560 walks and about 105 minutes (counted by
# queue/bin/sweep-size.mjs, never typed in), and it is GATED behind
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
# An EXACT list of walks to run, one name per line, for the loop's rotating
# check (queue/bin/sweep.sh slice). Substring patterns cannot express "these
# fifty and no others": a name is a substring of itself but also of its
# neighbours, so a list of fifty would quietly run sixty.
ONLY_FILE=""
NEXT_IS_ONLY=0
for arg in "$@"; do
  if (( NEXT_IS_ONLY )); then ONLY_FILE="$arg"; NEXT_IS_ONLY=0; continue; fi
  case "$arg" in
    --no-build) BUILD=0 ;;
    --only) NEXT_IS_ONLY=1 ;;
    *) PATTERNS+=("$arg") ;;
  esac
done
ONLY_NAMES=""
if [[ -n "$ONLY_FILE" ]]; then
  if [[ ! -s "$ONLY_FILE" ]]; then
    echo "!! --only $ONLY_FILE names no walks" >&2
    exit 2
  fi
  # Newline-delimited, with a newline at both ends, so a grep for the whole
  # line cannot match a name inside another name.
  ONLY_NAMES=$'\n'"$(cat "$ONLY_FILE")"$'\n'
fi

# The whole set is
# about 560 walks and about 105 minutes, which is eleven times the 600s ceiling
# on a task runner's background work, so running it from inside a task ends with
# the runner terminated and its task handed back unfinished. Point whoever did
# that at the way that survives instead of letting them start the run.
if (( ${#PATTERNS[@]} == 0 )) && [[ -z "$ONLY_FILE" && "${PHOTONZ_SWEEP:-0}" != 1 ]]; then
  cat >&2 <<'EOM'
!! Refusing to run the whole walk set here: it is
!! about 560 walks and about 105 minutes, and a task runner's background work
!! is terminated at 600s, so this run would be killed
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

# Hold the Mac awake for the length of the run.
#
# Every walk finds its controls BY NAME. Let the screen idle into sleep with a
# password asked for and it locks, and from that moment no control in the window
# carries a name, so every walk reports things missing that are on screen: the
# sweep that started 2026-09-14 20:42 was four minutes in when the Mac locked at
# 20:46:47, and it reported nineteen failures that were not in the app. So a run
# that starts on an unlocked screen finishes on one.
#
# -d -i holds off display sleep and idle sleep, which is what the screen saver
# and the lock that follows it hang off. Deliberately NOT -u: that posts user
# activity, which would light up a display somebody has already put to sleep, at
# whatever hour the loop happens to reach this. So this keeps an awake Mac awake
# and does nothing at all to a sleeping one. It is a power assertion rather than
# a process doing work, it is bounded by -t as well as by the trap below, and it
# can neither wake nor unlock a screen. Nothing here fights a person who locked
# the Mac on purpose; the walks simply say they could not run.
#
# How long to hold for is SIZED FROM THE SET, not written down. It was a flat two
# hours, chosen when a sweep was 52 minutes; by 2026-09-19 the set was 532 walks
# and a full sweep 106 minutes, so a run a little slower than usual would have
# outlived its own hold, let the screen idle into a lock with a hundred walks to
# go, and reported every one of them as refused. The hold has to outlast the
# sweep's wall-clock CAP rather than a good sweep, so it is that plus ten
# minutes for the probe build (queue/bin/sweep-size.mjs --awake-seconds).
AWAKE=""
awake_seconds() {
  if [[ -n "${PHOTONZ_WALK_AWAKE_SECONDS:-}" ]]; then echo "$PHOTONZ_WALK_AWAKE_SECONDS"; return; fi
  queue/bin/sweep-size.mjs --awake-seconds 2>/dev/null || echo 11400
}
# The hold outlives a SIGKILL, and the sweep's wall-clock stop is a SIGKILL: the
# trap below cannot run then, so the caffeinate is orphaned and holds the Mac
# awake for the rest of its -t. Seen for real on 2026-09-19, three hours of hold
# left behind by one forced stop. So the pid is written where the caller asked
# for it, and whoever forced the stop puts it down by pid rather than reaching
# for pkill, which would also kill a caffeinate the user started themselves.
#
# The go loop holds the Mac awake for as long as IT is working, gaps between
# sweeps included (queue/bin/go-loop.sh), and it says where by exporting
# PHOTONZ_LOOP_AWAKE_PIDFILE. When that hold is already live there is nothing a
# second one buys: assertions do not stack into a stronger hold, and two of them
# is two things to put down and one of them to get wrong. So defer to it, and
# leave no pidfile of our own, which is exactly what tells whoever stops this
# run (sweep.sh stop_the_run, sweep-recover.mjs) that there is no hold of ours
# to release. Neither of them ever touches the loop's, and the loop's is
# released by the loop's own pid going away, so it cannot outlive the loop.
hold_awake() {
  command -v caffeinate >/dev/null 2>&1 || return 0
  if [[ -s "${PHOTONZ_LOOP_AWAKE_PIDFILE:-/nonexistent}" ]]; then
    HELD_BY=$(cat "${PHOTONZ_LOOP_AWAKE_PIDFILE}" 2>/dev/null)
    if [[ -n "$HELD_BY" ]] && ps -o command= -p "$HELD_BY" 2>/dev/null | grep -q caffeinate; then
      echo "==> The go loop is already holding this Mac awake (pid $HELD_BY), so this run does not take a second hold."
      return 0
    fi
  fi
  caffeinate -d -i -t "$(awake_seconds)" &
  AWAKE=$!
  [[ -n "${PHOTONZ_WALK_AWAKE_PIDFILE:-}" ]] && echo "$AWAKE" > "$PHOTONZ_WALK_AWAKE_PIDFILE"
  return 0
}
release_awake() {
  [[ -n "${PHOTONZ_WALK_AWAKE_PIDFILE:-}" ]] && rm -f "$PHOTONZ_WALK_AWAKE_PIDFILE"
  [[ -n "$AWAKE" ]] || return 0
  kill "$AWAKE" 2>/dev/null
  wait "$AWAKE" 2>/dev/null
  AWAKE=""
  return 0
}
trap release_awake EXIT INT TERM
hold_awake

PASSED=0
FAILED=()
# Walks whose APP DIED part way through. Never folded into the failures: a
# failure is the app saying no, a crash is the app being gone, and only one of
# those means every walk after it is running against a question mark. Their
# names still go in the list under the counts, because the sweep files a bug
# from that list and a crash is the most filable thing there is.
CRASHED=()
CRASH_WHY=()
# Walks that DID NOT RUN, because the screen was locked. Never counted as
# failures: see Sources/Photonz/Playtest/PlaytestScreenState.swift.
LOCKED=0
# ...and how many of them, so a run of a handful says what it could not reach.
COULD_NOT_RUN=0
# Walks that had NO APP to run in, because the probe would not launch. Never
# failures: a walk nothing ran is unanswered. One on its own is a flake (a
# previous probe still shutting down); BLIND_AFTER in a row is the app not
# coming back, and the run stops there rather than marking the rest of the set
# broken. On 2026-09-21 it did not stop and wrote down 436 walks as failing in
# 0s each, on code that had passed 537 of 544 that morning.
BLIND_AFTER=5
BLIND_RUN=0
BLIND_FROM=""
BLIND=()
# How long the run took, and how long each walk in it took, because "the full
# run takes about four hours" was a guess nobody could check. Every walk prints
# its own seconds and the run prints its total, so a walk that has started
# dragging its feet is visible in the same output that says it passed.
RUN_BEGAN=$SECONDS
SLOWEST=""
SLOWEST_S=0
for walk in Scripts/playtest/*.json; do
  name="$(basename "$walk" .json)"
  if [[ -n "$ONLY_NAMES" ]]; then
    [[ "$ONLY_NAMES" == *$'\n'"$name"$'\n'* ]] || continue
  fi
  if (( ${#PATTERNS[@]} )); then
    match=0
    for p in "${PATTERNS[@]}"; do [[ "$name" == *"$p"* ]] && match=1; done
    (( match )) || continue
  fi
  printf '%-40s ' "$name"
  WALK_BEGAN=$SECONDS
  out="$(Scripts/playtest.sh "$walk" --no-build 2>&1)"
  code=$?
  if (( code == 0 )); then
    verdict="ok"
    PASSED=$((PASSED + 1))
    BLIND_RUN=0
  elif (( code == 5 )); then
    # There was no app. Not a pass, not a failure: unanswered.
    BLIND+=("$name")
    BLIND_RUN=$((BLIND_RUN + 1))
    (( BLIND_RUN == 1 )) && BLIND_FROM="$name"
    printf '%4ds  COULD NOT START  the probe would not launch, so nothing ran this walk\n' $((SECONDS - WALK_BEGAN))
    if (( BLIND_RUN >= BLIND_AFTER )); then
      echo
      echo "==> STOPPING: the app has failed to launch $BLIND_RUN times in a row, starting at $BLIND_FROM."
      echo "    This run has GONE BLIND. Carrying on would put every remaining walk in front of no app"
      echo "    and write it down as broken, which is exactly what happened on 2026-09-21: 436 walks"
      echo "    marked failing in 0s each, on code that had passed 537 of 544 that morning."
      echo "    The walks already answered above are real. Everything not run is unknown."
      echo "    What to chase is why the probe will not launch: Scripts/probe-app.sh"
      break
    fi
    continue
  elif (( code == 6 )); then
    # Somebody is using the Mac. Stop the whole batch rather than launching the
    # probe again under their hands; the walks not run are unknown, not passing.
    printf '%4ds  DEFERRED  somebody is using the Mac\n' $((SECONDS - WALK_BEGAN))
    echo
    echo "==> STOPPING: somebody is using the Mac. The walks answered above are real; the rest did not run."
    DEFERRED=1
    break
  elif (( code == 3 )); then
    BLIND_RUN=0
    # The screen is locked and THIS walk looks a control up by name, so it did
    # not run. Others still can: half the walk set never asks for a name, and
    # those run and photograph the app normally (PlaytestLockSafety). So the run
    # CARRIES ON either way and reports the part it managed. It used to stop
    # here when nothing was named, on the grounds that half a set is not the
    # state of the set; that was true and it cost three days of silence
    # (2026-09-15 to 2026-09-17), because half a set that SAYS it is half a set
    # still finds a regression on the day it lands.
    LOCKED=1
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1))
    printf '%4ds  COULD NOT RUN  it needs a control by name and the screen is locked\n' $((SECONDS - WALK_BEGAN))
    continue
  elif (( code == 4 )); then
    # The app died. playtest.sh has already looked up what macOS wrote down
    # about it and put it on one line for us.
    why="$(printf '%s' "$out" | sed -n 's/^==> Verdict: CRASHED  //p' | head -1)"
    why="${why:-the app quit part way through}"
    verdict="CRASHED  $why"
    CRASHED+=("$name")
    CRASH_WHY+=("$why")
    BLIND_RUN=0
  else
    # A walk that simply ran out of road says so in its own words; only a walk
    # that left nothing at all falls back to "no done.json", and now that a
    # crash and a timeout both speak up, that fallback means what it says.
    reason="$(printf '%s' "$out" | sed -n 's/^==> Verdict: //p' | head -1)"
    [[ -n "$reason" ]] || reason="$(printf '%s' "$out" | sed -n 's/.*"error" : "\(.*\)",*$/\1/p' | head -1)"
    verdict="FAILED  ${reason:-no done.json}"
    FAILED+=("$name")
    BLIND_RUN=0
  fi
  TOOK=$((SECONDS - WALK_BEGAN))
  printf '%4ds  %s\n' "$TOOK" "$verdict"
  if (( TOOK > SLOWEST_S )); then SLOWEST_S=$TOOK; SLOWEST="$name"; fi
done

TOTAL=$((SECONDS - RUN_BEGAN))
RAN=$((PASSED + ${#FAILED[@]} + ${#CRASHED[@]}))
echo
# A run stopped by the lock is NOT a verdict on the walk set. Say so first and
# on its own line, so nothing downstream reads the counts underneath as one.
if (( LOCKED )); then
  echo "==> $COULD_NOT_RUN walk(s) COULD NOT RUN: the Mac's screen is locked."
  echo "    The app keeps drawing, animating, taking the walk's clicks and being photographed."
  echo "    What a locked screen takes away is the NAME on every control, so a walk that looks"
  echo "    one up reports it missing while it is on screen at the right size with the right"
  echo "    tooltip. Those walks are not a pass and not a failure: they did not run."
  if (( RAN )); then
    echo "    The other $RAN walk(s) never ask for a name, so they ran for real and their"
    echo "    counts are real, pictures of the window included."
  fi
  echo "    Unlock the screen to run the rest."
fi
# The app not being there at all. Said above the counts, because the counts
# underneath are about the walks that DID get an app; the rest are unanswered
# and are never named as failures anywhere.
if (( ${#BLIND[@]} )); then
  echo "==> ${#BLIND[@]} walk(s) COULD NOT START: the probe would not launch, beginning at $BLIND_FROM."
  echo "    Nothing ran them, so they are not a pass and not a failure. They are unknown."
  echo "    Whatever is wrong is with launching the app, not with those walks: chase it in"
  echo "    Scripts/probe-app.sh and in the output above, and run one of them on its own."
  if (( RAN )); then
    echo "    The $RAN walk(s) answered before that are real and their counts below are real."
  fi
fi
# A crash is not a slow walk and must never read as one. Say it above the
# counts, with what it died in, because that line is the whole point: the loop
# reads these words and nothing else.
if (( ${#CRASHED[@]} )); then
  echo "==> ${#CRASHED[@]} walk(s) CRASHED: the app was GONE before the walk finished."
  echo "    That is not a walk running slowly: everything the app was holding went with it, and"
  echo "    whatever the walk was about is unanswered. The frames below run from where it died"
  echo "    down to what was being done; read < as \"called from\", and the fuller stack is in"
  echo "    each walk's own output above."
  for i in "${!CRASHED[@]}"; do
    printf '    %s: %s\n' "${CRASHED[$i]}" "${CRASH_WHY[$i]}"
  done
  echo "    Crash reports: ~/Library/Logs/DiagnosticReports"
fi
# The counts, in the one shape every reader of this log parses: the crash count
# is only there when something crashed and the refused count only when a lock
# turned walks away, and the broken walks are the indented lines under it and
# nothing else (queue/bin/sweep-parse.mjs).
COUNTS="==> $PASSED passed, ${#FAILED[@]} failed"
(( ${#CRASHED[@]} )) && COUNTS="$COUNTS, ${#CRASHED[@]} crashed"
(( LOCKED )) && COUNTS="$COUNTS, $COULD_NOT_RUN could not run"
(( ${#BLIND[@]} )) && COUNTS="$COUNTS, ${#BLIND[@]} could not start"
echo "$COUNTS"
(( ${#FAILED[@]} == 0 )) || printf '    %s\n' "${FAILED[@]}"
(( ${#CRASHED[@]} == 0 )) || printf '    %s\n' "${CRASHED[@]}"
printf '==> %d walks in %dm %02ds' "$RAN" $((TOTAL / 60)) $((TOTAL % 60))
(( RAN > 0 )) && printf ', %ds each on average' $((TOTAL / RAN))
[[ -n "$SLOWEST" ]] && printf '; slowest %s at %ds' "$SLOWEST" "$SLOWEST_S"
echo
# Exit 3 means THE SET WAS NOT COVERED: some walks were refused for the lock, so
# whatever ran is a part and never the state of the set. The sweep records it as
# a partial, keeps its request pending, and still files any walk that FAILED in
# the part that ran.
# Exit 5 means THE RUN WENT BLIND: the app stopped launching, so a stretch of
# the set was never put in front of anything. It outranks the lock, because a
# locked run at least had an app.
(( ${DEFERRED:-0} )) && exit 6
(( ${#BLIND[@]} )) && exit 5
(( LOCKED )) && exit 3
exit $(( ${#FAILED[@]} + ${#CRASHED[@]} == 0 ? 0 : 1 ))
