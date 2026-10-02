#!/bin/bash
# Times how long a stopped recording takes to show in history, on the probe.
#
#   Scripts/recording-latency-drill.sh [seconds] [--system-audio] [--with-microphone] [--no-build]
#
# Records the main display for <seconds> (default 5) through the app's own
# recording path, with the stop control left off the screen, filing into a
# scratch folder rather than anybody's history, and opens it in an editor the
# moment its tile is up. Prints every step after Stop (tile up, tile showing the
# picture, editor showing the picture, file closed by macOS, file landed,
# editor playable, duration) and exits 1 when any is over its budget
# (PhotonzCore RecordingStopBudget: tile 300 ms, thumbnail 100 ms, editor
# picture 300 ms) or the tile was not in history. The recording is deleted
# afterwards.
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
console.log(`    thumbnail shown      ${f(d.stopToThumbnailMS)}`);
console.log(`    editor shows picture ${f(d.stopToEditorPictureMS)}`);
console.log(`    file closed by macOS ${f(d.outputFinishedMS)}`);
console.log(`    file landed          ${f(d.stopToFileLandedMS)}`);
console.log(`    editor playable      ${f(d.stopToPlayableMS)}`);
console.log(`    duration             ${f(d.durationMS)}`);
if (!d.readyAtStop) console.log("    (next-a-recording-is-ready-at-stop is off: thumbnail and editor wait for the file)");
console.log(d.passed ? `==> PASS: tile inside ${d.budgetMS} ms` + (d.readyAtStop ? `, thumbnail inside ${d.thumbnailBudgetMS} ms, editor picture inside ${d.editorBudgetMS} ms` : "")
                     : `!! FAIL: a reading is over its budget (tile ${d.budgetMS} ms, thumbnail ${d.thumbnailBudgetMS} ms, editor picture ${d.editorBudgetMS} ms), or the tile was not in history`);
process.exit(d.passed ? 0 : 1);
' "$OUT"
