# Photonz daily digest + triage pass

You are the daily digest and triage iteration of the Photonz go loop. Produce today's digest file and keep the queue healthy. Work only inside `queue/` plus read-only looks at git history and the repo. Keep all copy plain and human; no em dashes; never mention a vendor name.

## 1. Triage pass (do this first, so the digest can report it)

Read `queue/objectives.json` first: it is the user's ordered epic tree, and it steers everything below. Epic order is priority order; nesting is sub-epics. Then read every task under `queue/tasks/` and every decision in `queue/decisions/`, and:

- Align: task priorities and sequences must reflect the objectives ordering. Work serving a higher epic outranks work serving a lower one; work serving no epic at all is a candidate to drop or park at p3.

- Dedupe: merge duplicate or overlapping tasks (keep the better-written one, fold notes in, drop the other with `node queue/bin/queue.mjs status <id> dropped "duplicate of <keeper>"`).
- Reprioritize: move tasks whose priority no longer matches reality with `node queue/bin/queue.mjs priority <id> <priority>`. Blocked-on-user tasks stay where they are; decision resolution already requeues them.
- Resequence: every task carries `seq`, the sort order within its priority (the loop claims lowest first). Decimals exist so a task can slot between two others without touching the rest. During triage, renumber each priority's OPEN tasks back to clean ascending steps of 10 (`node queue/bin/queue.mjs seq <id> <n>`), preserving relative order, and give any task missing a seq one at the end.
- Repair: any task left `in_progress` with no live runner gets reset (`node queue/bin/queue.mjs guard`). Tasks with unmet or circular deps get fixed or flagged.
- Groom: rewrite vague titles/notes so any future runner can execute without archaeology. Ensure every pending task has at least one concrete acceptance item.
- Record one history event summarizing the pass: `node queue/bin/queue.mjs event triage '{"summary":"<counts: merged, moved, reset, groomed>"}'`.

## 2. Write the digest

Create `queue/digests/<YYYY-MM-DD>.md` (today's date) with exactly these three sections:

```
# Daily digest <YYYY-MM-DD>

## Summary
What happened in the last 24 hours: tasks completed (with one line each on what shipped), tasks started or blocked, decisions opened and resolved, notable commits (check `git log --since="24 hours ago" --oneline`). Lead with the single most important development. If nothing happened, say so plainly and why (loop stopped, everything blocked, etc).

## Reflections
Forward-looking and honest: feature ideas worth queueing, ways to improve this process (loop, queue, dashboard), and ways to improve the Photonz app itself. When an idea is strong, actually queue it (`queue.mjs add`) and reference the task id here.

## Triage review
What the triage pass changed and why: merges, priority moves, resets, grooming. Include the before/after open-task counts per priority.
```

## 3. Finish

- `node queue/bin/queue.mjs event digest '{"file":"<YYYY-MM-DD>.md"}'`
- Commit the digest and any triaged task files to main with message `queue: daily digest + triage <date>`. Do not push.
