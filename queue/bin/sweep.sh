#!/bin/bash
# The full walk sweep, owned by the go loop instead of by a task runner.
#
# Scripts/playtest-all.sh runs every scripted walk in Scripts/playtest:
# about 530 walks and about 100 minutes. That size is COUNTED, not remembered:
# queue/bin/sweep-size.mjs reads the walk count off disk and the seconds a walk
# costs out of the recorded sweeps in queue/history.jsonl, and CI fails if this
# comment drifts away from it. It used to be typed in, and by 2026-09-19 eleven
# files still said 322 walks and 52 minutes while the set had grown to 532 and a
# full run to an hour and three quarters.
#
# A task runner cannot wait that long: its background
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

# A sweep that was left half-done by a loop that died is picked up HERE, before
# anything reads the state, so nobody ever sees the gap. Silent when there is
# nothing to pick up, and it leaves a sweep that is genuinely still running
# completely alone (queue/bin/sweep-recover.mjs checks the pid).
queue/bin/sweep-recover.mjs --quiet

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
      console.log(JSON.stringify({ walks: r.walks, passed: r.passed, failed: r.failed.length, seconds: r.seconds, complete: r.complete !== false, total: r.total || 0, ...(r.interrupted ? { interrupted: true } : {}), ...(r.timedOut ? { timedOut: true } : {}), ...(r.screenLocked ? { screenLocked: true, couldNotRun: r.couldNotRun || 0, partial: !!r.partial } : {}) }));
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
  #
  # The claim also carries the run's IDENTITY: which process is running it,
  # when it began, which log it is writing, how big the set is. Until
  # 2026-09-19 it carried only the requests, so a run that was killed left a
  # file that said nothing about what it had been doing, and the next run
  # deleted it. queue/bin/sweep-recover.mjs reads these fields to finish the
  # job a dead run did not.
  CLAIMED="$SDIR/.claimed.json"
  began_s=$SECONDS
  began=$(now)
  TOTAL_WALKS=$(ls Scripts/playtest/*.json 2>/dev/null | wc -l | tr -d ' ')
  # How big the set is, for "224 of 532 walks ran". A run narrowed with
  # PHOTONZ_SWEEP_ARGS covers a handful on purpose, so it reports no set size
  # rather than pretending the rest of the set was refused. Decided HERE rather
  # than after the run, because the claim carries it too and a recovery reading
  # a claim that said 532 would report a narrowed run against the whole set.
  SET_SIZE=$TOTAL_WALKS
  [[ -n "${PHOTONZ_SWEEP_ARGS:-}" ]] && SET_SIZE=0
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
  node -e '
    const fs = require("fs");
    const [req, claimed, ...rest] = process.argv.slice(1);
    const [pid, began, logPath, logRel, total, head] = rest;
    let doc = { requests: [] };
    try { doc = JSON.parse(fs.readFileSync(req, "utf8")); } catch {}
    if (!Array.isArray(doc.requests)) doc.requests = [];
    fs.writeFileSync(claimed, JSON.stringify({
      requests: doc.requests, pid: Number(pid), began, logPath, logRel,
      total: Number(total) || 0, head: head || null,
    }, null, 2) + "\n");
    try { fs.unlinkSync(req); } catch {}
  ' "$REQ" "$CLAIMED" "$$" "$began" "$SDIR/$stamp.log" "queue/sweep/$stamp.log" "$SET_SIZE" "$HEAD_SHA"
  echo "==> Walk sweep started $began, logging to $RUNLOG"
  # With the screen locked only the walks that never ask for a control by name
  # can run. Say which of the two runs is happening, in the live note as well as
  # here: one of them leaves most of the set unchecked and must not read as the
  # whole sweep.
  # How long to say it will take. Worked out from this machine's own recorded
  # sweeps rather than written down here, so the note does not keep promising
  # fifty minutes for a run that now takes twice that.
  FULL_MIN=$(queue/bin/sweep-size.mjs --minutes 2>/dev/null || echo 105)
  PART_MIN=$(queue/bin/sweep-size.mjs --partial-minutes 2>/dev/null || echo 55)
  WHAT="the full walk sweep (about $FULL_MIN minutes)"
  screen_locked && WHAT="the part of the walk sweep a locked screen cannot touch (about $PART_MIN minutes)"
  Q note "running $WHAT; no task is claimed while it runs" >/dev/null 2>&1

  # PHOTONZ_SWEEP=1 is the key that unlocks the full run in playtest-all.sh;
  # without it that script refuses, which is what keeps a runner from starting
  # a sweep it cannot survive.
  # PHOTONZ_SWEEP_ARGS narrows the run to a few walks. It exists so this
  # machinery can be verified in a minute instead of an hour; a real sweep
  # leaves it empty and runs everything.
  read -r -a SWEEP_ARGS <<< "${PHOTONZ_SWEEP_ARGS:-}"
  # Where playtest-all.sh leaves the pid of the caffeinate holding the Mac
  # awake, so that a run this script KILLS does not leave the hold behind. See
  # the forced stop below.
  AWAKE_PIDFILE="$SDIR/.awake.pid"
  rm -f "$AWAKE_PIDFILE"
  export PHOTONZ_WALK_AWAKE_PIDFILE="$AWAKE_PIDFILE"
  # PHOTONZ_SWEEP=1 is the key that unlocks the full run in playtest-all.sh;
  # without it that script refuses, which is what keeps a runner from starting
  # a sweep it cannot survive.
  PHOTONZ_SWEEP=1 Scripts/playtest-all.sh ${SWEEP_ARGS[@]+"${SWEEP_ARGS[@]}"} > "$RUNLOG" 2>&1 &
  SWEEP_PID=$!
  # Write the run itself into the claim, now that it has a pid.
  #
  # A SIGKILL to this script does NOT kill playtest-all.sh: it is a background
  # job, so it is orphaned and carries on for the rest of the set, with nobody
  # watching it, nobody recording it, and the caffeinate it started holding the
  # Mac awake for as long as it runs. At a full sweep's size that is an hour and
  # three quarters of the user's machine spent on a sweep whose answer will be
  # thrown away. queue/bin/sweep-recover.mjs puts it down by these two pids,
  # never with pkill.
  node -e '
    const fs = require("fs");
    const [claimed, runPid, awake] = process.argv.slice(1);
    try {
      const doc = JSON.parse(fs.readFileSync(claimed, "utf8"));
      doc.runPid = Number(runPid); doc.awakePidFile = awake;
      fs.writeFileSync(claimed, JSON.stringify(doc, null, 2) + "\n");
    } catch {}
  ' "$CLAIMED" "$SWEEP_PID" "$AWAKE_PIDFILE"

  # Putting a running sweep down: kill the child, release the hold keeping the
  # Mac awake, and put the probe app away. Used by the clock cap below and by
  # the signal handler, because a sweep stopped by a signal leaves exactly the
  # same mess as one stopped by the clock.
  stop_the_run() {
    kill -TERM "$SWEEP_PID" 2>/dev/null
    sleep 2
    kill -KILL "$SWEEP_PID" 2>/dev/null
    # A SIGKILL leaves playtest-all.sh's EXIT trap unrun, so the caffeinate it
    # started to hold the Mac awake is orphaned and holds it for the rest of
    # its clock: three hours, at the size the cap now is. Put it down by the
    # pid it wrote down, never with pkill, which would also kill one the user
    # started. Then check it is really gone.
    if [[ -s "$AWAKE_PIDFILE" ]]; then
      AWAKE_PID=$(cat "$AWAKE_PIDFILE")
      kill "$AWAKE_PID" 2>/dev/null
      sleep 1
      if kill -0 "$AWAKE_PID" 2>/dev/null; then
        echo "!! The caffeinate holding the Mac awake (pid $AWAKE_PID) would not go. Kill it by hand."
      else
        echo "==> Released the hold keeping the Mac awake."
      fi
      rm -f "$AWAKE_PIDFILE"
    fi
    # playtest.sh leaves the probe app up when it is killed mid-walk. This is
    # the sanctioned way to put it down; never reach for pkill, which is one
    # typo away from killing the user's dev app.
    Scripts/probe-app.sh --quit >/dev/null 2>&1
  }

  # A sweep that is ASKED to stop still owes an answer.
  #
  # On 2026-09-18 the loop was killed 126 walks into a sweep. Everything about
  # that run was written down only at the end, so 126 answers and one failing
  # walk went in the bin, and the requests it had claimed went with them: the
  # loop came back a day later saying no sweep was pending and the last one was
  # against the commit before last. Nothing had checked the app and nothing was
  # going to.
  #
  # So a signal no longer kills this script. It sets a flag, the watch loop
  # below sees it within its fifteen seconds, and the run goes down the same
  # path a run stopped on the clock goes down: what it reached is recorded,
  # marked as a run that did not finish, and the requests it claimed go back on
  # the pile. A SIGKILL still gets no say, which is what
  # queue/bin/sweep-recover.mjs is for.
  INTERRUPTED=0
  on_signal() {
    INTERRUPTED=1
    echo "!! Asked to stop. Putting the sweep down and writing down what it reached (up to 15s)."
  }
  trap on_signal INT TERM HUP

  # A wall-clock cap, SIZED FROM THE SET rather than written down.
  #
  # Each walk has its own 180s timeout, so a probe build that launches but never
  # drives would leave every walk in the set timing out one after another and
  # hold the loop for a day and more. The cap is what stops that, and it has to
  # sit well above a good sweep and well below a wedged one.
  #
  # The budget is 20 seconds a walk (BUDGET_SECONDS_PER_WALK in sweep-size.mjs),
  # floored at two hours. With today's 532 walks:
  #
  #   a good full sweep   532 x 12s   = 106 minutes   (measured, see --json)
  #   this cap            532 x 20s   = 177 minutes
  #   headroom                          67 per cent
  #   a wedged probe      532 x 180s  = 26 hours, stopped 59 walks in
  #
  # 20s is 67 per cent above the usual 12s and 23 per cent above the slowest
  # real sweep ever recorded (16.3s a walk, 2026-09-18 03:26), so a busy machine
  # does not trip it.
  #
  # It used to be a flat two hours, set when a sweep was 52 minutes. By
  # 2026-09-19 the set was 532 walks and a full sweep 106 minutes, so the net had
  # closed to 14 minutes of slack: the first full sweep after the screen was
  # unlocked would have been cut off part way and recorded as a run that did not
  # finish. Sizing it from the walk count means that cannot come back at 800.
  CAP_DEFAULT=$(queue/bin/sweep-size.mjs --cap-seconds 2>/dev/null || echo 10800)
  CAP=${PHOTONZ_SWEEP_MAX_SECONDS:-${PHOTONZ_SWEEP_MAX_MINUTES:+$(( PHOTONZ_SWEEP_MAX_MINUTES * 60 ))}}
  CAP=${CAP:-$CAP_DEFAULT}
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
    if (( INTERRUPTED )); then
      echo "!! Walk sweep INTERRUPTED at walk $DONE_N of $TOTAL_WALKS. What it reached is recorded below and the request that asked for it goes back on the pile."
      stop_the_run
      break
    fi
    if (( SECONDS - began_s > CAP )); then
      TIMED_OUT=1
      echo "!! Walk sweep passed its ${CAP}s cap at walk $DONE_N of $TOTAL_WALKS; stopping it."
      stop_the_run
      break
    fi
  done
  wait "$SWEEP_PID" 2>/dev/null
  SWEEP_CODE=$?
  cat "$RUNLOG"
  # A killed run's log ends mid-line, with the name of the walk that was still
  # going and no newline, so without this the next thing printed lands on the
  # end of it: "caliper-click-holds-walk Last sweep ... DID NOT FINISH".
  [[ -s "$RUNLOG" && -n "$(tail -c1 "$RUNLOG" 2>/dev/null)" ]] && echo

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
  if (( SWEEP_CODE == 3 )); then
    echo "!! The Mac's screen is locked, so this sweep covered only the part of the set a lock"
    echo "   cannot touch. What ran is real; what was refused is unknown, not passing."
    echo "   The request stays pending; the loop runs a full one once the screen is unlocked."
  fi
  queue/bin/sweep-record.mjs "$RUNLOG" "$LATEST" "$CLAIMED" "$REQ" \
    "$began" "$(now)" "$took" "queue/sweep/$stamp.log" "$TIMED_OUT" "$SET_SIZE" "$HEAD_SHA" "$INTERRUPTED"

  rm -f "$CLAIMED"
  trap - INT TERM HUP

  # Keep the last ten run logs. One is ~30KB and a sweep can be asked for
  # several times a day, so unbounded they become another loop.log.
  ls -t "$SDIR"/*.log 2>/dev/null | tail -n +11 | while IFS= read -r old; do rm -f "$old"; done

  # Did this run get written down at all? A run cut short before a single walk
  # answered records nothing, so latest.json still holds the run BEFORE it, and
  # everything below has to ask before it reads numbers out of that file. Until
  # 2026-09-19 it did not ask, so a run stopped at walk zero printed the
  # previous sweep's counts as its own and filed them onto the standing task a
  # second time.
  RECORDED=0
  [[ -s "$LATEST" ]] && [[ "$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).began||"")}catch{console.log("")}' "$LATEST")" == "$began" ]] && RECORDED=1

  if (( ! RECORDED )); then
    if (( INTERRUPTED )); then
      echo "==> Walk sweep INTERRUPTED after $((took / 60))m $((took % 60))s before a single walk answered."
    elif (( TIMED_OUT )); then
      echo "==> Walk sweep STOPPED ON THE CLOCK after $((took / 60))m $((took % 60))s at its ${CAP}s cap, before a single walk answered."
    else
      echo "==> Walk sweep ended after $((took / 60))m $((took % 60))s without a single walk answering."
    fi
    echo "    Nothing is written down: a run with no answers is not a clean sweep, and the last recorded one stays the last recorded one."
    echo "    The request that asked for it is pending again."
    (( SWEEP_CODE == 3 )) && exit 3
    (( INTERRUPTED )) && exit 4
    exit 0
  fi

  FAILCOUNT=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).failed.length)' "$LATEST")
  REACHED=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).walks)' "$LATEST")
  # "finished in 17s, 0 failing" is what a run STOPPED ON THE CLOCK printed here
  # until 2026-09-19, and it reads exactly like a clean sweep. A run that was cut
  # short has not finished and its zero is not a result, so it says which it was.
  # "of 532" only when 532 is really the set this run was against. A narrowed
  # run has no set to count itself against and says so by leaving it out.
  OF_SET=""
  (( SET_SIZE > 0 )) && OF_SET=" of $SET_SIZE"
  if (( INTERRUPTED )); then
    echo "==> Walk sweep INTERRUPTED after $((took / 60))m $((took % 60))s: it reached $REACHED$OF_SET walks, $FAILCOUNT of them failing."
    (( FAILCOUNT )) && echo "    Those failures are UNCONFIRMED: a stop takes the probe app down with it, so a walk failing in the last moments may be a casualty of the stop."
    echo "    The rest were never run: unknown, not passing. The request is pending again and the loop runs another sweep."
  elif (( TIMED_OUT )); then
    echo "==> Walk sweep STOPPED ON THE CLOCK after $((took / 60))m $((took % 60))s at its ${CAP}s cap."
    echo "    It reached $REACHED$OF_SET walks, $FAILCOUNT of them failing."
    echo "    The rest were never run: unknown, not passing."
  else
    echo "==> Walk sweep finished in $((took / 60))m $((took % 60))s, $FAILCOUNT failing"
  fi
  # Leave the live note saying what the run found rather than what it set out to
  # do: "running the full walk sweep" sat on the dashboard long after the run
  # was over and read as a sweep still going.
  Q note "$(node -e '
    const fs = require("fs");
    import("./queue/bin/sweep-parse.mjs").then(({ sweepSentences }) => {
      console.log(sweepSentences(JSON.parse(fs.readFileSync(process.argv[1], "utf8")))[0]);
    });
  ' "$LATEST")" >/dev/null 2>&1

  # Every sweep is written onto the standing task, including a clean one. A
  # failing sweep becomes one task, not one per sweep: if the standing task is
  # still open, the new result is appended to it instead of filing a duplicate
  # every time the sweep runs. A clean one refreshes the same block with its own
  # numbers, so the block can never keep naming walks the latest sweep passed,
  # and closes the task if it covered the whole set. It never files a task, and
  # it never closes one for a run that did not cover the set, so an interrupted
  # run cannot retire the standing walk task however green its part looks.
  node queue/bin/sweep-report.mjs "$LATEST"

  # Exit 3 still means the set was not covered, for anything that reads it.
  (( SWEEP_CODE == 3 )) && exit 3
  # Exit 4: the run was interrupted. Its answers are real and its request is
  # pending again, so this is not a failure of the sweep machinery.
  (( INTERRUPTED )) && exit 4
  # Said out loud because it cannot be left to fall out of the last test: an
  # arithmetic test that is false exits 1, so until 2026-09-19 every clean sweep
  # ended with a status of 1. Nothing read it, and now something does.
  exit 0
  ;;

*)
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac
