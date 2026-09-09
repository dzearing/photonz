# queue/sweep

The full walk sweep runs every scripted walk in `Scripts/playtest`. There are
322 of them, about 52 minutes, and this folder is where the go loop hands that
run back and forth with the task runners.

Nothing in here except this file is tracked by git: it is runtime state.

| File | Written by | What it is |
| --- | --- | --- |
| `requested.json` | a task runner, via `queue/bin/sweep.sh request` | who asked for a sweep and why. Several asks before the next sweep collapse into the one run that serves them all. |
| `latest.json` | the loop, via `queue/bin/sweep.sh run` | the last sweep: how long it took, how many walks passed, and the name of every walk that failed. |
| `<date>-<time>.log` | the same run | the full output, one line per walk. The last ten are kept. |

## Why a runner never runs the sweep itself

A task runner's background work is terminated at 600s. The sweep is five times
that, so a runner that starts one is killed waiting for it and its task is
handed back unfinished. Eight of the twenty recorded runner failures are this,
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
rather than filed again.

While you are building, run only the walks you touched. Each is about ten
seconds:

```
Scripts/playtest.sh Scripts/playtest/<name>.json --no-build
Scripts/playtest-all.sh --no-build <name-fragment>
```
