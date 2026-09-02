#!/bin/zsh
# Rebuild "dist/Photonz Dev.app" and put it back exactly as it was found:
# running if it was running, quit if it was not. The go loop calls this after a
# task pushes app code, so the user is never a build behind what the loop has
# landed. Run it by hand any time with: queue/bin/refresh-dev-app.sh
#
# Why this is safe now, when the playtest lock says it is not: the dev cert is
# stable and self-signed, so a rebuilt binary keeps its Screen Recording grant.
# The only remaining cost is that the app quits and comes back, which is what
# the user asked for (2026-09-02) rather than staying on a stale build.
#
# Env:
#   PHOTONZ_AUTO_REFRESH=0   turn the loop's automatic refresh off entirely.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
APP="dist/Photonz Dev.app"
BUNDLE_ID="com.dzearing.photonz.dev"
BIN="$APP/Contents/MacOS/Photonz Dev"

was_running() { pgrep -f "$BIN" >/dev/null 2>&1 }

quit_app() {
  local pid
  pid=$(pgrep -f "$BIN" | head -1) || return 0
  [[ -z "$pid" ]] && return 0
  # Ask first so the app can put its windows away; a modal sheet can swallow
  # the Apple event, so never wait on osascript, just give it a moment.
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 &
  local waited=0
  while (( waited < 6 )) && pgrep -f "$BIN" >/dev/null 2>&1; do sleep 1; waited=$((waited + 1)); done
  pgrep -f "$BIN" >/dev/null 2>&1 && kill "$pid" 2>/dev/null
  sleep 1
  return 0
}

RUNNING=0; was_running && RUNNING=1
quit_app
if ! PHOTONZ_ALLOW_DEV_BUILD=1 Scripts/build-app.sh; then
  echo "[refresh-dev-app] build failed; leaving the app alone" >&2
  (( RUNNING )) && open "$APP"
  exit 1
fi
(( RUNNING )) && { open "$APP"; sleep 2 }
echo "[refresh-dev-app] $APP rebuilt$( ((RUNNING)) && echo " and relaunched" || echo "; it was not running, so it stays closed")"
