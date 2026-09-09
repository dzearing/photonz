#!/bin/bash
# The full walk sweep, owned by the go loop instead of by a task runner.
#
# Scripts/playtest-all.sh runs every scripted walk in Scripts/playtest. There
# are 322 of them and the last measured run did 247 in 40m 21s, so a full sweep
# is now about 52 minutes. A task runner cannot wait that long: its background
# work is terminated at 600s, and eight of the twenty recorded runner failures
# are a runner that started a sweep and was killed waiting for it (2026-09-07
# 16:22 "The full walk sweep is still running (it re-runs all 253 walks)",
# 2026-09-08 00:03 "Background tasks still running after 600s; terminating",
# and six more). Every one of those tasks was finished later by another runner,
# so the sweep costs cycles rather than work, which is worse value than it
# sounds: the cycle it costs is a cycle of the focus.
#
# So a runner never runs the sweep. It ASKS for one and finishes its task:
#
#   queue/bin/sweep.sh request "<why you want the whole set>"
#   queue/bin/sweep.sh status                 what the last sweep found
#
# and the go loop runs it between tasks, in its own shell, where there is no
# background ceiling to hit and no task in flight to fight over the probe app
# (playtest-all.sh quits and rebuilds the probe bundle, so a sweep running
# beside a task would make both of them flaky):
#
#   queue/bin/sweep.sh due                    exit 0 when a sweep is pending
#   queue/bin/sweep.sh run                    run it, record it, file failures
#
# One walk is unaffected and still costs about ten seconds:
#   Scripts/playtest.sh Scripts/playtest/<name>.json --no-build
set -uo pipefail
cd "$(dirname "$0")/../.."
REPO="$PWD"
SDIR="${PHOTONZ_QUEUE_DIR:-$REPO/queue}/sweep"
REQ="$SDIR/requested.json"
LATEST="$SDIR/latest.json"
Q() { node queue/bin/queue.mjs "$@"; }
mkdir -p "$SDIR"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

case "${1:-}" in

# ---------------------------------------------------------------- request ----
# Called by a task runner. Instant: it appends a line to a file and returns.
# Several requests before the next sweep collapse into the one run that serves
# them all, and each one's reason is carried into the result.
request)
  shift
  why="${*:-unspecified}"
  node -e '
    const fs = require("fs"), [file, why, by] = process.argv.slice(1);
    let doc = { requests: [] };
    try { doc = JSON.parse(fs.readFileSync(file, "utf8")); } catch {}
    if (!Array.isArray(doc.requests)) doc.requests = [];
    doc.requests.push({ t: new Date().toISOString(), by, why });
    fs.writeFileSync(file, JSON.stringify(doc, null, 2) + "\n");
    console.log(`==> Sweep requested (${doc.requests.length} pending). The loop runs it after this task; nothing else for you to do.`);
    console.log("    Read the result later with: queue/bin/sweep.sh status");
  ' "$REQ" "$why" "$(node -e '
      // Name the asker automatically: the runner knows its task, but nothing
      // puts the id in its environment, and a request that cannot say who
      // wanted the sweep is a request nobody can judge later.
      import("./queue/bin/queue-lib.mjs").then((q) => {
        const t = q.readAllTasks().find((t) => t.status === "in_progress");
        console.log(t ? t.id : "a task runner");
      }).catch(() => console.log("a task runner"));
    ' 2>/dev/null || echo "a task runner")"
  ;;

# -------------------------------------------------------------------- due ----
# Exit 0 when there is a sweep to run. The loop tests this between tasks.
due)
  [[ -s "$REQ" ]] || exit 1
  ;;

# ----------------------------------------------------------------- status ----
status)
  if [[ -s "$LATEST" ]]; then
    node -e '
      const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      const took = r.seconds >= 60 ? `${Math.round(r.seconds / 60)}m` : `${r.seconds}s`;
      if (r.complete === false) {
        // Never let a cut-short run read as a clean bill of health: it only
        // reached part of the set, so silence about the rest means nothing.
        console.log(`Last sweep ${r.ended} DID NOT FINISH${r.timedOut ? " (stopped on the clock)" : ""}: it reached ${r.walks} walks in ${took}, of which ${r.passed} passed.`);
        console.log("The walks it never reached are unknown, not passing. Ask for another sweep if you need the whole set.");
      } else {
        console.log(`Last sweep ${r.ended}: ${r.passed}/${r.walks} walks passed in ${took}.`);
      }
      if (r.failed.length) console.log(`Failing: ${r.failed.join(", ")}`);
      else if (r.complete !== false) console.log("Nothing failing.");
      if (r.log) console.log(`Full output: ${r.log}`);
    ' "$LATEST"
  else
    echo "No sweep has been recorded yet. Ask for one with: queue/bin/sweep.sh request \"<why>\""
  fi
  [[ -s "$REQ" ]] && echo "A sweep is pending; the loop runs it between tasks."
  exit 0
  ;;

# ---------------------------------------------------------------- summary ----
# One compact JSON line about the last sweep, for the loop's event log.
summary)
  if [[ -s "$LATEST" ]]; then
    node -e '
      const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      console.log(JSON.stringify({ walks: r.walks, passed: r.passed, failed: r.failed.length, seconds: r.seconds, complete: r.complete !== false }));
    ' "$LATEST"
  else
    echo '{}'
  fi
  ;;

# -------------------------------------------------------------------- run ----
# The loop's half. Runs in the loop's own shell, so it can take an hour.
run)
  if [[ ! -s "$REQ" && "${2:-}" != "--force" ]]; then
    echo "==> No sweep requested; nothing to do."
    exit 0
  fi
  stamp="$(date +%Y-%m-%d-%H%M%S)"
  RUNLOG="$SDIR/$stamp.log"
  # Claim the request before running: a request that arrives DURING the sweep
  # belongs to the next one, not to this one.
  CLAIMED="$SDIR/.claimed.json"
  if [[ -s "$REQ" ]]; then mv -f "$REQ" "$CLAIMED"; else echo '{"requests":[]}' > "$CLAIMED"; fi

  began_s=$SECONDS
  began=$(now)
  TOTAL_WALKS=$(ls Scripts/playtest/*.json 2>/dev/null | wc -l | tr -d ' ')
  echo "==> Walk sweep started $began, logging to $RUNLOG"
  Q note "running the full walk sweep (about 50 minutes); no task is claimed while it runs" >/dev/null 2>&1

  # PHOTONZ_SWEEP=1 is the key that unlocks the full run in playtest-all.sh;
  # without it that script refuses, which is what keeps a runner from starting
  # a sweep it cannot survive.
  # PHOTONZ_SWEEP_ARGS narrows the run to a few walks. It exists so this
  # machinery can be verified in a minute instead of an hour; a real sweep
  # leaves it empty and runs everything.
  read -r -a SWEEP_ARGS <<< "${PHOTONZ_SWEEP_ARGS:-}"
  # PHOTONZ_SWEEP=1 is the key that unlocks the full run in playtest-all.sh;
  # without it that script refuses, which is what keeps a runner from starting
  # a sweep it cannot survive.
  PHOTONZ_SWEEP=1 Scripts/playtest-all.sh ${SWEEP_ARGS[@]+"${SWEEP_ARGS[@]}"} > "$RUNLOG" 2>&1 &
  SWEEP_PID=$!

  # A wall-clock cap. Each walk has its own 180s timeout, so a probe build that
  # launches but never drives would leave 322 walks timing out one after
  # another and hold the loop for sixteen hours. Two of those and a day is
  # gone. Stop at two hours (a good sweep is about 52 minutes) and record what
  # the run had reached.
  CAP=${PHOTONZ_SWEEP_MAX_SECONDS:-$(( ${PHOTONZ_SWEEP_MAX_MINUTES:-120} * 60 ))}
  TIMED_OUT=0
  LAST_REPORTED=0
  while kill -0 "$SWEEP_PID" 2>/dev/null; do
    sleep 15
    # playtest-all prints one padded line per walk, ending in "ok" or "FAILED".
    # grep -c exits 1 on no match, so `|| echo 0` would print the count AND a
    # zero into the same substitution. Take whatever it printed and insist it
    # is a number.
    DONE_N=$(grep -c -E '^[a-z0-9-]+ +[0-9]+s  (ok|FAILED)' "$RUNLOG" 2>/dev/null || true)
    [[ "$DONE_N" =~ ^[0-9]+$ ]] || DONE_N=0
    if (( DONE_N >= LAST_REPORTED + 20 )); then
      LAST_REPORTED=$DONE_N
      echo "==> walk sweep: $DONE_N of $TOTAL_WALKS walks done"
      Q note "walk sweep: $DONE_N of $TOTAL_WALKS walks done" >/dev/null 2>&1
    fi
    if (( SECONDS - began_s > CAP )); then
      TIMED_OUT=1
      echo "!! Walk sweep passed its ${CAP}s cap at walk $DONE_N of $TOTAL_WALKS; stopping it."
      kill -TERM "$SWEEP_PID" 2>/dev/null
      sleep 2
      kill -KILL "$SWEEP_PID" 2>/dev/null
      # playtest.sh leaves the probe app up when it is killed mid-walk. This is
      # the sanctioned way to put it down; never reach for pkill, which is one
      # typo away from killing the user's dev app.
      Scripts/probe-app.sh --quit >/dev/null 2>&1
      break
    fi
  done
  wait "$SWEEP_PID" 2>/dev/null
  cat "$RUNLOG"

  took=$(( SECONDS - began_s ))

  node -e '
    const fs = require("fs");
    const [logFile, latest, claimed, began, ended, took, runlogRel, timedOut] = process.argv.slice(1);
    const text = fs.readFileSync(logFile, "utf8");
    const counts = text.match(/^==> (\d+) passed, (\d+) failed$/m);
    const failed = [];
    if (counts) {
      // playtest-all lists each failing walk on its own indented line right
      // after the count line.
      const after = text.slice(text.indexOf(counts[0]) + counts[0].length).split("\n");
      for (const l of after) {
        const m = l.match(/^ {4}(\S+)$/);
        if (!m) { if (l.trim().startsWith("==>")) break; else continue; }
        failed.push(m[1]);
      }
    } else {
      // No summary line, so the run was stopped part way. Read the per-walk
      // lines it did print, because "it got to walk 58 and these two failed"
      // is worth far more than a row of zeroes.
      for (const l of text.split("\n")) {
        const m = l.match(/^([a-z0-9-]+) +\d+s  (ok|FAILED)/);
        if (m && m[2] === "FAILED") failed.push(m[1]);
      }
    }
    const reached = (text.match(/^[a-z0-9-]+ +\d+s  (ok|FAILED)/gm) || []).length;
    let requests = [];
    try { requests = (JSON.parse(fs.readFileSync(claimed, "utf8")).requests) || []; } catch {}
    const passed = counts ? Number(counts[1]) : reached - failed.length;
    const result = {
      began, ended, seconds: Number(took),
      walks: counts ? Number(counts[1]) + Number(counts[2]) : reached,
      passed, failed, requests, log: runlogRel,
      // A sweep is complete when playtest-all printed its summary line. A run
      // that was stopped on the clock did not, so nobody reads its counts as
      // the state of the walk set.
      complete: Boolean(counts) && timedOut !== "1",
      timedOut: timedOut === "1",
    };
    fs.writeFileSync(latest, JSON.stringify(result, null, 2) + "\n");
    if (!result.complete) console.log("!! The sweep did not finish cleanly; its counts are not the state of the walk set.");
  ' "$RUNLOG" "$LATEST" "$CLAIMED" "$began" "$(now)" "$took" "queue/sweep/$stamp.log" "$TIMED_OUT"
  rm -f "$CLAIMED"

  # Keep the last ten run logs. One is ~30KB and a sweep can be asked for
  # several times a day, so unbounded they become another loop.log.
  ls -t "$SDIR"/*.log 2>/dev/null | tail -n +11 | while IFS= read -r old; do rm -f "$old"; done

  FAILCOUNT=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).failed.length)' "$LATEST")
  echo "==> Walk sweep finished in $((took / 60))m $((took % 60))s, $FAILCOUNT failing"

  # A failing sweep becomes one task, not one per sweep: if the standing task
  # is still open, the new result is appended to it instead of filing a
  # duplicate every time the sweep runs.
  if [[ "$FAILCOUNT" != 0 ]]; then
    node queue/bin/sweep-report.mjs "$LATEST"
  fi
  ;;

*)
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac
