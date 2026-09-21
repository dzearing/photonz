#!/usr/bin/env node
// Drill for "where did the loop's day go" (queue/bin/loop-day.mjs).
//
// The number this prints is the one an argument about the sweep turns on, so it
// has to survive the two things the history really does: a task that is never
// closed, and a whole-set run recorded twice by the recovery path.
//
//   node queue/bin/loop-day-drill.mjs
import { spansFrom, loopDay, sentences } from './loop-day.mjs';

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

const T = (h, m = 0) => new Date(Date.UTC(2026, 8, 21, h, m, 0)).toISOString();
const at = (h, m = 0) => Date.parse(T(h, m));

console.log('spans');
let spans = spansFrom([
  { t: T(1, 0), ev: 'task_started', id: 'a' },
  { t: T(1, 30), ev: 'task_done', id: 'a' },
], { now: at(2) });
check('a task runs from its start to its ending', spans.length === 1 && spans[0].to - spans[0].from === 30 * 60000, spans);

spans = spansFrom([
  { t: T(1, 0), ev: 'task_started', id: 'standing' },       // never closed
  { t: T(3, 0), ev: 'sweep_pass', seconds: 3600, walks: 500 },
  { t: T(3, 0), ev: 'task_started', id: 'b' },
  { t: T(3, 30), ev: 'task_done', id: 'b' },
], { now: at(4) });
const standing = spans.find((s) => s.id === 'standing');
check('a task that is never closed stops when the next thing the loop started begins',
  standing.to === at(2), new Date(standing.to).toISOString());
check('...so it does not swallow the sweep that followed it',
  standing.to <= at(2), new Date(standing.to).toISOString());

console.log('shares');
// Twelve hours: two hours of task, one hour of sweep, the rest between.
let r = loopDay({
  events: [
    { t: T(0, 0), ev: 'task_started', id: 'a' },
    { t: T(2, 0), ev: 'task_done', id: 'a' },
    { t: T(3, 0), ev: 'sweep_pass', seconds: 3600, walks: 544 },
  ],
  from: at(0), to: at(12),
});
check('the window is twelve hours', r.windowMinutes === 720, r.windowMinutes);
check('two hours on the task', r.minutes.tasks === 120, r.minutes.tasks);
check('one hour on the sweep', r.minutes.sweeps === 60, r.minutes.sweeps);
check('the rest is between', r.minutes.between === 540, r.minutes.between);
check('the shares add to one', Math.abs(Object.values(r.share).reduce((a, b) => a + b, 0) - 1) < 1e-9, r.share);

console.log('the two things the history really does');
r = loopDay({
  events: [
    { t: T(3, 0), ev: 'sweep_pass', seconds: 3600, walks: 544 },
    { t: T(3, 0), ev: 'sweep_pass', seconds: 3600, walks: 544 },   // recorded twice
  ],
  from: at(0), to: at(12),
});
check('the same run recorded twice is counted once', r.minutes.sweeps === 60, r.minutes.sweeps);
r = loopDay({
  events: [
    { t: T(0, 0), ev: 'task_started', id: 'a' },
    { t: T(1, 0), ev: 'sweep_pass', seconds: 1800, walks: 50 },
  ],
  from: at(0), to: at(2),
});
check('a task is cut off where the run that followed it began', r.minutes.tasks === 30, r.minutes.tasks);

console.log('clipping');
r = loopDay({
  events: [{ t: T(2, 0), ev: 'sweep_pass', seconds: 4 * 3600, walks: 544 }],
  from: at(1), to: at(3),
});
check('a run that started before the window counts only the part inside it',
  r.minutes.sweeps === 60, r.minutes.sweeps);

console.log('what it says out loud');
r = loopDay({
  events: [
    { t: T(0, 0), ev: 'task_started', id: 'a' },
    { t: T(1, 0), ev: 'task_done', id: 'a' },
    { t: T(11, 0), ev: 'sweep_pass', seconds: 10 * 3600, walks: 544 },
  ],
  from: at(0), to: at(12),
});
check('a day mostly spent sweeping says so in words',
  sentences(r).some((l) => /did NOT spend the majority/.test(l)), sentences(r).slice(-1));
r = loopDay({
  events: [
    { t: T(0, 0), ev: 'task_started', id: 'a' },
    { t: T(10, 0), ev: 'task_done', id: 'a' },
    { t: T(11, 0), ev: 'sweep_pass', seconds: 3600, walks: 544 },
  ],
  from: at(0), to: at(12),
});
check('a day mostly spent building says that instead',
  sentences(r).some((l) => /spent the majority of this window building/.test(l)), sentences(r).slice(-1));
check('a rotating check is counted apart from a sweep',
  loopDay({ events: [{ t: T(1, 0), ev: 'slice_pass', seconds: 600, walks: 50 }], from: at(0), to: at(12) }).minutes.slices === 10);

console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
