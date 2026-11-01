#!/bin/bash
# How soon a copy is on the clipboard, measured from a second process.
# Builds the watcher, the paster and the test pictures into /tmp/copy-timing
# (the walks read their pictures from there), then runs:
#   timing  every copy path; prints when the clipboard moved and the PNG could be read
#   race    120 pastes 10, 50 and 200 ms after a copy; each must get the new picture
#   stall   copies on a 12 megapixel photo; fails if any main thread pass tops 50 ms
# Usage: Scripts/clipboard-timing/run.sh [timing|race|stall]   (probe must be built)
set -euo pipefail
cd "$(dirname "$0")/../.."
HERE=Scripts/clipboard-timing
T=/tmp/copy-timing
mkdir -p "$T"
for tool in watcher paster makeimages; do
  [[ -x "$T/$tool" ]] || swiftc -O "$HERE/$tool.swift" -o "$T/$tool"
done
FIXTURE="$PWD/Tests/PhotonzRenderTests/Fixtures/app-window-2x.png"
[[ -f "$T/photo-12mp.png" ]] || (cd "$T" && ./makeimages "$FIXTURE")
case "${1:-timing}" in
  timing)
    "$T/watcher" 150 > "$T/timing.jsonl" &
    sleep 0.5
    Scripts/playtest.sh "$HERE/copy-timing-walk.json" --no-build > "$T/timing-walk.txt"
    pkill -f "$T/watcher" || true
    python3 "$HERE/analyze.py" /tmp/photonz-playtest/copy-timing-walk/log.json \
      /tmp/photonz-playtest/copy-timing-walk/done.json "$T/timing.jsonl" ;;
  race)
    "$T/paster" 200 10,50,200 > "$T/race.jsonl" &
    sleep 0.5
    Scripts/playtest.sh "$HERE/paste-race-walk.json" --no-build > "$T/race-walk.txt"
    pkill -f "$T/paster" || true
    python3 "$HERE/race.py" "$T/race.jsonl" ;;
  stall)
    Scripts/playtest.sh "$HERE/stall-walk.json" --no-build ;;
esac
