#!/bin/bash
# A file handed to Photonz AS IT STARTS opens, in one window, the way a
# double-click in Finder or a drop on the Dock icon hands it over.
#
#   Scripts/launch-open-drill.sh [--no-build]
#
# For a recording and then for a picture: quits the probe, launches it with
# the file (`open -a`, which is what Finder does), and passes when the probe's
# documents name that file and the probe has exactly one window on screen.
#
# Why: until 2026-11-22 a recording that launched the app never showed. The
# open reached the coordinator about 0.1s before the menu-bar scene had handed
# over its window opener, so it fell through to revealing the file in Finder,
# and the window SwiftUI had made to hand the file over stayed behind, empty.
# A walk cannot see this: a walk starts inside an app that is already running.
#
# It launches the probe, which comes to the front when a window opens, so like
# Scripts/probe-app.sh with a file it waits for a minute with nobody at the
# Mac, and gives up with exit 6 (DEFERRED: nothing ran, nothing is broken).
# Exit 0 passed, 1 failed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/dist/Photonz Probe.app"
SCRATCH=/tmp/photonz-launch-open-drill
BUILD=1
[[ "${1:-}" == "--no-build" ]] && BUILD=0

WAITED=0
until queue/bin/person-at-mac.sh away "${PHOTONZ_WALK_IDLE:-60}"; do
  if (( WAITED >= ${PHOTONZ_WALK_IDLE_WAIT:-240} )); then
    echo "==> Verdict: DEFERRED  somebody was using this Mac for ${WAITED}s, so the probe was not launched"
    exit 6
  fi
  sleep 10; WAITED=$((WAITED + 10))
done

if (( BUILD )); then
  Scripts/build-app.sh --probe >"$SCRATCH.build.log" 2>&1 \
    || { tail -20 "$SCRATCH.build.log"; echo "!! the probe did not build"; exit 1; }
fi
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
cp "Scripts/playtest/fixtures/Noisy voice recording 1280x800.mp4" "$SCRATCH/Launch recording.mp4"
cp "Scripts/playtest/fixtures/Busy photo 1200x800.png" "$SCRATCH/Launch picture.png"

# The probe's own windows on screen, at a size an editor window has (menu-bar
# item, toasts and the status strip are all smaller).
cat > "$SCRATCH/windows.swift" <<'EOF'
import CoreGraphics
let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = all.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Photonz (Probe)"
        && ($0[kCGWindowLayer as String] as? Int) == 0
        && ((($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double) ?? 0) > 400
}
print(mine.count)
EOF

documents() {
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"launch-open-drill","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_documents","arguments":{}}}' \
    | PHOTONZ_APP=probe Scripts/photonz-mcp.sh 2>/dev/null | grep '"id":2' || true
}

FAILED=0
check() {
  local file="$1" kind="$2" said="" windows="?" i
  Scripts/probe-app.sh --quit >/dev/null
  open -g -a "$APP" "$file"
  for ((i = 0; i < 20; i++)); do
    sleep 1
    said="$(documents)"
    [[ "$said" == *"$(basename "$file")"* && "$said" == *"\\\"kind\\\":\\\"$kind\\\""* ]] && break
    # A picture's document is Untitled until saved, so its kind is the answer.
    [[ "$kind" == picture && "$said" == *'\"kind\":\"picture\"'* ]] && break
  done
  # A beat for a window handed the file and left with nothing to close.
  sleep 2
  windows="$(swift "$SCRATCH/windows.swift" 2>/dev/null || echo "?")"
  if [[ "$said" == *"\\\"kind\\\":\\\"$kind\\\""* && "$windows" == 1 ]]; then
    echo "ok      $(basename "$file") opened as a $kind, in 1 window"
  else
    echo "FAILED  $(basename "$file"): $windows window(s) on screen; the app's documents: ${said:-no answer}"
    FAILED=1
  fi
}

check "$SCRATCH/Launch recording.mp4" video
check "$SCRATCH/Launch picture.png" picture
Scripts/probe-app.sh --quit >/dev/null
rm -rf "$SCRATCH"
if (( FAILED )); then echo "==> Verdict: FAILED"; exit 1; fi
echo "==> Verdict: ok"
