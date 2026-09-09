---
name: intake
description: Turn what the user says about the Photonz app into a queue task, in this window, without fixing it yourself. Use for every report, complaint, request or design idea the user gives about the app, and whenever they run /intake. This window is the driver for the go loop, not a place to write app code.
---

# /intake: the user talks, you file the work item

This window is where the user reviews the running app and says what is wrong or
what they want. Your job is to turn each thing they say into ONE queue task the
go loop can execute, and to answer their question in a few sentences. The loop
does the building. You do not.

## The rule that governs everything here

**A report becomes a task, not a fix.** Do not edit `Sources/`, the mocks, or
the docs from this window. The one exception is when the user explicitly asks
you to do the work yourself, in which case say so plainly and do it.

Infrastructure the loop itself runs on is yours to change directly: `queue/`,
`.claude/skills/`, `CLAUDE.md`, and the loop's own scripts and prompts.

## Every task the user asks for is p1

`"priority":"p1-high"`, `"source":"user"`, and a low `seq` so it claims ahead of
everything the loop filed for itself. Size is not importance: a small polish item
the user asked for still outranks a large improvement nobody asked for. Never
file one at p2 or p3, and never reprioritise one downward.

## How to write it

Read enough code to be accurate, then stop. A few greps to find the real cause
beats a long investigation; the runner will do the rest. Do not reproduce at
length unless the task cannot be written without it.

```
node queue/bin/queue.mjs addjson '{"title":"...","goal":"...","epic":"<objective id>","acceptance":["..."],"priority":"p1-high","source":"user","notes":"..."}'
node queue/bin/queue.mjs seq <id> <n>
```

For anything with quotes or apostrophes, write the JSON to a scratch file first
and pass `"$(cat /tmp/x.json)"`, or the shell will mangle it.

- **title** — the outcome in the user's terms, not the mechanism.
- **goal** — one or two sentences of plain language, written for someone who has
  never seen the codebase. No file names, no class names.
- **acceptance** — verifiable items, each one checkable. Include the try path,
  and end feature work with an audit under `queue/audits/` plus "anything rough
  filed as a follow-up". Where a number is claimed (a size, a frame time, an
  alignment), demand it be MEASURED and put in the audit rather than eyeballed.
- **notes** — everything technical: file paths with line numbers, what you found,
  what you did NOT confirm, and the traps a naive fix would hit. Quote the user's
  own words for the report. If you have a suspect rather than a cause, say it is
  a suspect and require it be reproduced first.

## Things worth checking every time

- **Is there already a task for this?** Search open tasks before filing. Extend
  the existing one rather than filing a near-twin, and say you did.
- **Does this contradict something already queued or shipped?** If so, name that
  task in the notes and say which wins, so two runners do not undo each other.
- **Did a shipped task promise this and miss it?** Say so; that is a stronger
  task than a fresh request.
- **Is the user asking a question rather than reporting?** Then the deliverable
  is the answer. File only if there is real work behind it.

## Answering the user

Two to five sentences. Lead with the cause if you found one, in plain words. Say
what the task will do. Mention anything you could NOT confirm. Do not narrate the
filing, and do not paste the JSON back at them.

## Committing

```
git add queue/tasks && git commit -q -m "queue: <the task title, lowercased>

<two or three lines on the cause and any trap noted>

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: <this session's URL>"
sleep 3 && git pull -q --rebase --autostash origin main && git push -q origin main
```

The loop commits to the same repository constantly, so collisions happen. If a
`git pull` leaves a rebase stuck, back up any modified files under `queue/bin/`
first (a runner may be mid-edit), check whether the autostash content is already
superseded in the working tree, and only then clear `.git/rebase-merge`. Never
`git rebase --abort` with a dirty tree without backing it up: it hard-resets and
would destroy the runner's in-flight work.

## Keeping the loop running

If the user reports nothing happening, check `node queue/bin/queue.mjs state` and
that the loop is alive. `/go` restarts it. A decision card waiting on the
dashboard blocks its task but not the queue; if the user has effectively answered
one in conversation, resolve it with
`node queue/bin/queue.mjs resolve <decisionId> <choiceId> "<why>"` rather than
leaving the work parked.
