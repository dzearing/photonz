# queue/sweep

The full walk sweep runs every scripted walk in `Scripts/playtest`:
about 530 walks and about 100 minutes,
counted by `queue/bin/sweep-size.mjs` rather than written down here. This folder
is where the go loop hands that run back and forth with the task runners.

Nothing in here except this file is tracked by git: it is runtime state.

| File | Written by | What it is |
| --- | --- | --- |
| `requested.json` | a task runner, via `queue/bin/sweep.sh request` | who asked for a sweep and why. Several asks before the next sweep collapse into the one run that serves them all. |
| `latest.json` | the loop, via `queue/bin/sweep.sh run` | the last sweep: how long it took, how many walks passed, and the name of every walk that failed. |
| `<date>-<time>.log` | the same run | the full output, one line per walk. The last ten are kept. |
| `.claimed.json` | `sweep.sh run`, at the moment it starts | the requests this run is serving, plus who is running it, when it began, which log it is writing and how big the set is. Deleted when the run is written down. One left behind means a run that never finished. |
| `.awake.pid` | `playtest-all.sh` | the caffeinate holding the Mac awake for the length of the run, so a run that is killed does not leave the hold behind. |

## A sweep that is cut short still counts

A run can end four ways, and only the first is the state of the walk set:
it covered the set, a locked screen let only part of it through, it hit its own
clock cap, or it was INTERRUPTED because whoever was running it went away.

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
ten times the 600s ceiling, so a runner that starts one is killed waiting
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
