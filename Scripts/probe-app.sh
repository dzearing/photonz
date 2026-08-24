#!/bin/bash
# Builds and launches the task loop's OWN copy of Photonz, so an unmanned
# runner can look at a real running app without ever touching the one a person
# is using.
#
#   Scripts/probe-app.sh                 build, relaunch, report
#   Scripts/probe-app.sh <file> [...]    ...and open these files in it
#   Scripts/probe-app.sh --no-build      relaunch the existing probe bundle
#   Scripts/probe-app.sh --quit          quit the probe and leave
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
case "${1:-}" in
  --quit)     quit_probe; echo "==> Probe quit."; exit 0 ;;
  --no-build) BUILD=0; shift ;;
esac

if [[ "$BUILD" == "1" ]]; then
  Scripts/build-app.sh --probe
fi
[[ -d "$APP" ]] || { echo "!! $APP does not exist; run without --no-build" >&2; exit 1; }

quit_probe
if [[ $# -gt 0 ]]; then
  open -a "$PWD/$APP" "$@"
else
  open "$PWD/$APP"
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
