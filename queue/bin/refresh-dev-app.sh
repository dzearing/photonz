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
# Why this used to override the playtest lock, and why it no longer does: the
# dev cert is stable, so a rebuilt binary keeps its Screen Recording grant, and
# the cost was written off as "the app blinking out and back". That is only true
# when nobody is using it. On 2026-09-15 the user was drawing with the Pen while
# the loop quit the app out from under them every time a task landed code, which
# reads exactly like the app stealing focus: "i can't fucking type". The lock
# exists to say someone is in there. Overriding it defeated the only guard that
# protects a person from their own build loop.
#
# So the refresh now BAILS when the lock is held, and bails when the dev app is
# the frontmost app, which catches the common case of somebody working without
# having thought to take the lock. It leaves the app alone and says so; the next
# task that lands code will try again.
#
# Env:
#   PHOTONZ_AUTO_REFRESH=0   turn the loop's automatic refresh off entirely.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
APP="dist/Photonz Dev.app"
BUNDLE_ID="com.dzearing.photonz.dev"
BIN="$APP/Contents/MacOS/Photonz Dev"

say() { echo "[refresh-dev-app] $*"; }

# Someone is using the app: leave it alone. Both tests are cheap and both fail
# open, because refusing to refresh is always safer than yanking a window away
# from somebody mid-drag.
if [[ -f queue/playtest.lock ]]; then
  say "someone is using the dev app (queue/playtest.lock); leaving it alone"
  exit 0
fi
if lsappinfo front 2>/dev/null | grep -q "photonz.dev"; then
  say "the dev app is frontmost, so somebody is working in it; leaving it alone"
  exit 0
fi

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
#    Assembling tears the bundle down and rebuilds it, so a probe build racing
#    for the same dist directory can leave a file mid-flight and the copy fails
#    with a permission error (seen 2026-09-03: AppIcon.icns, Operation not
#    permitted, while another SwiftPM held .build). One retry after a breath
#    clears that, and a bundle left half built is worse than no attempt, so a
#    second failure rebuilds once more from nothing before giving up.
(( RUNNING )) && { say "compiled; swapping the bundle"; quit_app; }
bundle() { Scripts/build-app.sh; }
if ! bundle; then
  say "bundling failed, retrying once"
  sleep 4
  rm -rf "$APP"
  if ! bundle; then
    say "bundling failed twice; putting the app back on the previous build"
    (( RUNNING )) && open -g "$APP"
    exit 1
  fi
fi
# The app is only current once it is running the bundle we just wrote. Relaunch
# even when it came back on its own during a failed attempt.
if (( RUNNING )); then
  quit_app
  # -g: relaunch WITHOUT bringing it to the front. This runs between tasks
  # whenever code lands, so a plain `open` stole the user's focus every twenty
  # minutes or so and made the app unusable while they were working in it
  # (reported 2026-09-14: "i can't even use the app because you keep stealing
  # focus"). The refresh is meant to put the app back as it found it, and it was
  # not found frontmost.
  open -g "$APP"
  sleep 2
fi
say "$APP rebuilt$( ((RUNNING)) && echo " and relaunched" || echo "; it was not running, so it stays closed")"
