#!/usr/bin/env node
// Writes down what a ROTATING CHECK found, and files nothing.
//
// A rotating check is about ten minutes of walks between tasks: fifty of five
// hundred and forty four, made of everything whose script changed plus the next
// chunk of the set (queue/bin/sweep-schedule.mjs). Its job is to catch a
// regression the day it lands rather than twelve hours later.
//
// It is deliberately NOT a sweep, and everything here is about keeping that
// true:
//
//   - it never clears a sweep request, so a full one is still owed;
//   - it never closes the standing walk task, because fifty walks passing is
//     not the state of five hundred;
//   - a walk it finds broken is APPENDED to the standing task's log, named, so
//     whoever is on that task sees it the same day. It does not file a task of
//     its own: the standing task already covers "walks that fail", and a check
//     that ran nine times a day would file nine near-twins of it.
//
//   queue/bin/sweep-slice-record.mjs <runlog> <out.json> <began> <ended> <seconds> <ran> <of> <pick.json> [<timedOut 0|1>]
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { parseSweepLog } from './sweep-parse.mjs';
import * as q from './queue-lib.mjs';

const [runlog, out, began, ended, seconds, ran, of, pickFile, timedOut] = process.argv.slice(2);
const cutShort = timedOut === '1';

const logText = existsSync(runlog) ? readFileSync(runlog, 'utf8') : '';
const r = parseSweepLog(logText, { total: 0 });
let pick = { changed: [], from: 0, nextCursor: 0 };
try { pick = JSON.parse(readFileSync(pickFile, 'utf8')); } catch { /* fine */ }

const record = {
  began, ended, seconds: Number(seconds),
  walks: r.walks, passed: r.passed, failed: r.failed, crashed: r.crashed,
  couldNotRun: r.couldNotRun,
  of: Number(of) || 0, asked: Number(ran) || 0,
  from: pick.from || 0, to: pick.nextCursor || 0,
  changed: pick.changed || [],
  rotating: true,
  timedOut: cutShort,
  log: runlog,
};
writeFileSync(out, JSON.stringify(record, null, 2) + '\n');

const broken = [...r.failed, ...r.crashed];
const scope = cutShort
  ? `${r.walks} of the ${ran} it set out to run (out of ${of})`
  : `${r.walks} of ${of} walks`;

if (!broken.length) {
  console.log(cutShort
    ? `==> Rotating check STOPPED ON THE CLOCK: ${scope}, nothing failing in them. It is not a clean check, and the rest of the set is unchecked, not passing.`
    : `==> Rotating check: ${scope}, nothing failing. The rest of the set is unchecked, not passing.`);
  process.exit(0);
}

console.log(`==> Rotating check${cutShort ? ' STOPPED ON THE CLOCK' : ''}: ${scope}, ${broken.length} failing: ${broken.join(', ')}`);
if (cutShort) console.log('    A stop takes the probe app down with it, so a walk failing in the last moments may be a casualty of the stop.');
if (r.crashed.length) console.log(`    ${r.crashed.length} of them CRASHED: the app was gone before the walk finished.`);

// Onto the standing task if there is one open, otherwise say so and stop. It
// does not open one: the next full sweep does that, with the whole set behind
// it, and a task opened off fifty walks would claim more than it knows.
const STANDING = 'walk-sweep';
const live = q.readAllTasks().filter((t) => !['done', 'dropped'].includes(t.status));
const open = live
  .filter((t) => t.standing === STANDING)
  .sort((a, b) => String(a.created || '').localeCompare(String(b.created || '')))[0];

const changedNote = (pick.changed || []).filter((w) => broken.includes(w));
const why = changedNote.length
  ? ` ${changedNote.join(', ')} had its own script changed since the last check.`
  : '';
const line = `rotating check ${ended}: ${broken.join(', ')} failing out of the ${r.walks} walks it ran (${pick.from} onward in the rotation).${why} This is a slice, not a sweep: the rest of the set is unchecked.`;

if (open) {
  q.noteTask(open.id, line);
  console.log(`    Written onto the standing task ${open.id}.`);
} else {
  console.log('    No standing walk task is open, so this is recorded here and in the loop log only.');
  console.log(`    ${line}`);
}
