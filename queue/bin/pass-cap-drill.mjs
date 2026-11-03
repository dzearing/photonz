#!/usr/bin/env node
// Drill for "at most three passes a day" (queue-lib passesToday, cappedForToday,
// readyTasks, taskRow).
//
// On 2026-11-02 the loop claimed Ask's component sheet task five times and
// spent about seven hours on it, each runner setting it back to pending because
// a judged bar was close but not reached. A task claimed three times since
// local midnight now waits until tomorrow (or for the user), and the row says
// why, so it does not read as stuck.
//
//   node queue/bin/pass-cap-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dir = mkdtempSync(join(tmpdir(), 'photonz-pass-cap-'));
process.env.PHOTONZ_QUEUE_DIR = dir;
for (const p of ['p0-critical', 'p1-high', 'p2-normal', 'p3-low']) mkdirSync(join(dir, 'tasks', p), { recursive: true });
const put = (t) => writeFileSync(join(dir, 'tasks', 'p1-high', t.id + '.json'), JSON.stringify(t));

const today = (h) => { const d = new Date(); d.setHours(h, 0, 0, 0); return d.toISOString(); };
const yesterday = (h) => { const d = new Date(); d.setDate(d.getDate() - 1); d.setHours(h, 0, 0, 0); return d.toISOString(); };
const claimed = (t) => ({ t, note: 'claimed by go loop' });

put({ id: 'worked-three-times', status: 'pending', seq: 1, deps: [], created: yesterday(1),
  log: [claimed(today(0)), claimed(today(0)), claimed(today(0)), { t: today(0), note: "back to pending" }] });
put({ id: 'worked-twice', status: 'pending', seq: 2, deps: [], created: yesterday(1), log: [claimed(today(0)), claimed(today(0))] });
put({ id: 'worked-a-lot-yesterday', status: 'pending', seq: 3, deps: [], created: yesterday(1),
  log: [claimed(yesterday(9)), claimed(yesterday(10)), claimed(yesterday(11)), claimed(yesterday(12))] });
put({ id: 'fresh', status: 'pending', seq: 4, deps: [], created: yesterday(1), log: [] });

const q = await import('./queue-lib.mjs');
let failures = 0;
const check = (what, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failures++; console.log(`  FAIL  ${what}\n        got  ${JSON.stringify(got)}\n        want ${JSON.stringify(want)}`); }
  else console.log(`  ok    ${what}`);
};
const all = () => q.readAllTasks();
const byId = (id) => all().find((t) => t.id === id);

check('three passes today is the cap', q.MAX_PASSES_A_DAY, 3);
check('passes are counted since local midnight', q.passesToday(byId('worked-three-times')), 3);
check('yesterday does not count', q.passesToday(byId('worked-a-lot-yesterday')), 0);
check('a task worked three times today is not ready; the rest are, in order',
  q.readyTasks().map((t) => t.id), ['worked-twice', 'worked-a-lot-yesterday', 'fresh']);
check('its row says why it waits', typeof q.taskRow(byId('worked-three-times')).cappedForToday, 'string');
check('a ready row carries no such note', q.taskRow(byId('fresh')).cappedForToday, undefined);
const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1); tomorrow.setHours(9);
check('tomorrow it is ready again', q.cappedForToday(byId('worked-three-times'), tomorrow), null);
check('claiming takes the next ready task, never the capped one', q.claimNext().id, 'worked-twice');

console.log(failures ? `\n${failures} failing` : '\nall passing');
process.exit(failures ? 1 : 0);
