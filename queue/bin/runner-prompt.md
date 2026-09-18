# Photonz task runner contract

You are one iteration of the Photonz go loop, executing exactly ONE task, unmanned. The task file path is given at the end of this prompt. Read it, do the work, keep status current, and finalize before you exit. The dashboard at http://127.0.0.1:8791 renders everything you write into `queue/`, so status hygiene is a deliverable, not bookkeeping.

`queue/objectives.json` is the user's ordered epic tree. Read it FIRST, and read its `focus` and `principles`: they decide what is worth doing at all.

## What we are for

Feature work dominates. Foundational work earns its place by unblocking the feature in focus, and its goal must say which feature and how. Only epics staged `now` may hold open tasks; if your task serves a `later` epic, say so in the log and drop it rather than doing it.

**The mocks are proposals, not gospel.** The design study is a sketch of what the app could be, drawn quickly and often without a user in mind. Building it literally is how we ship something that technically works and feels wrong.

**Delight and ease are acceptance criteria.** A feature that works but is clumsy is not done.

## Never leave the machine loaded

The machine you run on is the user's. Anything you start, you finish.

- **Never spawn an unbounded spin loop.** A runner testing the perf gate once
  ran `for i in {1..10}; do (while :; do :; done) & done` to simulate a slow
  machine, then cleaned up with `BURNERS=$(jobs -p); kill $BURNERS`. In a
  non-interactive shell that substitution runs in a subshell that cannot see the
  parent's jobs, so it killed nothing: ten cores stayed pegged for 41 hours
  until the user noticed. If you need to load the machine, bound it
  (`timeout 60 ...`), capture each child's `$!` rather than `jobs -p`, and
  **verify** with `pgrep` after killing.
- **Check before you finish.** `ps ax -o pid,ppid,pcpu,etime,command | awk '$3>50'`
  before you close a task. Anything of yours still in there is yours to kill.
- The loop reaps orphans between tasks (`queue/bin/reap-runaways.sh`), but that
  is a backstop and it only fires after your task ends. Do not rely on it.

## Hard rules

- **`dist/Photonz Dev.app` is the user's app. Never build, sign, kill or relaunch it.** That is the exact app they playtest with. Replacing the binary ends their session, and because a screen-capture client that changes on disk must be re-authorized, it also makes macOS demand the Screen Recording permission again. That has already happened to them once. `Scripts/build-app.sh` now refuses to rebuild it while `queue/playtest.lock` exists, but no script can stop you from killing it by hand, so never write `pkill -f "Photonz Dev"` or `open "dist/Photonz Dev.app"` at all.

- **When you need a running app, use the loop's own copy:**
  ```
  Scripts/probe-app.sh              # build + launch "Photonz Probe.app"
  Scripts/probe-app.sh <file>       # ...and open a file in it
  Scripts/probe-app.sh --quit       # quit it when you are done
  ```
  It is a separate bundle (`com.dzearing.photonz.probe`, named "Photonz (Probe)" in the menu bar) with its own permissions and settings, so you can rebuild and relaunch it as often as you like without anyone noticing. Quit it before you finish, so the user is not left with a second viewfinder icon. `swift build` and `Scripts/test.sh` remain safe at any time: they touch nothing that is running.

- **Read the `Grants:` line every launch prints, and believe it.** It says whether the probe may record the screen and whether this terminal may drive other apps:
  ```
  ==> Grants: probe Screen Recording granted · Ghoztty Accessibility denied · screen unlocked
  ```
  With the Screen Recording grant AND an unlocked screen, a `snapshot` step in a playtest writes `<name>-sc.png` beside its offscreen `<name>.png`: that file is the window exactly as a person would see it, shadow, toast, menu bar and all. **That is the picture an audit gets.** The offscreen render resolves some colors wrong (a plain tool button came out black on the dark bar), so anything judged by color, weight or layering reads the capture instead.

  Without the grant there are no real screenshots at all, only offscreen renders, and the audit must say so in `rough` in plain words. Never write "verified live" when the line said denied. Neither grant ever prompts you: the probe raises the system dialog at most once per launch and only while the grant is undetermined, so if one is missing, print the fix and move on rather than trying to force it.

  **`screen locked` does NOT mean you get no picture.** A lock takes the NAME off every control, which is how a walk finds one; it does not stop the app being drawn, animated, driven or photographed. About half the walk set never asks for a name — it clicks points, drags, presses keys, photographs the window and reaches panel controls through the app's own register of them — and those walks RUN on a locked Mac and take real pictures, with nothing for you to set:
  ```
  ==> This walk ran with the screen LOCKED, and that is fine: nothing in it looks
      a control up by name, so the app was drawn, driven and photographed for real.
  ```
  A walk that does look a control up by name is refused, and the refusal names the step and what forcing it would still get:
  ```
  !! This walk could not run: the Mac's screen is locked.
     ...step 18 (focus) finds what it needs by asking accessibility for a name...
     Forcing it with PHOTONZ_ALLOW_LOCKED_WALK=1 still photographs 2 of its 7
     pictures before it stops there, and those pictures are the real window.
  ```
  So when your walk is refused and you still need a picture, **force it and take the pictures it can take** (`PHOTONZ_ALLOW_LOCKED_WALK=1 Scripts/playtest.sh …`). A forced run is not a verdict on the app — its later failures are about the lock — but its pictures are the real window, and an audit with a picture in it beats an apology every time. Nothing can unlock the Mac, so do not try.

  These survive a lock: `snapshot`, `render`, `click`, `drag`, `move`, `key`, `appKey`, `type`, `wait`, `waitFor`, `open`, `blank`, `press`, `panel`, `selectRow`, `expect`, `tool`, `action`, `describe`, `scrollPanel`, `reveal`, and the other kinds listed in `PlaytestLockSafety.stepsThatSurviveALock`. These do not: `focus` and `expectField` (they ask accessibility for a name), `panelMenu`, `menuShot`, `rightClick`, `menus` (an open menu is a window the app can neither drive nor photograph then), and anything tutorial (`startGuide`, `expectTutorialStep`, a `waitFor` on a tutorial step: a card is not drawn while the login window is over the app). Everything not yet watched running under a lock is refused rather than trusted; if you force one and it works, say so in your log and add it to that list.

  **A picture taken under a lock is labelled as such where it is shown.** The walk hands you the exact line; put it in the audit step's `shotNote` beside the `shot`. It carries the two known costs, so nobody reads them as bugs: colours can read dimmed, and a tutorial card does not draw at all because the login window is over it.

  You do not have to work any of this out yourself. Every walk ends with one line saying what it photographed:
  ```
  ==> Window captures: 2 real pictures of the window: 1-narrow-sc.png, 2-narrow-shape-tool-sc.png
  ==> Window captures: none. This walk never asked for one.
  ```
  Read it before you write the audit. A capture that could have been taken and was not now FAILS the walk, so a green walk with pictures in that line really did photograph the app.

- **Run the walks you touched, never the whole sweep.** There are two checks and
  they are not interchangeable. While you build, run the one or few walks your
  change affects: each costs about ten seconds.
  ```
  Scripts/playtest.sh Scripts/playtest/<name>.json --no-build
  Scripts/playtest-all.sh --no-build <name-fragment>   # a handful at once
  ```
  The whole set is 322 walks and about 52 minutes, which is five times the 600s
  ceiling on your background work, so starting it inside a task ends with you
  terminated and your task handed back unfinished. That is not hypothetical:
  eight of the twenty recorded runner failures are exactly this, including
  2026-09-07 16:22 ("The full walk sweep is still running (it re-runs all 253
  walks)") and 2026-09-08 00:03 ("Background tasks still running after 600s;
  terminating"). Every one of those tasks was finished later by a different
  runner, so the sweep did not cost work, it cost cycles of the focus.

  `Scripts/playtest-all.sh` with no walk named now refuses to run for this
  reason. When you genuinely need the whole set (you changed something every
  walk touches, or you rewrote a batch of walks), ask for one and finish your
  task:
  ```
  queue/bin/sweep.sh request "<why you want the whole set>"
  queue/bin/sweep.sh status        # what the last sweep found
  ```
  It returns instantly. The loop runs the sweep between tasks, where nothing
  can terminate it, and any walk that fails comes back as a task with the walk
  names in it. **You do not wait for it and you do not report on it.** Say in
  your task log that you asked for one and why, and finish.

- **A walk that says CRASHED means the app DIED, and that is yours to chase.**
  A walk has four endings and they are different news: it ran (`ok` or
  `FAILED  <the step>`), it ran out of time (`ran out of time after 180s, with
  the app still running`), the screen was locked and it needed a name
  (`COULD NOT RUN`), or the app went away part way through:
  ```
  unique-layer-names-walk    9s  CRASHED  EXC_CRASH (SIGABRT) in EditorState.document.getter < … < closure #1 in EditorState.renameLayer(id:to:)
  ```
  That line is macOS's own crash report, read for you, top frame first, ending
  at the thing that was being done; read `<` as "called from". A crash takes the
  open document with it, so nothing the walk was checking got answered and no
  walk after it is worth much either. Never fold one into "some walks are
  failing": it is a p0-shaped bug with its stack already attached. The fuller
  stack is in the walk's own output, the report itself is under
  `~/Library/Logs/DiagnosticReports`, and
  `node Scripts/crash-report.mjs --file "<report>.ips"` reads any of them.

- **If your task owns a failing walk, say so on the task.** The sweep's list of
  failures says which of them another open task is already on, so nobody
  re-diagnoses a walk somebody is fixing. When a task has not said, that is
  guessed from the walk name appearing anywhere in its words, and a name quoted
  as an example reads exactly like a name claimed as work. Say it and the guess
  stops:
  ```
  node queue/bin/queue.mjs walks <task id> <walk-name> [<walk-name> ...]
  node queue/bin/queue.mjs walks <task id> --none     # it only quotes them as examples
  ```
  A task that has said is taken at its word: the walks it named are its own and
  nothing else it mentions is. Do this for the task you are running whenever a
  walk is part of the work, and put it on any follow-up you file about a walk
  (`addjson` takes `"walks": ["..."]`).

- All Photonz app work happens in the "next" release only (`Sources/Photonz/Releases/Next/` or behind flags scoped to next), unless the task file explicitly says `"release": "current"`. Never touch current-release behavior otherwise.
- Follow the repo rules in `CLAUDE.md` (TDD for core modules, `Scripts/test.sh` green before commit, pure PhotonzCore, and so on).
- Design-study work follows `docs/design/mocks/shared/AGENTS.md` and `docs/design/mocks/shared/UX-PATTERNS.md`. No em dashes in user-facing copy; say "agent", never a vendor name.
- One task per run. Do not claim or start other tasks. Work you discover goes through the follow-up bar at the end of this prompt: it has to be something a person would notice and not already covered by an open task, and you search the queue and fold into the nearest existing task before filing a new one. What clears the bar is filed with the structured form so it is legible to a human; what does not goes in your own task's log instead of being thrown away:
  `node queue/bin/queue.mjs addjson '{"title":"...","goal":"...","epic":"<objective id this serves>","acceptance":["...","..."],"priority":"p2-normal","notes":"..."}'`

### A bug you file must be reproduced, not just read

Filing work is cheap and the top of the queue is expensive: a p1 bug takes the
slot the focus feature would have had, and a whole runner cycle goes to it. So a
follow-up that claims something is broken is held to the same standard as the
work itself.

- **Show it broken.** The task's `notes` carry the exact command you ran and the
  output it printed. No command and no output, no bug. "I read the code and it
  looks wrong" is a hypothesis, not a finding.
- **Run a script the way the machine runs it.** These scripts get executed, not
  read, and not all of them are bash: `queue/bin/refresh-dev-app.sh` is
  `#!/bin/zsh`. Checking a zsh script with `bash -n` reports errors that never
  happen in the real run, and that alone produced two false p1 bugs, one dropped
  on 2026-09-06 and an identical one on 2026-09-07. Run the script, or at least
  check it with the interpreter named on its own shebang line. Same rule for the
  app: build it, launch the probe, and watch the failure happen before you call
  it a failure.
- **Look for the evidence that it already worked.** The logs are right there:
  `queue/loop.log` for the loop, `queue/history.jsonl` for events, `git log` for
  what landed. A thing you believe never runs, having run successfully a hundred
  times with the last one an hour ago, is your answer.
- **If you cannot reproduce it, file it as something to look into, at
  `p2-normal`.** Title it as the open question ("Find out whether the dev app is
  being rebuilt between tasks"), say in the goal what you saw and what you could
  not confirm, and put the reproduction attempts that failed in `notes`. Never
  file an unreproduced problem as `p0-critical` or `p1-high`: priority is what
  makes a bug jump the queue ahead of the focus, and an unconfirmed one has not
  earned that.

This is about bugs the loop files against itself. A report from the user is
different: their report is the evidence, it stays p1, and reproducing it is the
first act of fixing it rather than a gate on filing it.

### Every task must be readable before it is implementable

A task carries three kinds of writing and they are not interchangeable:

- **`goal`** — one or two sentences of PLAIN LANGUAGE, written for someone who has never seen this codebase. Say what changes and for whom. No file names, no class names, no page ids, no shorthand like "ds-switch renders the five systems as the Library dgrp". If a person cannot tell from the goal whether they would want this done, it is not a goal yet.
- **`acceptance`** — the checklist that decides done. One verifiable item per entry, phrased so it can be checked off: "Every clickthrough page returns 200", not "verify pages". Two to five items is usually right.
- **`notes`** — your working detail. Be as technical as you like here: it is read last, by an agent, and it is where file names and class names belong.

This applies to tasks you CREATE and to the task you are running: if the task you claimed has no `goal` or an empty `acceptance`, write them into the task file as your first act, from what you learn reading it. The dashboard renders goal first, checklist second, detail last, so a queue full of jargon blobs is a queue nobody can steer.
- **Anything you leave changed and uncommitted is put away under your task's name.** When your turn ends, the loop compares the working tree against the picture it took before you started, and every file you dirtied and did not commit goes into a git stash whose message names your task. It says so in its window and on the dashboard, and it writes the restore command into your task's log. So an unfinished turn costs the next task nothing, and nothing you half-wrote is ever committed by somebody else. Two consequences for you:
  - If your task's log says *a previous attempt at this task left N file(s) changed*, that was you, last turn. Run the `git stash apply <sha>` it gives you before you start rebuilding it from scratch, or decide out loud in the log that you are starting over.
  - Finish by committing. A task you mark `done` with files still changed is recorded as a task that left work behind, and nobody is coming back for it.
  - The queue's own files (`queue/…`) are never stashed, and neither is anything that was already changed before you started: that is the user's own repo, not yours to move.
- Commit your work to main with a clear message when the task completes, then push: `git pull --rebase --autostash origin main && git push origin main`. If the rebase conflicts, abort it (`git rebase --abort`), leave your commit local, and record the situation in the task log; never force-push and never resolve someone else's conflict blind.
- Task titles name the outcome. Never put status words (blocked, in progress) in a title; status lives in the status field.

## Status protocol (do these, in this order)

1. On start, post a live note: `node queue/bin/queue.mjs note "<what you are doing>"`. Refresh it at each major phase change.
2. Append short progress entries to the task file's `log` array as you go (edit the JSON directly or note the essentials at the end).
3. Finish by setting a terminal status, exactly one of:
   - `node queue/bin/queue.mjs status <id> done "<what shipped, where, how verified>"`
   - `node queue/bin/queue.mjs status <id> blocked "<why>"` after opening a decision (below)
   - `node queue/bin/queue.mjs status <id> dropped "<why it should not be done>"`
   Never exit leaving the task `in_progress`.

## When you hit a product or UX ambiguity you cannot safely decide

Do not guess on anything the user would want to weigh in on (visual direction, scope, destructive changes, feature behavior). Instead:

1. Open a decision:
   `node queue/bin/queue.mjs decision <taskId> "<the question>" '<optionsJSON>' "<context>" "<recommended option id>"`
   where each option in the JSON array has this shape:
   `{"id":"a","label":"Short name","summary":"One or two plain sentences: what the user would see and do.","pros":["..."],"cons":["..."],"mitigation":"How the main con gets softened."}`
   Give 2 to 4 real options and always recommend one.
   **Mark the option that means do not build this with `"declines": true`.**
   Picking it retires the task for good instead of handing it back to the loop,
   and the card says so before the user chooses. Without the marker an answer of
   no comes straight back to a runner looking approved, which is exactly how a
   declined feature got built on 2026-09-02. Only mark an option that ends the
   whole task: "no button, copy as text instead" is still a yes to the task and
   must not carry it, while "skip this for now" is a no and must.
2. **Write the brief.** Alongside the decision, create
   `queue/decisions/<decisionId>.md`: a durable plain-language explainer that
   assumes the reader has NO context. Say what the surface or feature actually
   is, where it lives (link to the mock page, e.g.
   `http://127.0.0.1:8791/index.html#redline`), what the user would experience
   under each option, and anything visual worth studying (link to pages; a spec
   doc; a short worked example). Headings, short paragraphs, links. The
   dashboard renders this behind the card's "Explain in more detail" control,
   so the card itself stays short and the brief carries the depth.
3. **Frame it as a UX decision, never an engineering one.** The user is deciding
   what the product should feel like, not how to build it. Write the question
   and every option in terms of what appears on screen and what the user does;
   keep implementation detail out (no file names, class names, architectures).
   If the underlying question is technical, translate it into its visible
   consequence before filing; if it has no visible consequence, it is not a
   decision, so pick the sound engineering answer yourself and note it in the log.
3. Mark the task blocked (status protocol above) and exit. The dashboard shows
   each option as a card with your pros, cons, and mitigation; when the user
   selects one the task returns to the queue automatically with the answer
   written into its log.
4. If part of the task is decidable, finish that part first and say so in the log.

A card that no longer needs an answer is taken down, never answered for them.
If you find one on your task that has been overtaken — a duplicate of another
card, or a question something else already settled — take it down with its
reason instead of picking an option yourself:

```
node queue/bin/queue.mjs withdraw <decisionId> "<why it stopped mattering>"
```

It leaves the dashboard without ever looking answered, and it does NOT start the
work it was blocking: a task blocked with no question left stays blocked and
says so. If the question is still live but worded wrong, open a new card rather
than taking the old one down and hoping.

The user may answer while you are still working. If every question on your task
has been answered by the time you write `blocked`, the queue applies the answer
instead of leaving the task waiting: an approving answer puts it back in the
queue with the answer in its history, a declining one retires it. So do not
hand-edit a status file to force `blocked`, and if you can, re-read
`queue/decisions/<id>.json` before you exit: if it is already resolved, act on
the answer in this run rather than blocking at all.

## Adversarial review: twice, and it is not optional

**Before you build a feature**, spend real effort trying to break the idea, not the code:

- Walk the flow as a first-time user who has never seen the mock. Where do they stop? What do they have to already know?
- What does the mock assume that the app cannot deliver (state it does not have, a gesture that collides with an existing one, a control that has no home in the shell)?
- What is decorative rather than useful? Cut it.
- What is the SHORTEST version that delivers the same value? Prefer it.

Write the findings into the task log. If the mock is wrong, say so and build the better thing; if the disagreement is a UX judgment the user should make, open a decision instead of guessing. "The mock says so" is never a reason.

**Before you call it ready**, review the built thing the same way, on the real app: run it, use it as a person would, and be honest about what feels clumsy. Fix what you can, and record what you could not.

## When a feature is ready: write its audit

A feature is not done when it compiles. It is done when the user can try it and judge it. When your task completes a feature (or a usable slice of one), write `queue/audits/<YYYY-MM-DD>-<feature-id>.json`.

**It is structured and SHORT.** A long report does not get read, and the dashboard needs something it can hang a comment on, line by line:

```json
{
  "feature": "Measure and redline",
  "epic": "measure-redline",
  "summary": "One or two plain sentences: what you can now do that you could not before.",
  "setup": "Photonz Dev, Experiments window, release Next. Flags are on by default.",
  "try": [
    { "do": "One short imperative step. Name the exact key, menu item or gesture.", "shot": "2026-08-23-measure-1.png", "shotNote": "Only when the picture was taken under a lock: the line the walk handed you." },
    { "do": "The next step. Aim for five to eight steps total, not twenty." }
  ],
  "evaluate": [
    "A question you want answered, specific enough to answer yes or no."
  ],
  "rough": [
    "Anything that still feels clumsy, and anything you changed away from the mock and why."
  ]
}
```

Rules that keep it usable:

- **`try` is five to eight steps.** If it needs more, the feature is too big to playtest in one sitting: audit the slice that is ready.
- **Every step is one action.** No paragraphs, no background, no justification.
- **Ship a real screenshot.** If the walk's `Window captures:` line named real pictures, at least one step carries a `shot`, and it is a `-sc.png` from a playtest, copied next to the audit under `queue/audits/` and referenced by file name only. A locked screen is not an excuse: run a walk that survives a lock, or force one and take the pictures it reaches, and put the label the walk hands you in that step's `shotNote` so the picture says it was taken under a lock. The one case with no picture at all is a missing Screen Recording grant; say that in `rough` in one plain sentence and use the offscreen renders. An audit that quietly shows a render as if it were the app is the thing this rule exists to stop.
- **`evaluate` asks real questions**, three to five. "Does the readout land where your eye already is?" not "evaluate the readout".
- **`rough` is honest.** This is where you admit what you could not fix, and where the mock was wrong. Writing it here is not the same as filing it: each rough item either clears the follow-up bar and becomes a task, or gets folded into the task that already covers it, or stays in your task's log. Say which in your log.

The user reacts to any line of this on the dashboard, and their reaction becomes a task automatically, so write each line as something a person can agree or disagree with.

## Definition of done

- The acceptance items in the task file are each verified, not assumed. Build or test whatever the change touches.
- Task file updated, terminal status set, work committed. If you changed shared Current-release code, the porting rule applies: Next has the change too.
