#!/bin/bash
# Builds and launches the task loop's OWN copy of Photonz, so an unmanned
# runner can look at a real running app without ever touching the one a person
# is using.
#
#   Scripts/probe-app.sh                 build, relaunch, report
#   Scripts/probe-app.sh <file> [...]    ...and open these files in it
#   Scripts/probe-app.sh --no-build      relaunch the existing probe bundle
#   Scripts/probe-app.sh --playtest <script.json> [--no-build]
#                                        ...and run a scripted playtest in it
#                                        (Scripts/playtest.sh waits for it too)
#   Scripts/probe-app.sh --quit          quit the probe and leave
#
# Every launch ends with a "Grants:" line saying whether the probe may record
# the screen and whether this terminal may drive other apps. Read it before you
# claim a screenshot is real: without the grant the probe writes offscreen
# renders only, and an audit has to say so.
#
# Why this exists: "dist/Photonz Dev.app" is somebody's app. Rebuilding it
# quits their session, and because a screen-capture client whose binary changed
# has to be re-authorized, it also makes macOS re-ask for Screen Recording. The
# probe is a separate bundle (com.dzearing.photonz.probe, "Photonz Probe.app")
# that nobody plays with, so it can be replaced as often as you like.
#
# Use THIS instead of hand-rolling build + pkill + open. A stray
# `pkill -f "Photonz Dev"` is exactly the mistake this script exists to prevent;
# every process match here is pinned to the probe bundle's own executable path.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Photonz Probe.app"
# Written by the probe itself at launch (Sources/Photonz/Playtest/ProbeGrants.swift).
# Nothing in the shell can ask TCC about another app's grant, so the app answers.
GRANTS="dist/probe-grants.json"
# Anchored on the bundle's executable path, so it can never match "Photonz
# Dev.app", "Photonz.app", or a bare `swift build` run.
MATCH="Photonz Probe.app/Contents/MacOS"

BUNDLE_ID="com.dzearing.photonz.probe"

# Whether LaunchServices still counts the probe as running. `open` asks it, not
# the process table, and answers -600 while it does.
probe_listed() {
  [[ -n "$(lsappinfo find "bundleid=$BUNDLE_ID" 2>/dev/null)" ]]
}

# Gone means gone to the kernel AND to LaunchServices. A process that is
# exiting drops its command line (ps shows "(Photonz Probe)"), so `pgrep -f`
# stops matching the moment the kill lands while the process is still there
# and LaunchServices still lists it. Waiting on pgrep alone let the next launch
# run into that window, and after the five minute 1080p export walk (Metal and
# the video encoder to tear down) it was wide enough every time: `open` failed
# with error -600 and five walks in a row read COULD NOT START, which is how
# both whole-set runs of 2026-09-28 went blind. So remember the pids, wait on
# them with kill -0 (which still sees an exiting process), and on
# LaunchServices letting go; SIGKILL if a quit ever takes longer than 15s.
quit_probe() {
  local pids p alive i
  pids="$(pgrep -f "$MATCH" 2>/dev/null || true)"
  # shellcheck disable=SC2086
  [[ -n "$pids" ]] && kill $pids 2>/dev/null || true
  for ((i = 0; i < 200; i++)); do
    alive=0
    for p in $pids; do kill -0 "$p" 2>/dev/null && alive=1; done
    (( alive )) || probe_listed || return 0
    if (( i == 150 && alive )); then
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
    fi
    sleep 0.1
  done
  echo "!! The last probe was still going away 20s after it was told to quit." >&2
}

BUILD=1
PLAYTEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quit)     quit_probe; node Scripts/probe-crash-alert.mjs close || true; echo "==> Probe quit."; exit 0 ;;
    --no-build) BUILD=0; shift ;;
    --playtest)
      [[ -f "${2:-}" ]] || { echo "!! --playtest needs a script file (got '${2:-}')" >&2; exit 1; }
      PLAYTEST="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
    *) break ;;
  esac
done

if [[ "$BUILD" == "1" ]]; then
  Scripts/build-app.sh --probe
fi
[[ -d "$APP" ]] || { echo "!! $APP does not exist; run without --no-build" >&2; exit 1; }

quit_probe
# A crash of the last probe (a macOS fault, or a runner crashing it on purpose)
# leaves "Photonz (Probe) quit unexpectedly" up over the person's work, and
# while it is up no app can take focus, so this walk would fail for want of a
# key window. Close it if, and only if, it is the probe's, then note the newest
# window on the Mac so the next close can tell. See Scripts/probe-crash-alert.mjs.
node Scripts/probe-crash-alert.mjs close || true
node Scripts/probe-crash-alert.mjs mark || true
# The probe rewrites this at launch; drop it first so a failed launch reports
# "unknown" rather than yesterday's answer.
rm -f "$GRANTS"
# Which release the probe is running is a SETTING, kept between launches like
# any other, and no walk declares it. So a probe left on Current ran every walk
# afterwards against an app with a different right hand panel, reporting
# pass and fail as confidently as ever: the walk that asks for the Effects list
# just failed at whatever step first wanted something Current does not have.
# Every walk is written against Next (CLAUDE.md), so pin it here, once, before
# each launch. Nothing else in the probe's memory is touched: a walk says what
# it wants forgotten in its own `setup` block.
defaults write com.dzearing.photonz.probe "experiments.release" -string next
# A playtest script rides in as a launch argument (docs/design/playtest-harness.md);
# only the probe bundle acts on it.
ARGS=()
[[ -n "$PLAYTEST" ]] && ARGS=(--args --playtest "$PLAYTEST")
# `open` starts the app from launchd, not from this shell, so anything the
# harness reads out of the environment has to be handed over on purpose.
# PHOTONZ_PLAYTEST_PACE=full puts every `wait` step back on the clock, which is
# how a walk that has turned flaky says whether the pacing moved under it.
# PHOTONZ_ALLOW_LOCKED_WALK=1 lets a walk run with the screen locked, which only
# somebody working on the harness itself wants: the run still records that the
# screen was locked, so it is a way to watch the machinery, never a way to earn
# a pass. See Sources/Photonz/Playtest/PlaytestScreenState.swift.
# Whether the person at the Mac has to step away first (queue/bin/person-at-mac.sh).
# On 2026-09-26 the probe driving itself made the user's machine unusable, so
# until the whole walk set had been measured with queue/bin/focus-drill.sh every
# launch waited for the keyboard and mouse to be left alone. Every walk now
# leaves the person's keyboard, focus and screen alone (measured over all of
# them on 2026-09-26), so a walk launches whoever is at the Mac. Two launches
# still wait:
#   - a walk that needs the Mac to itself (queue/bin/walk-needs-the-mac.mjs):
#     it photographs an open menu, makes a real drag, or holds the front, and
#     each of those takes every key on the Mac while it lasts;
#   - a launch with no walk at all: nothing tells the app a walk is driving it,
#     so opening a file brings it to the front like any app.
# They wait for PHOTONZ_WALK_IDLE seconds of no input (default 60), up to
# PHOTONZ_WALK_IDLE_WAIT (default 240), then give up with exit 6, which means
# DEFERRED: nothing ran, nothing is broken.
MUST_WAIT=1
if [[ -n "$PLAYTEST" ]] && ! queue/bin/walk-needs-the-mac.mjs "$PLAYTEST" >/dev/null 2>&1; then
  MUST_WAIT=0
fi
WAITED=0
until (( ! MUST_WAIT )) || queue/bin/person-at-mac.sh away "${PHOTONZ_WALK_IDLE:-60}"; do
  if (( WAITED == 0 )); then
    if [[ -n "$PLAYTEST" ]]; then
      echo "==> Somebody is using this Mac, and this walk $(queue/bin/walk-needs-the-mac.mjs "$PLAYTEST"); waiting for them to step away."
    else
      echo "==> Somebody is using this Mac; waiting for them to step away before launching the probe with no walk to drive."
    fi
  fi
  if (( WAITED >= ${PHOTONZ_WALK_IDLE_WAIT:-240} )); then
    echo "==> Verdict: DEFERRED  somebody was using this Mac for ${WAITED}s, so the probe was not launched"
    exit 6
  fi
  sleep 5; WAITED=$((WAITED + 5))
done
ENVS=()
[[ -n "${PHOTONZ_PLAYTEST_PACE:-}" ]] && ENVS=(--env "PHOTONZ_PLAYTEST_PACE=$PHOTONZ_PLAYTEST_PACE")
[[ "${PHOTONZ_ALLOW_LOCKED_WALK:-}" == "1" ]] && ENVS+=(--env "PHOTONZ_ALLOW_LOCKED_WALK=1")
# quit_probe waits for LaunchServices to let the last probe go, so -600 here
# should not happen; if it still does (a quit slower than the wait), wait again
# and try twice more rather than handing the walk no app.
OPEN_ERR=""
for attempt in 1 2 3; do
  set +e
  if [[ $# -gt 0 ]]; then
    OPEN_ERR="$(open -g -a "$PWD/$APP" ${ENVS[@]+"${ENVS[@]}"} "$@" ${ARGS[@]+"${ARGS[@]}"} 2>&1)"
  else
    OPEN_ERR="$(open -g -a "$PWD/$APP" ${ENVS[@]+"${ENVS[@]}"} ${ARGS[@]+"${ARGS[@]}"} 2>&1)"
  fi
  OPEN_CODE=$?
  set -e
  (( OPEN_CODE == 0 )) && break
  echo "!! open failed (try $attempt of 3): $OPEN_ERR" >&2
  (( attempt < 3 )) || exit 1
  quit_probe
  sleep 1
done

# The app is a menu-bar agent: no window and no Dock icon is the normal state,
# so confirm the process rather than looking for something on screen.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PID="$(pgrep -f "$MATCH" | head -1 || true)"
  [[ -n "$PID" ]] && break
  sleep 0.5
done
if [[ -z "${PID:-}" ]]; then
  echo "!! Probe did not come up. Check ~/Library/Logs/DiagnosticReports for a crash." >&2
  exit 1
fi
echo "==> Photonz (Probe) running, pid $PID. Quit it with: Scripts/probe-app.sh --quit"

# --- What this run is allowed to see -----------------------------------------
# One line, every launch, because an audit that says "verified live" is only
# worth reading if the loop could actually look. The probe reports its own
# Screen Recording grant; permcheck.swift reports this terminal's. Neither
# prompts: the probe raises the system dialog at most once per launch and only
# while the grant is still undetermined, and the terminal side never prompts at
# all, since that dialog would land on top of whatever a person is doing.

# The app that owns this terminal is who macOS hangs its grants on, so name it
# rather than saying "your terminal" and leaving a person to guess which one.
terminal_app() {
  local pid=$PPID name
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -z "$pid" || "$pid" -le 1 ]]; then break; fi
    name="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    if [[ "$name" == *".app/Contents/MacOS/"* ]]; then
      name="${name%%.app/Contents/MacOS/*}"
      echo "${name##*/}"
      return
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
  done
  echo "this terminal"
}

SCREEN="unknown"
LOCKED="unknown"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -f "$GRANTS" ]]; then
    SCREEN="$(node -e 'const g = require("fs").readFileSync(process.argv[1], "utf8");
      console.log(JSON.parse(g).screenRecording ? "granted" : "denied")' "$GRANTS" 2>/dev/null || echo unknown)"
    LOCKED="$(node -e 'const g = require("fs").readFileSync(process.argv[1], "utf8");
      console.log(JSON.parse(g).screenLocked ? "locked" : "unlocked")' "$GRANTS" 2>/dev/null || echo unknown)"
    break
  fi
  sleep 0.3
done

AX="unknown"
AUTOMATION="unknown"
while IFS='=' read -r key value; do
  case "$key" in
    accessibility) AX="$value" ;;
    automation) AUTOMATION="$value" ;;
  esac
done < <(swift Scripts/permcheck.swift 2>/dev/null || true)

TERM_APP="$(terminal_app)"

# Is the go loop holding this Mac awake? It takes that hold for as long as it is
# working (queue/bin/go-loop.sh), so a walk running under the loop is normally on
# a Mac that will not lock itself part way through. It goes on this line because
# the honest version of it is the part that matters: a hold stops the NEXT lock
# and does nothing at all to a lock already in place.
HELD_AWAKE=no
AWAKE_PIDFILE="${PHOTONZ_LOOP_AWAKE_PIDFILE:-queue/.loop-awake.pid}"
if [[ -s "$AWAKE_PIDFILE" ]]; then
  HELD_PID="$(cat "$AWAKE_PIDFILE" 2>/dev/null || true)"
  if [[ -n "$HELD_PID" ]] && ps -o command= -p "$HELD_PID" 2>/dev/null | grep -q caffeinate; then
    HELD_AWAKE=yes
  fi
fi

# Is a system alert holding the front? While one is up (the "quit unexpectedly"
# dialog after a crash is the usual one) no app can become active, so the probe's
# window is never key, and a key window is what a SwiftUI tap or drag needs
# before it will take a click. Buttons still fire, so nothing looks wrong
# except that every click on the timeline does nothing. From 2026-09-25 23:22
# to 09-26 12:50 one "Photonz (Probe) quit unexpectedly" dialog did exactly
# that to every walk (clicking-a-cut-opens-the-transition-picker-again).
FRONT="$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
  | sed -n 's/.*="\(.*\)"/\1/p' || true)"
ALERT_IN_FRONT=no
if [[ "$FRONT" == "com.apple.UserNotificationCenter" ]]; then ALERT_IN_FRONT=yes; fi

LINE="==> Grants: probe Screen Recording $SCREEN · $TERM_APP Accessibility $AX · screen $LOCKED"
if [[ "$ALERT_IN_FRONT" == yes ]]; then LINE="$LINE · a system alert is in front"; fi
if [[ "$HELD_AWAKE" == yes ]]; then LINE="$LINE · the loop is holding this Mac awake"; fi
if [[ "$AUTOMATION" != "unknown" ]]; then LINE="$LINE · Automation $AUTOMATION"; fi
echo "$LINE"

# Each grant buys a different thing, so say which one is missing and what it
# costs. Both survive rebuilds (the probe is signed with the stable dev
# identity), so this is asked once per machine, not once per run.
if [[ "$LOCKED" == "locked" ]]; then
  echo "    THE SCREEN IS LOCKED. The app still draws, animates, takes clicks and can be"
  echo "    photographed, so a walk that never looks a control up by name runs normally and"
  echo "    its pictures are the real window (they carry a label saying they were taken under"
  echo "    a lock). A walk that does look one up is refused, because a name comes back empty"
  echo "    now and its failures would be about the lock rather than about the app."
  echo "    Which steps are which: Sources/PhotonzCore/PlaytestLockSafety.swift"
  if [[ "$HELD_AWAKE" == yes ]]; then
    echo "    The loop holding this Mac awake does NOT undo this lock and never will: it stops"
    echo "    the NEXT one. Only a person logging in clears this, and until somebody does, every"
    echo "    run here is a run on a locked screen."
  fi
fi
if [[ "$ALERT_IN_FRONT" == yes ]]; then
  echo "    A SYSTEM ALERT IS IN FRONT, usually \"Photonz (Probe) quit unexpectedly\" after a"
  echo "    crash. Until it goes, no app can take focus: buttons still work, but a click on"
  echo "    the timeline (a cut, a clip, the Blade, a caption bar) does NOTHING, and every"
  echo "    walk that makes one fails for a reason that is not in the app. The probe's own"
  echo "    crash alert is closed before every launch (Scripts/probe-crash-alert.mjs), so this"
  echo "    one is somebody else's or was up before the probe started: whoever is at the Mac"
  echo "    clicks it away."
fi
if [[ "$SCREEN" != "granted" ]]; then
  echo "    No real screenshots: the probe can only write offscreen renders, and an audit"
  echo "    must say so. Fix once in System Settings > Privacy & Security > Screen & System"
  echo "    Audio Recording: tick \"Photonz Probe\"."
fi
if [[ "$AX" != "granted" ]]; then
  echo "    No driving OTHER apps: keystrokes and clicks aimed outside Photonz fail."
  echo "    Photonz's own menu bar does not need this: a playtest \"menus\" step reads it."
  echo "    Fix once in System Settings > Privacy & Security > Accessibility: tick \"$TERM_APP\"."
fi
