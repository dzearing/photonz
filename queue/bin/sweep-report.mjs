#!/usr/bin/env node
// Turns a failing walk sweep into ONE standing task.
//
// The sweep runs whenever a runner asks for it, and the same walks tend to
// fail several sweeps in a row. Filing a fresh task each time would bury the
// queue in near-duplicates (queue-lib's addTask does not dedupe; it appends
// -2, -3 to the id), so the first failing sweep files the task and every
// later one appends its result to that task's log and rewrites its notes for
// as long as the task is still open.
//
//   queue/bin/sweep-report.mjs queue/sweep/latest.json
import { readFileSync } from 'node:fs';
import * as q from './queue-lib.mjs';

const TITLE = 'Walks that fail in the full sweep';

const result = JSON.parse(readFileSync(process.argv[2], 'utf8'));
if (!result.failed?.length) {
  console.log('==> Nothing failing; no task filed.');
  process.exit(0);
}

const list = result.failed.join(', ');
const asked = result.requests?.map((r) => `${r.by}: ${r.why}`).join('; ') || 'a scheduled sweep';
const notes = [
  result.complete === false
    ? `Last sweep ${result.ended} DID NOT FINISH${result.timedOut ? ' (stopped on the clock)' : ''}: it reached ${result.walks} walks in ${Math.round(result.seconds / 60)} minutes, of which ${result.passed} passed. The walks it never reached are unknown, not passing.`
    : `Last sweep ${result.ended}: ${result.passed} of ${result.walks} walks passed in ${Math.round(result.seconds / 60)} minutes.`,
  ``,
  `Failing walks (${result.failed.length}): ${list}`,
  ``,
  `Full output: ${result.log}. Re-run one of them on its own with`,
  `Scripts/playtest.sh Scripts/playtest/<name>.json --no-build, which takes about ten seconds.`,
  `Do NOT run Scripts/playtest-all.sh yourself; ask for a sweep with`,
  `queue/bin/sweep.sh request "<why>" and finish your task.`,
  ``,
  `Sweep asked for by: ${asked}`,
].join('\n');

const open = q.readAllTasks().find(
  (t) => t.title === TITLE && !['done', 'dropped'].includes(t.status),
);

if (open) {
  q.appendLog(open, `sweep ${result.ended}: ${result.failed.length} failing (${list})`);
  q.saveTask({ ...open, notes });
  console.log(`==> Updated the standing task ${open.id} with ${result.failed.length} failing walk(s).`);
} else {
  const task = q.addTask({
    title: TITLE,
    goal:
      'The scripted walks are the app driving itself, and some of them no longer reach what they were written to check. ' +
      'Find out what each failing walk is looking for, then either fix the app if the walk is right or update the walk if the app moved on.',
    epic: 'unmanned-loop',
    priority: 'p2-normal',
    area: 'queue',
    acceptance: [
      'Every walk named in the notes either passes or is rewritten to match what the app does now',
      'Each one is run on its own and passes twice in a row',
      'Any walk that was wrong rather than broken says so in this task log',
    ],
    notes,
    source: 'sweep',
  });
  console.log(`==> Filed ${task.id} for ${result.failed.length} failing walk(s).`);
}
