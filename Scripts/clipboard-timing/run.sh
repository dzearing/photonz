#!/bin/bash
# How soon a copy is on the clipboard, measured from a second process.
# Builds the watcher, the paster and the test pictures into /tmp/copy-timing
# (the walks read their pictures from there), then runs:
#   timing  every copy path; prints when the clipboard moved and the PNG could be read
#   race    120 pastes 10, 50 and 200 ms after a copy; each must get the new picture
#   stall   copies on a 12 megapixel photo; fails if any main thread pass tops 50 ms
#   paste   new screenshots landing as a capture does, pasted from a second
#           process the way a web page, Preview, Finder and Slack read them,
#           at 0 s and 1 s (COUNT captures, default 40); every paste must get it
#   twoapps the same with a second Photonz answering the shortcut too, as the
#           installed 0.21.0 did beside Photonz Dev on 2026-11-03 (second-app);
#           shows the race a single owner of the shortcuts removes
# Usage: Scripts/clipboard-timing/run.sh [timing|race|stall|paste|twoapps]   (probe must be built)
set -euo pipefail
cd "$(dirname "$0")/../.."
HERE=Scripts/clipboard-timing
T=/tmp/copy-timing
mkdir -p "$T"
for tool in watcher paster makeimages targets second-app; do
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
  paste|twoapps)
    COUNT="${COUNT:-40}"
    python3 "$HERE/capture-walk.py" "$COUNT" 1.75 "$T/capture-paste-walk.json" captureLandsAndStays
    SECOND=""
    if [[ "$1" == twoapps ]]; then "$T/second-app" $((COUNT * 4 + 30)) 50 > "$T/second.jsonl" & SECOND=$!; fi
    "$T/targets" $((COUNT * 4 + 30)) 0,1000 web,native,file,electron 3456 > "$T/paste.jsonl" &
    PASTER=$!
    sleep 0.5
    PHOTONZ_PLAYTEST_TIMEOUT=$((COUNT * 4 + 60)) Scripts/playtest.sh "$T/capture-paste-walk.json" --no-build > "$T/paste-walk.txt" || true
    kill $PASTER ${SECOND:+$SECOND} 2>/dev/null || true
    python3 "$HERE/paste-report.py" "$T/paste.jsonl" ;;
esac
