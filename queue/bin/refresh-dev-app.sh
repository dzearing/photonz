#!/bin/zsh
# Rebuild "dist/Photonz Dev.app" and put it back exactly as it was found:
# running if it was running, quit if it was not. The go loop calls this after a
# task pushes app code, so the user is never a build behind what the loop has
# landed. Run it by hand any time with: queue/bin/refresh-dev-app.sh
#
# The app stays up for the SLOW part. Compiling is minutes and touches only
# .build, so it happens while the user keeps working; only the seconds of
# assembling and signing the bundle need the app closed. Quitting first, which
# is what this script did on its first outing (2026-09-02), left the user
# staring at a missing app for the whole compile.
#
# Why rebuilding the user's app is safe at all, when the playtest lock says it
# is not: the dev cert is stable and self-signed, so a rebuilt binary keeps its
# Screen Recording grant. The only cost is the app blinking out and back.
#
# Env:
#   PHOTONZ_AUTO_REFRESH=0   turn the loop's automatic refresh off entirely.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
APP="dist/Photonz Dev.app"
BUNDLE_ID="com.dzearing.photonz.dev"
BIN="$APP/Contents/MacOS/Photonz Dev"

say() { echo "[refresh-dev-app] $*" }

quit_app() {
  local pid waited=0
  pid=$(pgrep -f "$BIN" | head -1)
  [[ -z "$pid" ]] && return 0
  # Ask first so the app can put its windows away. A modal sheet can swallow the
  # Apple event, so never wait on osascript itself, just give it a few seconds.
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 &
  while (( waited < 6 )) && pgrep -f "$BIN" >/dev/null 2>&1; do sleep 1; waited=$((waited + 1)); done
  pgrep -f "$BIN" >/dev/null 2>&1 && kill "$pid" 2>/dev/null
  sleep 1
  return 0
}

RUNNING=0; pgrep -f "$BIN" >/dev/null 2>&1 && RUNNING=1

# 1. Compile with the app still up. Same flags the dev bundle is assembled from,
#    so the assemble step below finds everything already built and does no work.
say "compiling (your app stays up for this part)"
if ! swift build -c release --arch arm64 -Xswiftc -DPHOTONZ_PLAYTEST; then
  say "compile failed; your app is untouched"
  exit 1
fi

# 2. Now the seconds-long part: close the app, swap the bundle, bring it back.
(( RUNNING )) && { say "compiled; swapping the bundle"; quit_app }
if ! PHOTONZ_ALLOW_DEV_BUILD=1 Scripts/build-app.sh; then
  say "bundling failed; putting the app back on the previous build"
  (( RUNNING )) && open "$APP"
  exit 1
fi
(( RUNNING )) && { open "$APP"; sleep 2 }
say "$APP rebuilt$( ((RUNNING)) && echo " and relaunched" || echo "; it was not running, so it stays closed")"
