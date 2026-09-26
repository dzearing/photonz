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
#   PHOTONZ_PLAYTEST_TIMEOUT=300 Scripts/playtest.sh ...   (default 180s, or the
#                                  walk's own top-level "clock" when it has one)
#
# Exits 0 when done.json says "ok", 1 when the walk failed or ran out of time,
# 3 when the screen was locked and the walk could not run at all, 4 when THE
# APP DIED part way through, 5 when THE APP WOULD NOT START at all, and 6 when
# it was DEFERRED because somebody was using the Mac (queue/bin/person-at-mac.sh). Those
# last two print what really happened rather than "no done.json", which is what
# a merely slow walk says: a crash and an app that never came up are both news
# about the app, and neither is news about the walk.
# Prints the output folder and the log's last lines either way.
# Never touches "dist/Photonz Dev.app".
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
# The run empties this folder itself the moment the harness starts, so the
# pictures in it are the ones it took (PlaytestOutputFolder). These two go here
# as well, because they are what THIS script waits on and reads back: an app
# that dies before the harness ever starts would otherwise leave the last run's
# verdict and log sitting here, ready to be read as this one's.
rm -f "$OUT/done.json" "$OUT/log.json"

# When the app dies, the reason is in a crash report macOS drops into
# ~/Library/Logs/DiagnosticReports a second or two later. Remember when this run
# began, so a report from last night is never read as this run's crash: macOS
# rewrites those files when it symbolicates them, and their mtime lies.
RUN_BEGAN_MS="$(node -e 'console.log(Date.now())')"

# If the probe will not launch there is no app to walk, and that has to be its
# own answer rather than a walk failing. Under `set -e` this line used to end
# the script on the spot with no verdict printed at all, so playtest-all fell
# back to its "no done.json" wording and a sweep on the night of 2026-09-21
# wrote down 436 walks as broken in 0s each on code that passed 537 of 544 that
# morning. Exit 5 says what really happened, once, in words.
set +e
Scripts/probe-app.sh --playtest "$SCRIPT_ABS" ${NO_BUILD:+"$NO_BUILD"}
LAUNCH_CODE=$?
set -e
if (( LAUNCH_CODE == 6 )); then
  echo "==> This walk was DEFERRED: somebody is using the Mac, so it never ran. Not a failure."
  echo "==> Verdict: DEFERRED  somebody is using the Mac"
  exit 6
fi
if (( LAUNCH_CODE != 0 )); then
  echo "!! THE APP WOULD NOT START (probe-app.sh exit $LAUNCH_CODE), so this walk never ran. That is not" >&2
  echo "   the walk failing and it is not the app being broken in the way the walk was about to" >&2
  echo "   check: there was no app. Why is in the output just above." >&2
  echo "==> Verdict: THE APP WOULD NOT START  probe-app.sh exit $LAUNCH_CODE"
  exit 5
fi

# Anchored on the bundle's executable path, exactly as probe-app.sh anchors it,
# so it can never match "Photonz Dev.app", "Photonz.app" or a bare `swift build`.
MATCH="Photonz Probe.app/Contents/MacOS"
PROBE_PID="$(pgrep -f "$MATCH" | head -1 || true)"
probe_alive() {
  if [[ -n "$PROBE_PID" ]]; then
    kill -0 "$PROBE_PID" 2>/dev/null
  else
    pgrep -f "$MATCH" >/dev/null 2>&1
  fi
}

# A walk that writes minutes of video says how long it needs in its own file
# ("clock": 420), so a sweep gives it that without anybody remembering to.
WALK_CLOCK="$(node -e 'try { const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).clock; if (Number.isFinite(c) && c > 0) console.log(Math.round(c)) } catch {}' "$SCRIPT_ABS")"
TIMEOUT="${PHOTONZ_PLAYTEST_TIMEOUT:-${WALK_CLOCK:-180}}"
echo "==> Waiting up to ${TIMEOUT}s for $OUT/done.json"
# Whether the app went away on us. Until 2026-09-18 nobody watched for this, so
# an app that aborted at step 12 was waited on for the full timeout and then
# reported as "no done.json", which is the same sentence a slow walk gets. Seven
# walks crashing that way cost 22 minutes of every sweep and read as nothing at
# all; the crash behind them was found by a person reading a stack trace.
DIED=0
for ((i = 0; i < TIMEOUT * 2; i++)); do
  [[ -f "$OUT/done.json" ]] && break
  # The person came back: stop driving the probe and give them their Mac.
  if (( i > 4 )) && queue/bin/person-at-mac.sh here 3; then
    Scripts/probe-app.sh --quit >/dev/null 2>&1
    echo "==> This walk was INTERRUPTED: somebody started using the Mac, so the probe was quit. Not a failure."
    echo "==> Verdict: DEFERRED  somebody started using the Mac"
    exit 6
  fi
  if ! probe_alive; then
    # It may have written done.json and exited between two polls, so look once
    # more after giving that write a moment to land.
    sleep 1
    [[ -f "$OUT/done.json" ]] || DIED=1
    break
  fi
  sleep 0.5
done

STATUS=1
if [[ -f "$OUT/done.json" ]]; then
  cat "$OUT/done.json"
  echo
  grep -q '"status" : "ok"' "$OUT/done.json" && STATUS=0
  # Exit 3 means THE WALK DID NOT RUN, which is not the same as failing. The
  # screen was locked, so no control carried a name and nothing the walk read
  # was about the app. playtest-all.sh counts these apart from failures and the
  # sweep files no bugs from them. See Sources/Photonz/Playtest/PlaytestScreenState.swift.
  if grep -q '"status" : "locked"' "$OUT/done.json"; then
    STATUS=3
    echo "!! This walk could not run: the Mac's screen is locked."
    echo "   The app is fine and keeps drawing, animating, taking clicks and being"
    echo "   photographed. What a locked screen takes away is the NAME on every control,"
    echo "   which is how a walk finds one, so steps report controls missing that are"
    echo "   plainly on screen. The error above names the step that needs a name and says"
    echo "   what forcing the walk would still photograph."
  fi
elif (( DIED )); then
  # The app is gone. Say so, and say what it died of: the words a sweep prints
  # are all the loop ever reads, and "no done.json" sent four sweeps in a row
  # past twenty-one crashes (2026-09-17 night).
  STATUS=4
  CRASH="$(node Scripts/crash-report.mjs --since "$RUN_BEGAN_MS" --wait 10 2>/dev/null || true)"
  echo "!! THE APP DIED part way through this walk. It is gone and it left no done.json," >&2
  echo "   which is not the same news as a walk that merely ran slowly." >&2
  if [[ -n "$CRASH" ]]; then
    printf '%s\n' "$CRASH" | tail -n +2
    echo "   The frames run from where it died down to what was being done; read < as \"called from\"."
    echo "==> Verdict: CRASHED  $(printf '%s' "$CRASH" | head -1)"
  else
    echo "   macOS left no crash report for it within 10s, so either something quit it or it" >&2
    echo "   went away without crashing. Look in ~/Library/Logs/DiagnosticReports." >&2
    echo "==> Verdict: CRASHED  the app quit part way through and left no crash report"
  fi
else
  # Still running, still nothing written: this one really is a walk that ran out
  # of road, and it has to stay tellable apart from a crash.
  echo "!! RAN OUT OF TIME: ${TIMEOUT}s gone, no done.json, and the app is still running." >&2
  echo "   Its log so far is below; raise the clock with PHOTONZ_PLAYTEST_TIMEOUT if the walk" >&2
  echo "   is honestly this long." >&2
  echo "==> Verdict: ran out of time after ${TIMEOUT}s, with the app still running"
fi
# What the run actually photographed. `<name>-sc.png` is the window as a person
# would see it, and it is the only picture an audit may ship; the plain
# `<name>.png` beside it is an offscreen drawing that gets some colours wrong.
# Saying this in one line is what stops an audit quietly shipping the drawing.
if [[ -f "$OUT/done.json" ]]; then
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (d.capturesSaid) console.log(`==> Window captures: ${d.capturesSaid}`);
    // A walk that ran with the screen LOCKED because nothing in it looks a
    // control up by name. Its verdict is real and its pictures are the real
    // window; they carry a label saying what a lock costs them, and that label
    // belongs under the picture wherever it is shown, which in an audit is the
    // step\x27s "shotNote".
    if (d.lockSafe) {
      console.log("==> This walk ran with the screen LOCKED, and that is fine: nothing in it looks");
      console.log("    a control up by name, so the app was drawn, driven and photographed for");
      console.log("    real. Put this line under any picture of it you ship:");
      if (d.pictureLabel) console.log("    " + d.pictureLabel);
    }
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
