#!/usr/bin/env node
// Writes what a ROTATING CHECK found onto the task that will fix it.
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
//   - it never writes the sweep's block of results: that block describes a run
//     over the set, and fifty walks is not one.
//
// What it DOES do is make sure every walk it saw fail lands on a task somebody
// will pick up, the same day:
//
//   - a walk another open task owns (it said so with `queue.mjs walks`, or its
//     words name the walk) is written onto THAT task, and nowhere else;
//   - every other failing walk is written onto the standing walk task, and if
//     none is open the check opens it. At most one task per check, and the
//     task names only the walks it saw fail, so it claims nothing about the
//     rest of the set.
//
// Until 2026-09-29 it opened nothing, on the grounds that "a task opened off
// fifty walks would claim more than it knows". The standing task was closed
// most of that week, so thirteen checks in a day printed their failures into
// queue/loop.log and nowhere else, and motion-pivot-in-a-corner-walk sat broken
// and unowned from the 11:03Z check until the daily digest happened to find it.
//
//   queue/bin/sweep-slice-record.mjs <runlog> <out.json> <began> <ended> <seconds> <ran> <of> <pick.json> [<timedOut 0|1>]
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { parseSweepLog } from './sweep-parse.mjs';
import * as q from './queue-lib.mjs';
import { ownersOfWalks, MACHINE_BEGIN, MACHINE_END } from './sweep-notes.mjs';

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
  // The app stopped launching part way through this check, so these walks were
  // never put in front of anything. Unanswered, and never written onto the
  // standing task as broken.
  blind: r.blind, blindWalks: r.blindWalks,
  of: Number(of) || 0, asked: Number(ran) || 0,
  from: pick.from || 0, to: pick.nextCursor || 0,
  changed: pick.changed || [],
  rotating: true,
  timedOut: cutShort,
  log: runlog,
};
writeFileSync(out, JSON.stringify(record, null, 2) + '\n');

// A check that lost the app says that first and loudest. Its own failures are
// still real and still get written down; what it never ran is not.
if (r.blind) {
  console.log(`==> Rotating check WENT BLIND: the app stopped launching at ${r.blind.from}, `
    + `so the ${r.blind.count} walks from there on never ran at all.`);
  console.log('    They are unknown, not failing, and none of them is named as broken anywhere.');
  console.log('    Chase why the probe will not launch: Scripts/probe-app.sh');
}

// r.crashed is {name, why} objects, not names. Spreading them straight in put
// "[object Object]" in the line this writes onto the standing walk task.
const broken = [...new Set([...r.failed, ...r.crashed.map((c) => c.name)])];
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

// Who gets told. The same marker and the same age rule the full sweep uses
// (queue/bin/sweep-report.mjs), so a check and a sweep always write onto the
// same standing task.
const STANDING = 'walk-sweep';
const TITLE = 'Walks that fail in the full sweep';
const all = q.readAllTasks();
const live = all.filter((t) => !['done', 'dropped'].includes(t.status));
const byAge = (a, b) => String(a.created || '').localeCompare(String(b.created || ''));
const standing = live.filter((t) => t.standing === STANDING).sort(byAge)[0]
  || live.filter((t) => t.title === TITLE).sort(byAge)[0];
const owners = ownersOfWalks(broken, all, standing?.id);

const changed = new Set((pick.changed || []).filter((w) => broken.includes(w)));
const how = `rotating check ${ended}, ${r.walks} walks run from ${pick.from || 0} onward in the rotation`
  + (cutShort ? ', STOPPED ON THE CLOCK so a late failure may be a casualty of the stop' : '');
const own = (ws) => ws.map((w) => (changed.has(w) ? `${w} (its script changed since the last check)` : w)).join(', ');

// Onto each owner, grouped so a task that owns three failing walks gets one line.
const byOwner = new Map();
for (const w of broken) {
  for (const id of owners[w]?.ids || []) {
    if (!byOwner.has(id)) byOwner.set(id, { walks: [], guessed: false });
    const o = byOwner.get(id);
    o.walks.push(w);
    if (!owners[w].declared) o.guessed = true;
  }
}
for (const [id, o] of byOwner) {
  const guess = o.guessed
    ? ` This task was picked because its words name the walk; if it is not yours, say so with node queue/bin/queue.mjs walks ${id} --none and the next check writes it onto the standing walk task instead.`
    : '';
  q.noteTask(id, `${how}: ${own(o.walks)} failing.${guess}`);
  console.log(`    ${o.walks.join(', ')}: written onto ${id}, which ${o.guessed ? 'names' : 'owns'} ${o.walks.length > 1 ? 'them' : 'it'}.`);
}

// Everything nobody owns goes onto the standing task, opening it if it has to.
const unowned = broken.filter((w) => !owners[w]?.ids?.length);
if (!unowned.length) process.exit(0);
const line = `${how}: ${own(unowned)} failing. This is a slice, not a sweep: the rest of the set is unchecked.`;

if (standing) {
  q.noteTask(standing.id, line);
  console.log(`    ${unowned.join(', ')}: written onto the standing walk task ${standing.id}.`);
} else {
  // The notes carry a block between the sweep's own markers, so the first full
  // sweep replaces it with its own reading of the set, and reads the list back
  // to say which of these walks stopped failing.
  const notes = [
    MACHINE_BEGIN,
    ``,
    `Opened by the rotating check at ${ended}, not by a full sweep: it ran ${r.walks} of ${of} walks and found the ones below failing with no other open task naming them. Nothing here is a claim about the rest of the set.`,
    ``,
    `Failing walks (${unowned.length}): ${unowned.join(', ')}`,
    ...(cutShort ? [``, `That check was stopped on the clock, so a walk failing in its last moments may be a casualty of the stop rather than a break.`] : []),
    ``,
    `Full output: ${runlog}. Re-run one of them on its own with`,
    `Scripts/playtest.sh Scripts/playtest/<name>.json --no-build, which takes about ten seconds.`,
    `Do NOT run Scripts/playtest-all.sh yourself; ask for a sweep with`,
    `queue/bin/sweep.sh request "<why>" and finish your task.`,
    ``,
    MACHINE_END,
  ].join('\n');
  const task = q.addTask({
    title: TITLE,
    goal:
      'The scripted walks are the app driving itself, and the check between tasks found some that no longer reach what they were written to check. ' +
      'Find out what each failing walk is looking for, then either fix the app if the walk is right or update the walk if the app moved on.',
    epic: 'unmanned-loop',
    priority: 'p2-normal',
    area: 'queue',
    acceptance: [
      'Every walk the sweep block names as this task\'s own either passes or is rewritten to match what the app does now',
      'Each one is run on its own and passes twice in a row',
      'Any walk that was wrong rather than broken says so in this task log',
    ],
    notes,
    source: 'rotating check',
  });
  q.appendLog(task, line);
  q.saveTask({ ...task, standing: STANDING });
  console.log(`    ${unowned.join(', ')}: no open task names ${unowned.length > 1 ? 'them' : 'it'}, so opened the standing walk task ${task.id}.`);
}
