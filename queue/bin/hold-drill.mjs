#!/usr/bin/env node
// Drill for held tasks (queue.mjs hold / release, queue-lib holdTask,
// releaseTask, guardStuck, readyTasks, taskRow).
//
// On 2026-10-01 the intake window took the segmented chip task at the user's
// request and marked it in_progress. One second later `guard` reset it to
// pending, because guard resets every in_progress task, and the loop would have
// claimed it next: two hands on the same code at once. A HELD task is in
// progress in somebody else's hands: guard leaves it alone without counting a
// failure, the loop never claims it, and one command hands it back.
//
// Everything here runs through the CLI, the way the intake window and the loop
// call it, against a scratch queue.
//
//   node queue/bin/hold-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const CLI = join(dirname(fileURLToPath(import.meta.url)), 'queue.mjs');
const dir = mkdtempSync(join(tmpdir(), 'photonz-hold-'));
for (const p of ['p0-critical', 'p1-high', 'p2-normal', 'p3-low']) mkdirSync(join(dir, 'tasks', p), { recursive: true });
const file = (id) => join(dir, 'tasks', 'p1-high', id + '.json');
const put = (t) => writeFileSync(file(t.id), JSON.stringify({ deps: [], log: [], created: '2026-10-01T10:00:00.000Z', ...t }));
const task = (id) => JSON.parse(readFileSync(file(id), 'utf8'));
// Same tasks, same order of claim, as the real queue on 2026-10-01: the one the
// person took sits FIRST, so a loop that ignored the hold would claim it.
put({ id: 'the-person-has-this', title: 'The person has this one', status: 'pending', seq: 1 });
put({ id: 'ordinary-work', title: 'Ordinary loop work', status: 'pending', seq: 2 });

const env = { ...process.env, PHOTONZ_QUEUE_DIR: dir, PHOTONZ_SCREEN_LOCKED: '0' };
delete env.GO_LOOP_PID;
const run = (...args) => {
  const r = spawnSync(process.execPath, [CLI, ...args], { env, encoding: 'utf8' });
  return { code: r.status, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
};
const claimed = () => { const o = run('next').out; return o === 'none' ? 'none' : o.split('/').pop().replace(/\.json$/, ''); };
const row = (id) => JSON.parse(run('state').out).tasks.find((t) => t.id === id);

let failures = 0;
const check = (what, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failures++; console.log(`  FAIL  ${what}\n        got  ${JSON.stringify(got)}\n        want ${JSON.stringify(want)}`); }
  else console.log(`  ok    ${what}`);
};

console.log('holding:');
check('the intake window holds the first task in line', run('hold', 'the-person-has-this', 'the user asked for it here').code, 0);
check('it is in progress', task('the-person-has-this').status, 'in_progress');
check('and says who holds it', task('the-person-has-this').heldBy, 'intake');
check('the dashboard row names the holder', row('the-person-has-this').heldBy, 'intake');
check('the dashboard row says since when', typeof row('the-person-has-this').heldSince, 'string');
check('status <id> reads the holder back', /held by intake/.test(run('status', 'the-person-has-this').out), true);

console.log('the loop around it:');
check('next claims the other task, not the held one', claimed(), 'ordinary-work');
let g = JSON.parse(run('guard').out);
check('guard resets the loop runner\'s task left in progress', g.reset, ['ordinary-work']);
check('and leaves the held task in progress', task('the-person-has-this').status, 'in_progress');
check('without counting a failure against it', task('the-person-has-this').failures, undefined);
check('the runner\'s task does carry its failure', task('ordinary-work').failures, 1);
check('next claims the ordinary task again', claimed(), 'ordinary-work');
run('status', 'ordinary-work', 'dropped', 'drill');
check('with nothing else left, next claims nothing', claimed(), 'none');
for (let i = 0; i < 4; i++) run('guard');
check('guard run four more times still leaves it held', [task('the-person-has-this').status, task('the-person-has-this').heldBy], ['in_progress', 'intake']);
check('and never parks it', !!task('the-person-has-this').parked, false);

console.log('refusals:');
check('a hold named after the loop is refused', run('hold', 'ordinary-work', '--by', 'go loop').code, 1);
check('a second holder is refused', run('hold', 'the-person-has-this', '--by', 'someone-else').code, 1);
check('the same holder again changes nothing', run('hold', 'the-person-has-this').code, 0);
check('a finished task cannot be held', run('hold', 'ordinary-work').code, 1);
check('an unknown flag holds nothing', run('hold', 'ordinary-work', '--for', 'x').code, 1);
check('release of a task nobody holds is refused', run('release', 'ordinary-work').code, 1);
put({ id: 'runner-has-this', title: 'A runner has this one', status: 'in_progress', seq: 3 });
writeFileSync(join(dir, 'status.json'), JSON.stringify({ state: 'running', pid: process.pid, task: { id: 'runner-has-this' } }));
const r = run('hold', 'runner-has-this');
check('a task a live loop runner is on cannot be held', [r.code, /loop runner is working on/.test(r.err)], [1, true]);
writeFileSync(join(dir, 'status.json'), JSON.stringify({ state: 'stopped', pid: null, task: null }));
rmSync(file('runner-has-this'));

console.log('handing it back:');
check('release is one command', run('release', 'the-person-has-this', 'done for now').code, 0);
check('it is pending again', task('the-person-has-this').status, 'pending');
check('with no holder left on it', task('the-person-has-this').heldBy, undefined);
check('the row no longer names a holder', row('the-person-has-this').heldBy, undefined);
check('and next can claim it', claimed(), 'the-person-has-this');
run('guard');
check('held again from where guard left it', run('hold', 'the-person-has-this', '--by', 'the user').code, 0);
check('under the name it was given', task('the-person-has-this').heldBy, 'the user');
run('status', 'the-person-has-this', 'done', 'fixed in the intake window');
check('finishing it with status done ends the hold', [task('the-person-has-this').status, task('the-person-has-this').heldBy], ['done', undefined]);

console.log('a hand edit that kept the holder:');
put({ id: 'hand-edited', title: 'Hand edited back to pending', status: 'pending', seq: 0, heldBy: 'intake' });
check('a pending task that still names a holder is not claimed', claimed(), 'none');

rmSync(dir, { recursive: true, force: true });
if (failures) { console.log(`\n${failures} check(s) failed`); process.exit(1); }
console.log('\nall checks passed');
