#!/bin/bash
# Times how long a recording takes to begin once Return is pressed on the
# recording card, on the probe.
#
#   Scripts/recording-start-drill.sh [runs] [--region] [--system-audio] [--with-microphone] [--cold] [--still] [--stop-early] [--cancel] [--no-build]
#
# Each run puts the app's own recording card up (without taking the keyboard),
# presses Return on it a second later, and times every step up to the stream's
# first frame, recording through the app's own path into a scratch folder that
# is deleted afterwards. Two small squares of its own sit near the top centre
# of the main display while it runs: a black one that turns white 50 ms after
# Return (the file must begin black and show the white), and a green one under
# the stop control (the file must show green where the control's dot is).
# `--region` records a region around them, timed from the moment the region is
# chosen. `--cold` skips getting the recording ready while the card is up, which
# is how every start worked before 2026-10-03. `--still` leaves the square
# black. `--stop-early` presses Stop 300 ms after Return (with sound, while
# macOS is still starting the stream) and checks the recording stops and lands.
# `--cancel` presses Escape on the card instead and checks that everything made
# ready while it was up (the stream, the unseen stop control) is gone.
# Exits 1 when the median Return-to-first-frame is over
# RecordingStartBudget, or a file missed the square turning, or the stop
# control got into a file.
#
# It needs the probe's Screen Recording grant and an unlocked screen; the menu
# bar shows the recording indicator and the stop control appears while it runs.
set -euo pipefail
cd "$(dirname "$0")/.."

RUNS=10
BUILD=1
EXTRA=()
for a in "$@"; do
  case "$a" in
    --no-build) BUILD=0 ;;
    --region|--system-audio|--with-microphone|--cold|--still|--stop-early|--cancel) EXTRA+=("$a") ;;
    *[!0-9]*|"") echo "!! unknown argument: $a" >&2; exit 2 ;;
    *) RUNS="$a" ;;
  esac
done

OUT=/tmp/photonz-recording-start-latency.json
APP="$PWD/dist/Photonz Probe.app"
[[ "$BUILD" == "1" ]] && Scripts/build-app.sh --probe >/dev/null
Scripts/probe-app.sh --quit >/dev/null
rm -f "$OUT"
open -g -n "$APP" --args --recording-start-latency-diag "$RUNS" "${EXTRA[@]+"${EXTRA[@]}"}"
LIMIT=$(( RUNS * 9 + 30 ))
for ((i = 0; i < LIMIT; i++)); do
  [[ -f "$OUT" ]] && break
  sleep 1
done
Scripts/probe-app.sh --quit >/dev/null
[[ -f "$OUT" ]] || { echo "!! The drill wrote nothing in ${LIMIT}s." >&2; exit 1; }
node -e '
const d = require(process.argv[1]);
const f = (v) => v == null ? "  -  " : String(v).padStart(5);
if (d.cancel && !d.error) {
  for (const r of d.readings) console.log(`    ready while the card was up: ${r.readyWhileCardUp}; Escape taken: ${r.escapeTaken}; card gone: ${r.cardGone}; nothing left after: ${r.nothingLeftAfterCancel}`);
  console.log(d.passed ? "==> PASS" : "!! FAIL"); process.exit(d.passed ? 0 : 1);
}
if (d.stopEarly && !d.error) {
  for (const r of d.readings) console.log(`    Stop pressed while starting: ${r.stopPressedWhileStarting}; stopped: ${r.stoppedAfterStart}; file landed: ${r.fileLanded}; ${r.seconds ?? "?"} s long`);
  console.log(d.passed ? "==> PASS" : "!! FAIL"); process.exit(d.passed ? 0 : 1);
}

console.log(`==> ${d.runs} runs, ${d.source}, sound: ${d.audio && d.audio.length ? d.audio.join(" + ") : "none"}, ${d.warm ? "made ready while the card is up" : "cold"}`);
console.log("    ms after Return:  start  stop-ctl  content  built  capture  1st-frame  timer  square  | plan     file: 1st square, turn at, clock error, ctl in video");
for (const r of d.readings || []) {
  console.log(`                     ${f(r.returnToStartCalledMS)} ${f(r.returnToControlsShownMS)}    ${f(r.returnToContentReadyMS)}  ${f(r.returnToStreamBuiltMS)}  ${f(r.returnToCaptureStartedMS)}     ${f(r.returnToFirstFrameMS)}  ${f(r.returnToTimerStartedMS)}  ${f(r.returnToSquareWhiteMS)}  | ${String(r.plan ?? "-").padEnd(8)} ${r.firstFrameSquare || r.error}, ${r.squareTurnedAtFileMS ?? "never"}, ${r.clockErrorMS ?? "-"}, ${r.controlsInVideo}${r.controlsSeenAs ? " (" + r.controlsSeenAs + ")" : ""}`);
}
if (d.error) { console.log("!! " + d.error); process.exit(1); }
console.log(`==> Return to first frame: median ${d.medianFirstFrameMS} ms, worst ${d.worstFirstFrameMS} ms, best ${d.bestFirstFrameMS} ms (budget ${d.budgetMS ?? "?"} ms)`);
console.log(`    every file began before the square turned: ${d.everyFileBeganBeforeTheSquareTurned}; every file showed it turn: ${d.everyFileShowedTheSquareTurn}; stop control kept out: ${d.controlsAlwaysOutOfTheVideo}`);
const passed = d.passed ?? false;
console.log(passed ? "==> PASS" : "!! FAIL");
process.exit(passed ? 0 : 1);
' "$OUT"
