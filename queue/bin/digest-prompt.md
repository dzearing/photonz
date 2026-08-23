# Photonz daily digest + triage pass

You are the daily digest and triage iteration of the Photonz go loop. Produce today's digest file and keep the queue healthy. Work only inside `queue/` plus read-only looks at git history and the repo. Keep all copy plain and human; no em dashes; never mention a vendor name.

## 1. Triage pass (do this first, so the digest can report it)

Read `queue/objectives.json` first: it is the user's ordered epic tree, and it steers everything below. Epic order is priority order; nesting is sub-epics. Then read every task under `queue/tasks/` and every decision in `queue/decisions/`, and:

- Align: task priorities and sequences must reflect the objectives ordering. Work serving a higher epic outranks work serving a lower one; work serving no epic at all is a candidate to drop or park at p3.

- Dedupe: merge duplicate or overlapping tasks (keep the better-written one, fold notes in, drop the other with `node queue/bin/queue.mjs status <id> dropped "duplicate of <keeper>"`).
- Reprioritize: move tasks whose priority no longer matches reality with `node queue/bin/queue.mjs priority <id> <priority>`. Blocked-on-user tasks stay where they are; decision resolution already requeues them.
- Resequence: every task carries `seq`, the sort order within its priority (the loop claims lowest first). Decimals exist so a task can slot between two others without touching the rest. During triage, renumber each priority's OPEN tasks back to clean ascending steps of 10 (`node queue/bin/queue.mjs seq <id> <n>`), preserving relative order, and give any task missing a seq one at the end.
- Repair: any task left `in_progress` with no live runner gets reset (`node queue/bin/queue.mjs guard`). Tasks with unmet or circular deps get fixed or flagged.
- Groom for READABILITY first: every open task needs a plain-language `goal` (one or two sentences, no file or class names, written for someone who has never seen the codebase) and an `acceptance` checklist of verifiable items. Backfill both wherever they are missing or where the goal is really a jargon blob. Then rewrite vague titles/notes so any future runner can execute without archaeology. Ensure every pending task has at least one concrete acceptance item. Titles name the OUTCOME and never encode status ("blocked", "in progress", "done" in a title is a bug; status lives in the status field and the dashboard renders it).
- Record one history event summarizing the pass: `node queue/bin/queue.mjs event triage '{"summary":"<counts: merged, moved, reset, groomed>"}'`.

## 2. Design review pass (evidence, then judgment)

Before writing the digest, do a real design review of the last 24 hours. Evidence first: read the task logs of everything completed or blocked, the decisions opened and resolved, and skim `shared/UX-PATTERNS.md` and `shared/AGENTS.md` against what actually got built. Then answer four questions:

- **Is the IA sound?** Did any surface this cycle have to bend the shell/dock/navigation vocabulary (UX-PATTERNS sections 1 to 3) to get its job done? A rule that had to bend is a finding.
- **Are we missing components or guidance?** What did runners hand-roll that the design system should own? Anything built twice is an extraction candidate: queue a task for it.
- **What UX issues keep recurring?** Patterns across audits, decisions, and fixes (control misuse, spacing drift, unclear affordances, copy problems). Name the pattern and the pages it hit, not one-offs.
- **Do the documented rules need a scrub?** Where reality has moved past a rule, or a rule keeps getting violated because it is unclear, queue a scrub task for that document (AGENTS.md, UX-PATTERNS.md, docs/design/*.md) and say which rule and why.

Strong findings become queued tasks, and the review cites its evidence (page names, task ids); no vibes-only claims.

## 3. Write the digest

Create `queue/digests/<YYYY-MM-DD>.md` (today's date) with exactly these four sections:

```
# Daily digest <YYYY-MM-DD>

## Summary
What happened in the last 24 hours: tasks completed (with one line each on what shipped), tasks started or blocked, decisions opened and resolved, notable commits (check `git log --since="24 hours ago" --oneline`). Lead with the single most important development. If nothing happened, say so plainly and why (loop stopped, everything blocked, etc).

## Reflections
Forward-looking and honest: feature ideas worth queueing, ways to improve this process (loop, queue, dashboard), and ways to improve the Photonz app itself. When an idea is strong, actually queue it (`queue.mjs add`) and reference the task id here.

## Design review
The findings from the design review pass, with evidence: IA soundness (what bent, if anything), missing components or guidance (what got hand-rolled, what was queued for extraction), recurring UX issues (the pattern and where it hit), and rule scrubs queued (which document, which rule, why). If the day was genuinely clean, say so and name what was checked.

## Triage review
What the triage pass changed and why: merges, priority moves, resets, grooming. Include the before/after open-task counts per priority.
```

## 4. Finish

- `node queue/bin/queue.mjs event digest '{"file":"<YYYY-MM-DD>.md"}'`
- Commit the digest and any triaged task files to main with message `queue: daily digest + triage <date>`, then push: `git pull --rebase --autostash origin main && git push origin main` (on rebase conflict: abort, leave the commit local, note it in the digest).
