#!/usr/bin/env node
// Turns a failing walk sweep into ONE standing task.
//
// The sweep runs whenever a runner asks for it, and the same walks tend to
// fail several sweeps in a row. Filing a fresh task each time would bury the
// queue in near-duplicates (queue-lib's addTask does not dedupe; it appends
// -2, -3 to the id), so the first failing sweep files the task and every
// later one appends its result to that task's log and refreshes its notes for
// as long as the task is still open.
//
// "Refreshes" and not "rewrites": the notes are also where a person writes
// down what each failing walk MEANS, and until 2026-09-13 a sweep replaced all
// of that with a fresh list. The sweep now owns only the block between the two
// markers in sweep-notes.mjs and carries everything below them across.
//
//   queue/bin/sweep-report.mjs queue/sweep/latest.json
import { readFileSync } from 'node:fs';
import * as q from './queue-lib.mjs';
import { mergeNotes, previousFailures, ownersOfWalks } from './sweep-notes.mjs';

const TITLE = 'Walks that fail in the full sweep';

const result = JSON.parse(readFileSync(process.argv[2], 'utf8'));
if (!result.failed?.length) {
  console.log('==> Nothing failing; no task filed.');
  process.exit(0);
}

const list = result.failed.join(', ');
const all = q.readAllTasks();
const open = all.find((t) => t.title === TITLE && !['done', 'dropped'].includes(t.status));

// Which failures already belong to another open task, so the list itself says
// which walks this task is actually meant to fix.
const owners = ownersOfWalks(result.failed, all, open?.id);

if (open) {
  const stopped = result.complete === false
    ? []
    : previousFailures(open.notes).filter((w) => !result.failed.includes(w));
  const tail = stopped.length ? `; stopped failing: ${stopped.join(', ')}` : '';
  q.appendLog(open, `sweep ${result.ended}: ${result.failed.length} failing (${list})${tail}`);
  q.saveTask({ ...open, notes: mergeNotes(open.notes, result, owners) });
  console.log(`==> Updated the standing task ${open.id} with ${result.failed.length} failing walk(s).`);
} else {
  const task = q.addTask({
    title: TITLE,
    goal:
      'The scripted walks are the app driving itself, and some of them no longer reach what they were written to check. ' +
      'Find out what each failing walk is looking for, then either fix the app if the walk is right or update the walk if the app moved on. ' +
      'This serves the focus because the sweep is the only thing that tells a focus runner whether the change it just made broke anything: ' +
      'a sweep with failures nobody has named cannot say that, so every focus feature ships on a weaker claim than it should.',
    epic: 'unmanned-loop',
    priority: 'p2-normal',
    area: 'queue',
    acceptance: [
      'Every walk the sweep block names as this task\'s own either passes or is rewritten to match what the app does now',
      'Each one is run on its own and passes twice in a row',
      'Any walk that was wrong rather than broken says so in this task log',
    ],
    notes: mergeNotes('', result, owners),
    source: 'sweep',
  });
  console.log(`==> Filed ${task.id} for ${result.failed.length} failing walk(s).`);
}
