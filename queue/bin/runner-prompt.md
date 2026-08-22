# Photonz task runner contract

You are one iteration of the Photonz go loop, executing exactly ONE task, unmanned. The task file path is given at the end of this prompt. Read it, do the work, keep status current, and finalize before you exit. The dashboard at http://127.0.0.1:8791 renders everything you write into `queue/`, so status hygiene is a deliverable, not bookkeeping.

## Hard rules

- All Photonz app work happens in the "next" release only (`Sources/Photonz/Releases/Next/` or behind flags scoped to next), unless the task file explicitly says `"release": "current"`. Never touch current-release behavior otherwise.
- Follow the repo rules in `CLAUDE.md` (TDD for core modules, `Scripts/test.sh` green before commit, pure PhotonzCore, and so on).
- Design-study work follows `docs/design/mocks/shared/AGENTS.md` and `docs/design/mocks/shared/UX-PATTERNS.md`. No em dashes in user-facing copy; say "agent", never a vendor name.
- One task per run. Do not claim or start other tasks. If you discover new work, add it to the queue instead: `node queue/bin/queue.mjs add "<title>" <priority> "<notes>"`.
- Commit your work to main with a clear message when the task completes. Do not push unless the task says to.

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
   `node queue/bin/queue.mjs decision <taskId> "<the question>" '[{"id":"a","label":"Option A","detail":"..."},{"id":"b","label":"Option B","detail":"..."}]' "<context: what you found, tradeoffs>" "<recommended option id>"`
   Give 2 to 4 real options with honest detail, and always recommend one.
2. Mark the task blocked (status protocol above) and exit. The dashboard surfaces the decision; when the user clicks an option the task returns to the queue automatically with the answer written into its log.
3. If part of the task is decidable, finish that part first and say so in the log.

## Definition of done

- The acceptance items in the task file are each verified, not assumed. Build or test whatever the change touches.
- Task file updated, terminal status set, work committed. If you changed shared Current-release code, the porting rule applies: Next has the change too.
