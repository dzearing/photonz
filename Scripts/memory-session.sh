#!/bin/zsh
# The long session Photonz's memory budget is measured on
# (docs/design/memory.md): runs Scripts/memory/long-session-walk.json in the
# probe while Scripts/memory-watch.sh samples Photonz and every helper it
# starts, then draws the chart.
#
#   Scripts/memory-session.sh <out-folder> [--no-build]
#
# About twenty five minutes, and it loads Ask's models, so it is not part of
# the walk set. The quick guard that is (every rotating check runs it) is
# Scripts/playtest/closed-windows-give-their-memory-back-walk.json.
set -u
cd "$(dirname "$0")/.."
out="${1:?usage: memory-session.sh <out-folder> [--no-build]}"
shift
mkdir -p "$out"
Scripts/memory-watch.sh "$out/samples.csv" --every 10 --for 2400 &
watcher=$!
Scripts/playtest.sh Scripts/memory/long-session-walk.json "$@"
walk=$?
kill "$watcher" 2>/dev/null
wait "$watcher" 2>/dev/null
cp /tmp/photonz-playtest/memory-long-session/log.json "$out/walk-log.json" 2>/dev/null
node Scripts/memory-chart.mjs "$out/samples.csv" "$out/chart.svg" "Photonz and its helpers over the long session"
grep -o '"[^"]*MB, [0-9]* editor[^"]*' "$out/walk-log.json" 2>/dev/null | sed 's/\\"/"/g'
exit $walk
