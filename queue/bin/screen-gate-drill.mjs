#!/usr/bin/env node
// Drill for the "waits for an unlocked screen" gate (queue-lib screenIsLocked,
// waitingForScreen, readyTasks, taskRow, claimNext).
//
// A handful of tasks can only be answered with somebody logged in at the Mac:
// confirming that File ▸ Save is not greyed out after a trim is the one that
// forced this, because a locked Mac gives the app no key window and every
// window-scoped menu command then reads dimmed whatever the document says.
// Such a task used to either strand (marked blocked with no decision card,
// which nothing but an answer ever returns to the queue) or spin (left pending,
// re-claimed every pass, burning a runner cycle on the same lock). It now stays
// pending and simply is not ready while the screen is locked.
//
// What this holds honest: the gate only touches tasks that ask for it, it lets
// go the instant the screen is unlocked, it says WHY on the row so a waiting
// task does not read as stuck, and the lock check fails OPEN so a broken
// reading can only let a task run, never hide one forever.
//
//   node queue/bin/screen-gate-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dir = mkdtempSync(join(tmpdir(), 'photonz-screen-gate-'));
process.env.PHOTONZ_QUEUE_DIR = dir;
for (const p of ['p0-critical', 'p1-high', 'p2-normal', 'p3-low']) {
  mkdirSync(join(dir, 'tasks', p), { recursive: true });
}
const put = (prio, t) => writeFileSync(join(dir, 'tasks', prio, t.id + '.json'), JSON.stringify(t));

put('p1-high', {
  id: 'needs-a-person', title: 'Confirm the menu on an unlocked screen', status: 'pending',
  seq: 1, waitsForUnlockedScreen: true, created: '2026-09-19T10:00:00.000Z', deps: [], log: [],
});
put('p1-high', {
  id: 'ordinary-work', title: 'Ordinary work', status: 'pending',
  seq: 2, created: '2026-09-19T10:00:00.000Z', deps: [], log: [],
});

const q = await import('./queue-lib.mjs');

let failures = 0;
const check = (what, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failures++; console.log(`  FAIL  ${what}\n        got  ${JSON.stringify(got)}\n        want ${JSON.stringify(want)}`); }
  else console.log(`  ok    ${what}`);
};
const readyIds = () => q.readyTasks().map((t) => t.id);
const row = (id) => q.taskRow(q.readAllTasks().find((t) => t.id === id));

console.log('screen locked:');
process.env.PHOTONZ_SCREEN_LOCKED = '1';
check('the lock reading says locked', q.screenIsLocked(), true);
check('a task that needs a person is not ready', readyIds(), ['ordinary-work']);
check('and its row says why it is waiting',
      typeof row('needs-a-person').waitingForScreen === 'string', true);
check('ordinary work is untouched', row('ordinary-work').waitingForScreen, undefined);
check('the loop claims the ordinary task instead', q.claimNext().id, 'ordinary-work');

console.log('screen unlocked:');
process.env.PHOTONZ_SCREEN_LOCKED = '0';
check('the lock reading says unlocked', q.screenIsLocked(), false);
check('the waiting task comes back by itself', readyIds(), ['needs-a-person']);
check('and its row stops saying it is waiting', row('needs-a-person').waitingForScreen, undefined);
check('the loop claims it', q.claimNext().id, 'needs-a-person');
// ...and now that somebody is on it, the row stops saying it is held back, which
// on a task being worked would read as the loop refusing to touch it.
process.env.PHOTONZ_SCREEN_LOCKED = '1';
check('a task already claimed does not read as waiting', row('needs-a-person').waitingForScreen, undefined);

console.log('the reading fails open:');
// Nothing can answer, so nothing is hidden: a gate that cannot read the screen
// must let the work through rather than park it forever.
delete process.env.PHOTONZ_SCREEN_LOCKED;
const path = process.env.PATH;
process.env.PATH = join(dir, 'no-such-bin');
q.forgetScreenReading();
check('with no way to read the lock, a waiting task is ready', q.screenIsLocked(), false);
process.env.PATH = path;

console.log(failures ? `\n${failures} failure(s)` : '\nall good');
process.exit(failures ? 1 : 0);
