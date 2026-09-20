#!/bin/zsh
# Hold the machine while you work in the app.
#
#   queue/bin/testing.sh on    the loop stops touching your dev app
#   queue/bin/testing.sh off   it may refresh it again
#   queue/bin/testing.sh       says which it is
#
# The loop rebuilds and relaunches "dist/Photonz Dev.app" between tasks so you
# are never reviewing a stale build. That is right when you are away from it and
# maddening when you are in it: the app quits out from under you mid-drag. This
# is the switch that says you are in there.
#
# The lock is machine-local and gitignored. It used to be committed, which sent
# it to the build machine and failed every CI app build for three weeks
# (2026-08-23 to 2026-09-13), so it must never be added to git again.
set -u
cd "$(cd "$(dirname "$0")/../.." && pwd)"
LOCK="queue/playtest.lock"

case "${1:-status}" in
  on)
    cat > "$LOCK" <<LOCKTEXT
Someone is working in the dev app. Created $(date '+%Y-%m-%d %H:%M') by testing.sh.

While this file exists the loop will not rebuild, re-sign, quit or relaunch
"dist/Photonz Dev.app". Remove it with: queue/bin/testing.sh off
LOCKTEXT
    print -- "holding: the loop will leave your dev app alone"
    ;;
  off)
    rm -f "$LOCK"
    print -- "released: the loop may refresh the dev app again"
    ;;
  *)
    if [[ -f "$LOCK" ]]; then
      print -- "holding since $(stat -f '%Sm' "$LOCK")"
      # Holding is the point, so it is not a warning. What IS worth saying is
      # the price: a lock left on for two days in September 2026 left the app
      # twelve commits old and the user thought the app was broken. This is
      # silent while the app is current.
      node queue/bin/queue.mjs devapp 2>/dev/null
    else
      print -- "not holding: the loop may refresh the dev app"
    fi
    ;;
esac
