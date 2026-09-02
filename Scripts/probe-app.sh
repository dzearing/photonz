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

quit_probe() {
  if pgrep -f "$MATCH" >/dev/null 2>&1; then
    pkill -f "$MATCH" || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -f "$MATCH" >/dev/null 2>&1 || break
      sleep 0.3
    done
  fi
}

BUILD=1
PLAYTEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quit)     quit_probe; echo "==> Probe quit."; exit 0 ;;
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
# The probe rewrites this at launch; drop it first so a failed launch reports
# "unknown" rather than yesterday's answer.
rm -f "$GRANTS"
# A playtest script rides in as a launch argument (docs/design/playtest-harness.md);
# only the probe bundle acts on it.
ARGS=()
[[ -n "$PLAYTEST" ]] && ARGS=(--args --playtest "$PLAYTEST")
if [[ $# -gt 0 ]]; then
  open -a "$PWD/$APP" "$@" ${ARGS[@]+"${ARGS[@]}"}
else
  open -a "$PWD/$APP" ${ARGS[@]+"${ARGS[@]}"}
fi

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
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -f "$GRANTS" ]]; then
    SCREEN="$(node -e 'const g = require("fs").readFileSync(process.argv[1], "utf8");
      console.log(JSON.parse(g).screenRecording ? "granted" : "denied")' "$GRANTS" 2>/dev/null || echo unknown)"
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
LINE="==> Grants: probe Screen Recording $SCREEN · $TERM_APP Accessibility $AX"
if [[ "$AUTOMATION" != "unknown" ]]; then LINE="$LINE · Automation $AUTOMATION"; fi
echo "$LINE"

# Each grant buys a different thing, so say which one is missing and what it
# costs. Both survive rebuilds (the probe is signed with the stable dev
# identity), so this is asked once per machine, not once per run.
if [[ "$SCREEN" != "granted" ]]; then
  echo "    No real screenshots: the probe can only write offscreen renders, and an audit"
  echo "    must say so. Fix once in System Settings > Privacy & Security > Screen & System"
  echo "    Audio Recording: tick \"Photonz Probe\"."
fi
if [[ "$AX" != "granted" ]]; then
  echo "    No driving other apps: menu titles and keystrokes through System Events fail."
  echo "    Fix once in System Settings > Privacy & Security > Accessibility: tick \"$TERM_APP\"."
fi
