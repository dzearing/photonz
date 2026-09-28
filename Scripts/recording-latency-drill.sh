#!/bin/bash
# Times how long a stopped recording takes to show in history, on the probe.
#
#   Scripts/recording-latency-drill.sh [seconds] [--system-audio] [--with-microphone] [--no-build]
#
# Records the main display for <seconds> (default 5) through the app's own
# recording path, with the stop control left off the screen, filing into a
# scratch folder rather than anybody's history. Prints every step after Stop
# (tile up, file closed by macOS, file landed, poster, duration) and exits 1
# when Stop to tile is over the budget (PhotonzCore RecordingStopBudget, 300 ms)
# or the tile was not in history. The recording is deleted afterwards.
#
# It needs the probe's Screen Recording grant and an unlocked screen, and the
# menu bar shows the recording indicator while it runs.
set -euo pipefail
cd "$(dirname "$0")/.."

SECONDS_ARG=5
BUILD=1
EXTRA=()
for a in "$@"; do
  case "$a" in
    --no-build) BUILD=0 ;;
    --system-audio|--with-microphone) EXTRA+=("$a") ;;
    *[!0-9.]*|"") echo "!! unknown argument: $a" >&2; exit 2 ;;
    *) SECONDS_ARG="$a" ;;
  esac
done

OUT=/tmp/photonz-recording-latency.json
APP="$PWD/dist/Photonz Probe.app"
[[ "$BUILD" == "1" ]] && Scripts/build-app.sh --probe >/dev/null
Scripts/probe-app.sh --quit >/dev/null
rm -f "$OUT"
open -g -n "$APP" --args --recording-latency-diag "$SECONDS_ARG" "${EXTRA[@]+"${EXTRA[@]}"}"
LIMIT=$(( ${SECONDS_ARG%.*} + 60 ))
for ((i = 0; i < LIMIT; i++)); do
  [[ -f "$OUT" ]] && break
  sleep 1
done
Scripts/probe-app.sh --quit >/dev/null
[[ -f "$OUT" ]] || { echo "!! The drill wrote nothing in ${LIMIT}s." >&2; exit 1; }
node -e '
const d = require(process.argv[1]);
if (d.error) { console.log("!! " + d.error); process.exit(1); }
const f = (v) => v == null ? "never" : v + " ms";
console.log(`==> ${d.seconds} s recording, sound: ${d.audio.length ? d.audio.join(" + ") : "none"}`);
console.log(`    tile in history      ${f(d.stopToTileMS)} after Stop${d.tileInHistory ? "" : " (NOT in history)"}`);
console.log(`    file closed by macOS ${f(d.outputFinishedMS)}`);
console.log(`    file landed          ${f(d.stopToFileLandedMS)}`);
console.log(`    poster frame         ${f(d.posterMS)}`);
console.log(`    duration             ${f(d.durationMS)}`);
console.log(d.passed ? `==> PASS: inside the ${d.budgetMS} ms budget`
                     : `!! FAIL: Stop to tile is over the ${d.budgetMS} ms budget, or the tile was not in history`);
process.exit(d.passed ? 0 : 1);
' "$OUT"
