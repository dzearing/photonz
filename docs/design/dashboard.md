# Design dashboard, task queue & go loop

The design site at http://127.0.0.1:8791 (served by `docs/design/mocks/dev-server.mjs`)
is now the **Photonz design dashboard**: the hub for the design system, component
library, information architecture pages, and, first in the rail, the live
**Project** section that fronts an unmanned build loop. Goal: the user returns
each day to real progress toward the streamlined creation/editing vision, with
every judgment call that came up waiting as a one-click decision.

## The pieces

| Piece | Where | What it does |
| --- | --- | --- |
| Queue | `queue/` (repo root) | File-based task queue: tasks by priority folder, decisions, digests, history.jsonl, status.json. See `queue/README.md`. |
| Go loop | `queue/bin/go-loop.sh` | Daily digest + triage pass, a manager pass whenever the queue runs low (`queue/bin/manager-prompt.md`: assess the app against the objectives, file the next batch of tasks, reports under `queue/manager/`), then one task at a time, each dispatched to a fresh headless agent under `queue/bin/runner-prompt.md`. Keeps status, Ghoztty banner, and activity state current. |
| API | `dev-server.mjs` `/api/*` | `GET /api/state` (aggregate for the dashboard; `?tasks=1` adds the task list, which only the Tasks tab draws), `GET /api/task/<id>` (one task's whole record, for the detail dialog), `GET /api/task-search?q=` (matching task ids, searched over the fields the poll does not carry), `POST /api/decide`, `POST /api/task`, `POST /api/task/update`. Implementation shared with the CLI via `queue/bin/queue-lib.mjs`. |
| Dashboard | `docs/design/mocks/pages/dashboard.html` | Live page, default route of the site. Tabs: Summary (loop hero, decision option cards with pros/cons/mitigation and per-card Select, up next, done in 24h), Objectives (the commanding hub: drag-to-reorder/nest epic tree plus a Retriage button), Tasks (sortable/filterable details table with inline seq and priority editing), Ready to try (the finished features as cards, newest first, grouped by the pillar epic they serve; a card carries the feature name, the one sentence saying what you can now do, the day it landed from its file name and its step count, and opens in place to reveal the report, one at a time; search and an area picker reach the rest, and any line still files a task), Data (stat tiles + charts from history), Digest (rendered daily digests). Polls `/api/state` every 4s; the Ready to try list comes from `/api/audit-index` instead, fetched once and again only when the report count moves. The poll carries LIST rows, never whole tasks: a row is the title, status, priority, seq, its dates and the last line of its log (`taskRow` in queue-lib). The task list rides along only while you are on the Tasks tab (`?tasks=1`), the detail dialog fetches the task it opened from `/api/task/<id>`, and search runs server-side over the goal, working detail, checklist and log. That took the poll from 3.2MB to 62KB on every tab but Tasks and 279KB on Tasks. `queue/bin/state-poll-drill.mjs` holds it there. |
| /go skill | `.claude/skills/go/SKILL.md` | One command after a reboot: dev server up, loop spawned in a Ghoztty window titled "photonz: go-loop", dashboard split into the current window. |

## Design decisions

- **Files over a database.** The queue survives reboots, diffs in git, and any
  writer (loop, runner, server, human) can operate on it. The dashboard is a
  view over files, so a wedged UI can never lose work.
- **The queue lives outside `docs/design/mocks/`** so status writes do not trip
  the dev server's livereload watcher; the dashboard polls instead.
- **Decisions are the escalation path.** Runners never guess on product/UX
  ambiguity; they file a decision (2 to 4 options, one recommended), block the
  task, and move on. Resolving on the dashboard requeues the task with the
  answer in its log. The Summary tab is the default route so blocked-on-you is
  the first thing visible.
- **An answer of no stays no.** The option that means do not build this carries
  `"declines": true`. Its card reads *Stops this work* and its button reads
  *Select and stop*, and choosing it retires the task as `dropped` with the
  answer in the task history, instead of handing it back to the loop. Before
  this, every answer requeued its task, so on 2026-09-02 a feature the user had
  turned down at 15:10 was claimed and started by a runner at 19:45. A decline is
  only for an option that ends the whole task: "no button, copy as text instead"
  is still a yes to the task and does not carry the marker.
- **An answer is never lost to a slow runner.** Answering a card while its task
  is still being worked on used to be overwritten seconds later by the runner's
  own `blocked` write, leaving a task with no open question and nothing that
  could ever hand it back (2026-09-02, the tool bar card: answered 15:24:11,
  re-blocked 15:24:36). Blocking now only holds while a question is actually
  open; if every question is already answered, the block resolves into the
  answer instead, and the guard pass the loop runs after every task sweeps up
  anything already stranded. See `queue/README.md`.
- **Next release only.** Runners work in the Next release unless a task
  explicitly says current (see `docs/design/experiments.md`); the porting rule
  from CLAUDE.md still applies to shared-file changes.
- **Chart colors are validated.** The created/completed pair (#4c6fff, #b7791f)
  passes CVD-separation and contrast checks on both light and dark surfaces;
  priority bars use one hue since the row label carries identity; status colors
  are semantic and always paired with label + count.

## Daily rhythm (unmanned)

1. First loop pass of a calendar day: triage (dedupe, reprioritize, groom,
   repair) then write `queue/digests/YYYY-MM-DD.md` with Summary / Reflections /
   Triage review, and commit.
2. Then tasks, highest priority first, one at a time, each with fresh context.
   Statuses and history events flow to the dashboard as they happen.
3. The user resolves decisions on the dashboard whenever convenient; the loop
   picks unblocked work up automatically.

## When runners fail

A loop that cannot run anything must never read as Running. Every runner exit is
classified: leaving its task `in_progress` is a failure, recorded with the exit
code and the runner's own last error line. The loop then waits longer after each
consecutive failure (30s → 30m), reports `unhealthy` in `status.json`, and the
Summary hero swaps its Running pill for a red **Loop unhealthy** pill above a
strip carrying the failure count, the raw error, and what it means. A task that
fails three times in a row on its own is parked and the loop moves on; failures
that span several tasks are read as an environment problem instead, so nothing
gets parked and anything parked in that streak is handed back. An expired login
is its own case: the CLI reports it as a success with exit 0, so the loop reads
the runner's words instead, charges nothing to the task, leaves the daily
digest unwritten so it is retried, and the hero pill says **Sign-in needed**
with the fix (run `claude` in a terminal and log in). A spend-limit refusal is
read the same way: the CLI reports it as a success too, so a digest run that
says it is deferred rather than stubbed, the loop reports `unhealthy` at once,
and the hero pill says **Spend limit hit** with when it resets. On a task run
the limit can land mid-work, so there the usual per-task rule stays in charge.
Details and the drill that verifies it: `queue/README.md`.

## When the loop is behind its own script

zsh parses a script once, so every fix landed in `queue/bin/go-loop.sh` is
invisible to the process already running it. That was silent for four days: the
loop ran unbroken from 5 September, the walk sweep landed in the loop on the
8th, and by the 9th seven runners had asked for a sweep the running loop had no
code to serve.

Two halves fix it. The loop hashes its own file at startup, records that in
`status.json`, and between tasks (nothing claimed, nothing in flight) compares
it against the file on disk. When it differs and `zsh -n` parses it, the loop
`exec`s itself onto the new copy: same pid, same queue, same window, and the
pass count rides across in the environment so `PHOTONZ_MAX_ITERS` still ends a
drill. A copy that does not parse is refused out loud and the loop keeps working
on the one it has. Turn the whole thing off with `PHOTONZ_LOOP_RELOAD=0`.

The other half is the page saying so, for the window the reload cannot cover:
the long minutes inside a task, a refused copy, and a loop old enough to predate
the mechanism. `loopScript()` hashes the file at read time, so the answer is
never itself stale, and the Summary hero carries an amber strip naming the
situation and the fix. A live loop that has never recorded a script is read as
stale on its own: only a loop from before 2026-09-09 can be silent about it.

The dashboard server had the same trap, since node caches an imported module
forever and it had been up a day. It now re-imports `queue-lib.mjs` whenever the
file changes, so the page is never behind the queue.

The sweep is on the hero too, under the heartbeat: the last run's pass count and
age, or how many runs have been asked for and never served. It runs between
tasks and nothing else on the page would ever have mentioned it.
