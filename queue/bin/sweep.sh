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

# Whether the Mac's screen is locked right now. The login window does not stop
# the app being drawn, driven or photographed; what it takes away is the NAME on
# every control, which is how about half the walks find one
# (Sources/PhotonzCore/PlaytestLockSafety.swift).
screen_locked() {
  ioreg -n Root -d1 -a 2>/dev/null | grep -A1 CGSSessionScreenIsLocked | grep -q '<true/>'
}

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
  # While the screen is locked the loop can only ever run the part of the set a
  # lock cannot touch, and that part takes about forty minutes. Running it again
  # between every pair of tasks, on code it has already covered, would eat the
  # loop and tell nobody anything new. So a partial repeats only once new code
  # has landed, and never twice inside the floor below.
  screen_locked || exit 0
  node -e '
    const fs = require("fs");
    const [latest, head, floorMin] = process.argv.slice(1);
    let r = null;
    try { r = JSON.parse(fs.readFileSync(latest, "utf8")); } catch {}
    if (!r || !r.screenLocked) process.exit(0);            // nothing locked to hold off
    const age = (Date.now() - Date.parse(r.began || r.ended || 0)) / 60000;
    const sameCode = r.head && head && r.head === head;
    process.exit(sameCode || age < Number(floorMin) ? 1 : 0);
  ' "$LATEST" "$(git rev-parse HEAD 2>/dev/null || echo '')" "${PHOTONZ_SWEEP_PARTIAL_FLOOR_MINUTES:-60}"
  ;;

# ----------------------------------------------------------------- status ----
status)
  if [[ -s "$LATEST" ]]; then
    node -e '
      const fs = require("fs");
      import("./queue/bin/sweep-parse.mjs").then(({ sweepSentences }) => {
        const r = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        for (const line of sweepSentences(r)) console.log(line);
        if (r.failed.length) console.log(`Failing: ${r.failed.join(", ")}`);
        else if (r.complete !== false) console.log("Nothing failing.");
        else if (r.partial) console.log("Nothing failing in the part that ran.");
        if (r.log) console.log(`Full output: ${r.log}`);
      });
    ' "$LATEST"
  else
    echo "No sweep has been recorded yet. Ask for one with: queue/bin/sweep.sh request \"<why>\""
  fi
  if [[ -s "$REQ" ]]; then
    echo "A sweep is pending; the loop runs it between tasks."
    # Say why a pending sweep is not running right now, rather than letting it
    # look stuck: while the screen stays locked the loop runs the lock-safe part
    # once per commit, and holds off in between.
    if screen_locked && ! queue/bin/sweep.sh due; then
      echo "The screen is locked and the lock-safe part has already run against this commit, so the loop is holding off until new code lands or the screen is unlocked."
    fi
  fi
  exit 0
  ;;

# ---------------------------------------------------------------- summary ----
# One compact JSON line about the last sweep, for the loop's event log.
summary)
  if [[ -s "$LATEST" ]]; then
    node -e '
      const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      console.log(JSON.stringify({ walks: r.walks, passed: r.passed, failed: r.failed.length, seconds: r.seconds, complete: r.complete !== false, ...(r.screenLocked ? { screenLocked: true, couldNotRun: r.couldNotRun || 0, partial: !!r.partial, total: r.total || 0 } : {}) }));
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
  # With the screen locked only the walks that never ask for a control by name
  # can run. Say which of the two runs is happening, in the live note as well as
  # here: one of them leaves most of the set unchecked and must not read as the
  # whole sweep.
  WHAT="the full walk sweep (about 50 minutes)"
  screen_locked && WHAT="the part of the walk sweep a locked screen cannot touch (about 40 minutes)"
  Q note "running $WHAT; no task is claimed while it runs" >/dev/null 2>&1

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
    # playtest-all prints one padded line per walk, ending in "ok", "FAILED" or
    # "CRASHED" (the app died in it).
    # grep -c exits 1 on no match, so `|| echo 0` would print the count AND a
    # zero into the same substitution. Take whatever it printed and insist it
    # is a number.
    DONE_N=$(grep -c -E '^[a-z0-9-]+ +[0-9]+s  (ok|FAILED|CRASHED)' "$RUNLOG" 2>/dev/null || true)
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
  SWEEP_CODE=$?
  cat "$RUNLOG"

  took=$(( SECONDS - began_s ))

  # Exit 3 from playtest-all means the sweep DID NOT COVER THE SET: the Mac's
  # screen was locked, so every walk that looks a control up by name was refused
  # (PlaytestLockSafety). The walks that never ask for a name DO run, and their
  # answers and their pictures are real, so what comes back is a PARTIAL sweep:
  # recorded with its numbers, marked partial, and never allowed to read as the
  # state of the walk set. Until 2026-09-17 a run in this state filed nothing at
  # all, which meant three days of silence while half the set was running fine.
  #
  # The request goes back on the pile either way: a full sweep is still owed.
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
  if (( SWEEP_CODE == 3 )); then
    echo "!! The Mac's screen is locked, so this sweep covered only the part of the set a lock"
    echo "   cannot touch. What ran is real; what was refused is unknown, not passing."
    echo "   The request stays pending; the loop runs a full one once the screen is unlocked."
  fi
  # How big the set is, for "224 of 521 walks ran". A run narrowed with
  # PHOTONZ_SWEEP_ARGS covers a handful on purpose, so it reports its own size
  # rather than pretending the rest of the set was refused.
  SET_SIZE=$TOTAL_WALKS
  [[ -n "${PHOTONZ_SWEEP_ARGS:-}" ]] && SET_SIZE=0
  queue/bin/sweep-record.mjs "$RUNLOG" "$LATEST" "$CLAIMED" "$REQ" \
    "$began" "$(now)" "$took" "queue/sweep/$stamp.log" "$TIMED_OUT" "$SET_SIZE" "$HEAD_SHA"

  rm -f "$CLAIMED"

  # Keep the last ten run logs. One is ~30KB and a sweep can be asked for
  # several times a day, so unbounded they become another loop.log.
  ls -t "$SDIR"/*.log 2>/dev/null | tail -n +11 | while IFS= read -r old; do rm -f "$old"; done

  FAILCOUNT=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).failed.length)' "$LATEST")
  echo "==> Walk sweep finished in $((took / 60))m $((took % 60))s, $FAILCOUNT failing"
  # Leave the live note saying what the run found rather than what it set out to
  # do: "running the full walk sweep" sat on the dashboard long after the run
  # was over and read as a sweep still going.
  Q note "$(node -e '
    const fs = require("fs");
    import("./queue/bin/sweep-parse.mjs").then(({ sweepSentences }) => {
      console.log(sweepSentences(JSON.parse(fs.readFileSync(process.argv[1], "utf8")))[0]);
    });
  ' "$LATEST")" >/dev/null 2>&1

  # A failing sweep becomes one task, not one per sweep: if the standing task
  # is still open, the new result is appended to it instead of filing a
  # duplicate every time the sweep runs.
  if [[ "$FAILCOUNT" != 0 ]]; then
    node queue/bin/sweep-report.mjs "$LATEST"
  fi

  # Exit 3 still means the set was not covered, for anything that reads it.
  (( SWEEP_CODE == 3 )) && exit 3
  ;;

*)
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac
