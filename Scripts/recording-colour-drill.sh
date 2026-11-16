#!/bin/bash
# How true a screen recording's colours and gradients are, and what each way
# of writing the file costs, on the probe.
#
#   Scripts/recording-colour-drill.sh [candidates] [--seconds N] [--out DIR] [--no-build]
#
# candidates is a comma list (default: today), from
# RecordingColourDiag.candidate(_:): today (what the app records with),
# today-hevc, h264-40, hevc-20, hevc10-20, prores422, prores422hq and more.
# A panel the size of the display sits BEHIND every app's windows while it runs
# (only that panel is captured), painted with known swatches, two slow dark
# ramps, a translucent pane with text and a strip that moves every frame. Each
# candidate records it for N seconds (default 6). result.json and crops land in
# DIR (default /tmp/photonz-recording-colour). Needs the probe's Screen
# Recording grant and an unlocked screen.
set -euo pipefail
cd "$(dirname "$0")/.."
EXTRA=()
NAMES=today SECONDS_EACH=6 OUT=/tmp/photonz-recording-colour BUILD=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) SECONDS_EACH="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --still) EXTRA+=(--still); shift ;;
    -*) echo "!! unknown argument: $1" >&2; exit 2 ;;
    *) NAMES="$1"; shift ;;
  esac
done
APP="$PWD/dist/Photonz Probe.app"
[[ "$BUILD" == "1" ]] && Scripts/build-app.sh --probe >/dev/null
Scripts/probe-app.sh --quit >/dev/null
rm -rf "$OUT"; mkdir -p "$OUT"
open -g -n "$APP" --args --recording-colour-diag "$NAMES" --seconds "$SECONDS_EACH" --out "$OUT" "${EXTRA[@]+"${EXTRA[@]}"}"
COUNT=$(tr ',' '\n' <<<"$NAMES" | wc -l)
LIMIT=$(awk -v n="$COUNT" -v s="$SECONDS_EACH" 'BEGIN { print int(n * (s + 20) + 30) }')
for ((i = 0; i < LIMIT; i++)); do
  [[ -f "$OUT/result.json" ]] && break
  sleep 1
done
Scripts/probe-app.sh --quit >/dev/null
[[ -f "$OUT/result.json" ]] || { echo "!! The drill wrote nothing in ${LIMIT}s." >&2; exit 1; }
echo "==> $OUT/result.json"
