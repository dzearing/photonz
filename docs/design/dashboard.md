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
| API | `dev-server.mjs` `/api/*` | `GET /api/state` (aggregate for the dashboard), `POST /api/decide`, `POST /api/task`, `POST /api/task/update`. Implementation shared with the CLI via `queue/bin/queue-lib.mjs`. |
| Dashboard | `docs/design/mocks/pages/dashboard.html` | Live page, default route of the site. Tabs: Summary (loop hero, decision option cards with pros/cons/mitigation and per-card Select, up next, done in 24h), Objectives (the commanding hub: drag-to-reorder/nest epic tree plus a Retriage button), Tasks (sortable/filterable details table with inline seq and priority editing), Data (stat tiles + charts from history), Digest (rendered daily digests). Polls `/api/state` every 4s. |
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
with the fix (run `claude` in a terminal and log in). Details and the drill that
verifies it: `queue/README.md`.
