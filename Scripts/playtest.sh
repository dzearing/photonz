#!/bin/bash
# Runs a scripted playtest in the task loop's own copy of Photonz and waits for
# it to finish. The script is a JSON file of steps (open a file, press keys,
# click, drag, snapshot the window, describe the editor); the harness in the
# probe build performs them and writes renders, log.json and done.json into
# the script's `out` folder, or /tmp/photonz-playtest/<walk name> when the walk
# names none. Full reference: docs/design/playtest-harness.md.
#
#   Scripts/playtest.sh <script.json>             build, run, wait, quit
#   Scripts/playtest.sh <script.json> --no-build  reuse the built probe
#   Scripts/playtest.sh <script.json> --keep      leave the probe running after
#   PHOTONZ_PLAYTEST_TIMEOUT=300 Scripts/playtest.sh ...   (default 180s)
#
# Exits 0 when done.json says "ok", 1 otherwise; prints the output folder and
# the log's last lines either way. Never touches "dist/Photonz Dev.app".
set -euo pipefail
cd "$(dirname "$0")/.."

SCRIPT="${1:-}"
[[ -f "$SCRIPT" ]] || { echo "usage: Scripts/playtest.sh <script.json> [--no-build] [--keep]" >&2; exit 1; }
shift
NO_BUILD=""
KEEP=""
for arg in "$@"; do
  case "$arg" in
    --no-build) NO_BUILD="--no-build" ;;
    --keep) KEEP=1 ;;
    *) echo "!! unknown option $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_ABS="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
# The harness resolves `out` the same way (PlaytestScript.outputDirectory).
OUT="$(node -e '
  const path = require("path");
  // A walk too broken to parse still has to be watched somewhere, because the
  // one report it most needs to leave is the one saying why it was broken.
  // PlaytestScript.outputDirectory(besides:in:) falls back the same way.
  let s = {};
  try { s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")) || {}; } catch {}
  const dir = path.dirname(process.argv[1]);
  const name = path.basename(process.argv[1], path.extname(process.argv[1]));
  const out = s.out && s.out.length ? s.out : "/tmp/photonz-playtest/" + (name || "walk");
  console.log(path.isAbsolute(out) ? out : path.resolve(dir, out));
' "$SCRIPT_ABS")"
mkdir -p "$OUT"
rm -f "$OUT/done.json"

Scripts/probe-app.sh --playtest "$SCRIPT_ABS" ${NO_BUILD:+"$NO_BUILD"}

TIMEOUT="${PHOTONZ_PLAYTEST_TIMEOUT:-180}"
echo "==> Waiting up to ${TIMEOUT}s for $OUT/done.json"
for ((i = 0; i < TIMEOUT * 2; i++)); do
  [[ -f "$OUT/done.json" ]] && break
  sleep 0.5
done

STATUS=1
if [[ -f "$OUT/done.json" ]]; then
  cat "$OUT/done.json"
  echo
  grep -q '"status" : "ok"' "$OUT/done.json" && STATUS=0
  # Exit 3 means THE WALK DID NOT RUN, which is not the same as failing. The
  # screen was locked, so the window never got drawn and nothing the walk read
  # was about the app. playtest-all.sh counts these apart from failures and the
  # sweep files no bugs from them. See Sources/Photonz/Playtest/PlaytestScreenState.swift.
  if grep -q '"status" : "locked"' "$OUT/done.json"; then
    STATUS=3
    echo "!! This walk could not run: the Mac's screen is locked."
    echo "   A locked screen covers every window, so the app is never drawn and a walk"
    echo "   reads a half-built window. Unlock the screen and run it again."
  fi
else
  echo "!! No done.json after ${TIMEOUT}s. The probe may still be running; its log so far:" >&2
fi
# What the run actually photographed. `<name>-sc.png` is the window as a person
# would see it, and it is the only picture an audit may ship; the plain
# `<name>.png` beside it is an offscreen drawing that gets some colours wrong.
# Saying this in one line is what stops an audit quietly shipping the drawing.
if [[ -f "$OUT/done.json" ]]; then
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (d.capturesSaid) console.log(`==> Window captures: ${d.capturesSaid}`);
  ' "$OUT/done.json"
fi
if [[ -f "$OUT/log.json" ]]; then
  echo "==> Last log lines ($OUT/log.json):"
  node -e '
    const log = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    for (const e of log.slice(-6)) console.log(`  [${e.step} ${e.do}] ${String(e.note).split("\n")[0]}`);
  ' "$OUT/log.json"
fi
echo "==> Output: $OUT"
ls "$OUT"

[[ -n "$KEEP" ]] || Scripts/probe-app.sh --quit
exit $STATUS
