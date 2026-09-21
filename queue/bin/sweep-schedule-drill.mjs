#!/usr/bin/env node
// Drill for when the walk sweep is allowed to run, and what a rotating check
// covers when it is not.
//
// This is the arithmetic that decides how the loop spends its day, so it is
// worth more than a comment. On 2026-09-21 the loop ran thirteen whole-set
// runs in twenty four hours and spent 58 per cent of its wall clock on them;
// the gate said yes every time because the only question it asked was whether
// a runner had asked, and a runner asks after every task.
//
//   node queue/bin/sweep-schedule-drill.mjs
import { decide, pickSlice, DEFAULTS } from './sweep-schedule.mjs';

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

const HOUR = 3600 * 1000;
const now = Date.parse('2026-09-21T12:00:00Z');
const ago = (h) => new Date(now - h * HOUR).toISOString();
const swept = (h, extra = {}) => ({ began: ago(h), head: 'old', complete: true, ...extra });
const asked = [{ t: ago(0.1), by: 'a-task', why: 'it landed code' }];

console.log('when a whole-set run is allowed');
check('nobody asked, so nothing runs',
  decide({ now, requests: [], latest: swept(20), head: 'new' }).run === 'nothing');
check('no sweep has ever run, so the first one runs whatever else is true',
  decide({ now, requests: asked, latest: null, head: 'new' }).run === 'full');
check('twelve hours have passed and code has landed, so the full set runs',
  decide({ now, requests: asked, latest: swept(13), head: 'new' }).run === 'full');
check('two hours have passed, so the full set does NOT run',
  decide({ now, requests: asked, latest: swept(2), head: 'new' }).run !== 'full',
  decide({ now, requests: asked, latest: swept(2), head: 'new' }));
check('...it runs the rotating check instead',
  decide({ now, requests: asked, latest: swept(2), head: 'new' }).run === 'slice');
check('a runner that asked for one straight away gets one inside the floor',
  decide({ now, requests: [{ t: ago(0.1), by: 'a-task', why: 'renderer rewrite', now: true }], latest: swept(2), head: 'new' }).run === 'full');
check('the floor is a knob, so a drill can move it',
  decide({ now, requests: asked, latest: swept(3), head: 'new', floorHours: 2 }).run === 'full');
check('the last full sweep already covered this exact commit, so nothing runs',
  decide({ now, requests: asked, latest: swept(20, { head: 'same' }), head: 'same' }).run === 'nothing');
check('...and it says so rather than going quiet',
  /already covered/.test(decide({ now, requests: asked, latest: swept(20, { head: 'same' }), head: 'same' }).why));

console.log('the rotating check in between');
check('nothing new has landed since the last rotating check, so it does not repeat',
  decide({ now, requests: asked, latest: swept(2), head: 'new', rotation: { cursor: 0, lastHead: 'new' } }).run === 'nothing');
check('a full sweep is not followed straight away by a rotating check over the same code',
  decide({ now, requests: asked, latest: swept(2, { head: 'same' }), head: 'same', rotation: { cursor: 0, lastHead: 'older' } }).run === 'nothing',
  decide({ now, requests: asked, latest: swept(2, { head: 'same' }), head: 'same', rotation: { cursor: 0, lastHead: 'older' } }));
check('new code since the last rotating check, so it runs again',
  decide({ now, requests: asked, latest: swept(2), head: 'newer', rotation: { cursor: 0, lastHead: 'new' } }).run === 'slice');

console.log('a locked screen');
check('the lock-safe part has already run against this commit, so nothing runs',
  decide({ now, requests: asked, latest: swept(20, { head: 'same', complete: false, partial: true }), head: 'same', screenLocked: true }).run === 'nothing');
check('new code and the floor elapsed, so the lock-safe part runs again',
  decide({ now, requests: asked, latest: swept(20, { head: 'old', complete: false, partial: true }), head: 'new', screenLocked: true }).run === 'full');
check('inside the floor a locked screen still gets the rotating check',
  decide({ now, requests: asked, latest: swept(2, { head: 'old', complete: false, partial: true }), head: 'new', screenLocked: true }).run === 'slice');

console.log('what a rotating check covers');
const walks = Array.from({ length: 100 }, (_, i) => `walk-${String(i).padStart(3, '0')}`);
let s = pickSlice({ walks, cursor: 0, changed: [], minutes: 10, perWalkSeconds: 12 });
check('ten minutes at twelve seconds a walk is fifty walks', s.walks.length === 50, s.walks.length);
check('it starts at the cursor', s.walks[0] === 'walk-000', s.walks[0]);
check('and leaves the cursor where it stopped', s.nextCursor === 50, s.nextCursor);
s = pickSlice({ walks, cursor: 80, changed: [], minutes: 10, perWalkSeconds: 12 });
check('the rotation wraps round the end of the set', s.walks.includes('walk-099') && s.walks.includes('walk-000'), s.walks.slice(18, 22));
check('and says it completed a lap', s.lap === true);
check('the cursor lands past the wrap', s.nextCursor === 30, s.nextCursor);
s = pickSlice({ walks, cursor: 0, changed: ['walk-090', 'walk-091'], minutes: 10, perWalkSeconds: 12 });
check('a walk whose script changed runs first, whatever the cursor says',
  s.walks[0] === 'walk-090' && s.walks[1] === 'walk-091', s.walks.slice(0, 3));
check('it is still fifty walks, not fifty two', s.walks.length === 50, s.walks.length);
check('and it says how many of them were there because they changed', s.changed.length === 2, s.changed);
s = pickSlice({ walks, cursor: 88, changed: ['walk-090'], minutes: 10, perWalkSeconds: 12 });
check('a changed walk the rotation would also reach is not run twice',
  s.walks.filter((w) => w === 'walk-090').length === 1, s.walks.length);
s = pickSlice({ walks: [], cursor: 0, changed: [], minutes: 10 });
check('an empty set picks nothing and does not spin', s.walks.length === 0 && s.nextCursor === 0);
s = pickSlice({ walks, cursor: 0, changed: ['not-a-walk'], minutes: 10 });
check('a changed file that is not a walk in the set is ignored',
  !s.walks.includes('not-a-walk') && s.changed.length === 0, s.changed);
s = pickSlice({ walks: walks.slice(0, 10), cursor: 0, changed: [], minutes: 10 });
check('a set smaller than the budget runs once through and no more',
  s.walks.length === 10, s.walks.length);

console.log('defaults');
check('the floor is twelve hours', DEFAULTS.floorHours === 12, DEFAULTS.floorHours);
check('a rotating check is budgeted at ten minutes', DEFAULTS.sliceMinutes === 10, DEFAULTS.sliceMinutes);

console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
