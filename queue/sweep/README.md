# queue/sweep

The full walk sweep runs every scripted walk in `Scripts/playtest`:
about 560 walks and about 105 minutes,
counted by `queue/bin/sweep-size.mjs` rather than written down here. This folder
is where the go loop hands that run back and forth with the task runners.

Nothing in here except this file is tracked by git: it is runtime state.

## The schedule: asking is not starting

Runners ask for a sweep after essentially every task, and until 2026-09-21
every ask started a whole-set run. The loop did thirteen of them in twenty four
hours and spent 58 per cent of its wall clock re-running walks against 41 per
cent building anything (`queue/bin/loop-day.mjs --hours 24`, measured
2026-09-21). The gate was there; the only question it asked was whether anybody
had asked.

Now `queue/bin/sweep-schedule.mjs` decides, and it is the one copy of these
rules:

* the **full set** runs at most once every twelve hours, and only when code has
  landed since the last one. Requests pile up and the next run serves them all;
* in between, after any task that lands code, a **rotating check** of about ten
  minutes: every walk whose script changed since the last check, then the next
  chunk of the set, carrying on from `rotation.json`. Over a day the rotation
  covers the whole set anyway, in pieces;
* a rotating check is **not a sweep**. It never clears a request, never closes
  the standing walk task, and says so in its own output. A walk it finds broken
  is written onto the standing walk task the same day;
* a change every walk touches can jump the floor:
  `queue/bin/sweep.sh request --now "<why>"`.

```
queue/bin/sweep.sh schedule     the rules, printed out of the code that runs them
queue/bin/sweep.sh status       what the last run found, and why nothing is running now
queue/bin/loop-day.mjs          where the loop's wall clock actually went
```

Drills: `node queue/bin/sweep-schedule-drill.mjs`, `node queue/bin/loop-day-drill.mjs`.

| File | Written by | What it is |
| --- | --- | --- |
| `requested.json` | a task runner, via `queue/bin/sweep.sh request` | who asked for a sweep and why. Several asks before the next sweep collapse into the one run that serves them all. Asking does not start one: see the schedule above. |
| `rotation.json` | the loop, via `queue/bin/sweep.sh slice` | where the rotating check has got to in the set, and the commit it last checked. |
| `last-slice.json` | the same | what the last rotating check ran and found. Never the state of the walk set. |
| `latest.json` | the loop, via `queue/bin/sweep.sh run` | the last sweep: how long it took, how many walks passed, and the name of every walk that failed. Only runs that could SEE land here: a run that went blind does not, so this stays the last run that really covered the set. **It only ever moves forward**, see below. |
| `blind.json` | the same | the last run that WENT BLIND, if there was one: where the app stopped launching, how many walks that cost, and what it did answer before it. `sweep.sh status` leads with it while it is newer than `latest.json`. |
| `<date>-<time>.log` | the same run | the full output, one line per walk. The last ten are kept. |
| `.claimed.json` | `sweep.sh run`, at the moment it starts | the requests this run is serving, plus who is running it, when it began, which log it is writing and how big the set is. Deleted when the run is written down. One left behind means a run that never finished. |
| `.awake.pid` | `playtest-all.sh` | the caffeinate holding the Mac awake for the length of the run, so a run that is killed does not leave the hold behind. |

## A sweep that goes blind says so

On the night of 2026-09-21 the probe stopped launching 117 walks into a sweep.
The run carried on to the end of the set anyway, and each of the remaining 436
walks came back in 0s with `no done.json`, so the sweep wrote down 438 failing
walks out of 553. That record replaced one that had passed 537 of 544 the same
morning, and for the next day `sweep.sh status` told every runner the app was
broken in 438 ways. Four of the names were run on their own and passed in about
20 seconds each.

A walk that nothing ran is UNANSWERED. It is not a pass and it is not a failure,
and it is now treated like one:

* `Scripts/playtest.sh` exits **5** when the probe will not launch, and says so
  in words instead of leaving `playtest-all.sh` to guess from an empty folder;
* `Scripts/playtest-all.sh` counts those apart, and after five in a row it
  **stops the run** rather than marching the rest of the set past an app that
  is not there;
* `queue/bin/sweep-parse.mjs` reads a run of five or more the same way in any
  log, old wording included, and takes those walks out of the failing list and
  out of the counts. One on its own is still a flake and still a failure;
* the run is written to `blind.json`, never over `latest.json`, so the last run
  that really covered the set stays the record and the twelve-hour floor is
  still counted from a run that could see. The request that asked for the sweep
  is handed back.

Drill: `node queue/bin/sweep-blind-drill.mjs`.

## A sweep that is cut short still counts

A run can end five ways, and only the first is the state of the walk set:
it covered the set, a locked screen let only part of it through, the app
stopped launching and it went blind, it hit its own clock cap, or it was
INTERRUPTED because whoever was running it went away.

The last one used to lose everything twice over. The requests are claimed at
the START of a run (one arriving during a sweep belongs to the next one) and
everything else was written down only at the END, so on 2026-09-18 the loop was
killed 126 walks into a sweep and came back the next day with `requested.json`
gone, `latest.json` still naming the sweep before it, and `sweep.sh status`
saying, truthfully, that no sweep was pending. The commit that had landed that
morning was never checked and nothing was going to check it.

Now:

* a signal to `sweep.sh` no longer kills it. It stops the run, writes down what
  it reached, hands the requests back and exits 4;
* a SIGKILL gets no such chance, so `queue/bin/sweep-recover.mjs` runs at the
  top of every `sweep.sh` verb and picks up a claim nobody is running any more:
  it records what the dead run reached, puts its requests back, and puts down
  the run itself if it is still going orphaned (a SIGKILL to `sweep.sh` does
  not touch `playtest-all.sh`, which would otherwise carry on for the rest of
  the set holding the Mac awake);
* a cut-short run is never allowed to read as the set. It says how much of the
  set it covered, everywhere it is shown, and its failures are recorded as
  UNCONFIRMED: a stop takes the probe app down with it, so a walk failing in
  the last moments may be a casualty of the stop. On 2026-09-18 the killed
  run's one failure, `measure-chip-snap-walk`, passed on its own the next day;
* a run that answered nothing at all records nothing, so a probe that cannot
  launch does not write a row of zeroes over the last real sweep;
* and the standing walk task is never closed by a run that did not cover the
  set.

Drill: `node queue/bin/sweep-interrupt-drill.mjs`. Proving it against the real
thing takes a minute rather than an hour, because the run can be narrowed:

```
PHOTONZ_QUEUE_DIR=/tmp/swq PHOTONZ_SWEEP_ARGS="--no-build caliper" \
  queue/bin/sweep.sh run          # then kill it part way, either signal
```

## Why a runner never runs the sweep itself

A task runner's background work is terminated at 600s. The sweep is
eleven times the 600s ceiling, so a runner that starts one is killed waiting
for it and its task is handed back unfinished. Eight of the twenty recorded runner failures are this,
including 2026-09-07 16:22 ("The full walk sweep is still running (it re-runs
all 253 walks)") and 2026-09-08 00:03 ("Background tasks still running after
600s; terminating"). Every one of those tasks was finished later by another
runner, so the sweep cost cycles of the focus rather than work.

Detaching the sweep so it outlives the runner would be worse: `playtest-all.sh`
quits and rebuilds the probe app, so a sweep running beside the next task would
make both of them flaky.

So the loop owns it. A runner asks and moves on:

```
queue/bin/sweep.sh request "<why you want the whole set>"   # instant
queue/bin/sweep.sh status                                   # what the last one found
```

and the loop runs it between tasks, in its own shell, where there is no
ceiling to hit and no task in flight. Any walk that fails comes back as the
standing task "Walks that fail in the full sweep", updated in place each sweep
rather than filed again. That task is found by the `standing: "walk-sweep"`
mark it carries, not by its title, so triage renaming it does not make the next
sweep file a second one beside it.

While you are building, run only the walks you touched. Each is about ten
seconds:

```
Scripts/playtest.sh Scripts/playtest/<name>.json --no-build
Scripts/playtest-all.sh --no-build <name-fragment>
```


## `latest.json` only ever moves forward

Nothing older than the run already recorded is written over it, whoever is
writing and for whatever reason. Two different things read this one file, and
that is why the rule lives inside `queue/bin/sweep-record.mjs` rather than at
each caller:

* the dashboard and `sweep.sh status` read it for **what the walk set last
  said**;
* `queue/bin/sweep-schedule.mjs` counts its twelve hour floor from `began`,
  which is **when the loop last spent two hours on the whole set**.

Move the record back to fix the first and you silently reset the second. On
2026-09-22 a runner repairing a poisoned record replayed the whole-set run of
2026-09-21T06:47Z through `recordSweep()` by hand. It was right about the walks
and it moved `began` back nineteen hours, so seven seconds after that task
ended the loop started a full sweep (`queue/loop.log`, 01:30:55 local) twenty
two minutes after a rotating check had correctly printed "6.4h since the last
whole-set run". That sweep then went blind, which bought a third one at 10:12Z:
one backwards write cost about 3.3 hours of a day the schedule had just been
built to protect.

A genuine repair that must move the record back deletes `latest.json` first,
which says out loud that the floor is being reset too. `sweep-record.mjs` says
so itself when it refuses one.

The loop's log now prints the reason beside every full sweep it starts
(`walk sweep due (20.5h since the last whole-set run)`), so a sweep that fires
on a floor that has been reset no longer reads the same as one that fires on a
full twelve hours.
