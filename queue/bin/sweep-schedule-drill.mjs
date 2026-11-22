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
import { decide as decideAt, pickSlice, DEFAULTS, decideFromDisk as decideFromDiskAt, codeLandedBetween, WALK_PATHS, sliceWalkSeconds, sliceWalkSecondsFromDisk, settleSlice, answeredInLog, walkSecondsFromLogs, lapEstimate } from './sweep-schedule.mjs';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync, utimesSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';

// The scenarios below are written in hours against a ONE-DAY floor (26 hours is
// "over the floor", 2 is "inside it"), which is the rule they drill, not the
// floor the loop uses today (72 since 2026-11-05; checked under "defaults").
const decide = (o) => decideAt({ floorHours: 24, ...o });
const decideFromDisk = (o) => decideFromDiskAt({ floorHours: 24, ...o });

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

console.log('code landing is the ask (2026-10-02: seven app commits, no request, no walk check)');
// Until 2026-10-02 the gate returned nothing the moment requests was empty, and
// runners are told to ask only when they need the whole set, so nobody asked
// and nothing ran for a day and a half of app commits.
check('nobody asked, a day has passed and code has landed, so the full set runs',
  decide({ now, requests: [], latest: swept(26), head: 'new', codeSinceFull: true }).run === 'full',
  decide({ now, requests: [], latest: swept(26), head: 'new', codeSinceFull: true }));
check('nobody asked, two hours in and code has landed, so the rotating check runs',
  decide({ now, requests: [], latest: swept(2), head: 'new', codeSinceFull: true, codeSinceCheck: true, rotation: { cursor: 0, lastHead: 'older' } }).run === 'slice',
  decide({ now, requests: [], latest: swept(2), head: 'new', codeSinceFull: true, codeSinceCheck: true, rotation: { cursor: 0, lastHead: 'older' } }));
check('...and its reason says code landed, not that somebody asked',
  /landed/.test(decide({ now, requests: [], latest: swept(2), head: 'new', codeSinceFull: true, codeSinceCheck: true, rotation: { cursor: 0, lastHead: 'older' } }).why));
check('only queue files moved HEAD since the last check, so no rotating check',
  decide({ now, requests: [], latest: swept(2), head: 'digest', codeSinceFull: true, codeSinceCheck: false, rotation: { cursor: 0, lastHead: 'older' } }).run === 'nothing',
  decide({ now, requests: [], latest: swept(2), head: 'digest', codeSinceFull: true, codeSinceCheck: false, rotation: { cursor: 0, lastHead: 'older' } }));
check('only queue files moved HEAD since the last whole-set run, a day on, so no whole-set run',
  decide({ now, requests: [], latest: swept(26), head: 'digest', codeSinceFull: false }).run === 'nothing',
  decide({ now, requests: [], latest: swept(26), head: 'digest', codeSinceFull: false }));
check('...and it says the code is what the last sweep saw',
  /already covered/.test(decide({ now, requests: [], latest: swept(26), head: 'digest', codeSinceFull: false }).why));
check('a pending request does not make a queue-only commit worth a whole-set run',
  decide({ now, requests: asked, latest: swept(26), head: 'digest', codeSinceFull: false }).run === 'nothing');
check('a pending request with code landed still gets its whole-set run a day on',
  decide({ now, requests: asked, latest: swept(26), head: 'new', codeSinceFull: true }).run === 'full');
check('a request for one straight away still jumps the floor with no code landed',
  decide({ now, requests: [{ t: ago(0.1), by: 'a-task', why: 'harness', now: true }], latest: swept(2), head: 'digest', codeSinceFull: false }).run === 'full');
check('a partial run the lock cut short is owed a whole run a day on, once unlocked, request or not',
  decide({ now, requests: [], latest: swept(26, { complete: false, partial: true }), head: 'digest', codeSinceFull: false }).run === 'full');
check('...but not while the screen is still locked',
  decide({ now, requests: [], latest: swept(26, { complete: false, partial: true }), head: 'digest', codeSinceFull: false, screenLocked: true }).run === 'nothing');
check('what counts as code: Sources and the walk scripts are in it',
  WALK_PATHS.includes('Sources') && WALK_PATHS.includes('Scripts'), WALK_PATHS);
check('...and the queue, docs and tests are not',
  !WALK_PATHS.some((p) => /^(queue|docs|Tests)/.test(p)), WALK_PATHS);

console.log('when a whole-set run is allowed');
check('no sweep has ever run, so the first one runs whatever else is true',
  decide({ now, requests: asked, latest: null, head: 'new' }).run === 'full');
check('a day has passed and code has landed, so the full set runs',
  decide({ now, requests: asked, latest: swept(25), head: 'new' }).run === 'full');
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
  decide({ now, requests: asked, latest: swept(26, { head: 'same' }), head: 'same' }).run === 'nothing');
check('...and it says so rather than going quiet',
  /already covered/.test(decide({ now, requests: asked, latest: swept(26, { head: 'same' }), head: 'same' }).why));

console.log('a whole-set run that went blind');
// 2026-09-28: two whole-set runs on the same commit went blind at the same walk
// (the probe would not relaunch after the 1080p export walk), fifty minutes
// each, and the gate would have started a third, because a blind run is kept
// out of latest.json and so the floor still read as a day and more.
const wentBlind = (h, head, extra = {}) => ({ began: ago(h), head, complete: false, blind: { from: 'x', count: 5 }, ...extra });
check('a blind run on this commit is not followed by another whole-set run on it',
  decide({ now, requests: asked, latest: swept(26), blind: wentBlind(1, 'same'), head: 'same' }).run !== 'full',
  decide({ now, requests: asked, latest: swept(26), blind: wentBlind(1, 'same'), head: 'same' }));
check('...it gets the rotating check instead, once',
  decide({ now, requests: asked, latest: swept(26), blind: wentBlind(1, 'same'), head: 'same' }).run === 'slice');
check('...and says the whole set went blind on this commit',
  /blind/.test(decide({ now, requests: asked, latest: swept(26), blind: wentBlind(1, 'same'), head: 'same' }).why));
check('once that rotating check has run too, nothing runs until code lands',
  decide({ now, requests: asked, latest: swept(26), blind: wentBlind(1, 'same'), head: 'same', rotation: { cursor: 0, lastHead: 'same' } }).run === 'nothing');
check('new code since the blind run, so the whole set runs again',
  decide({ now, requests: asked, latest: swept(26), blind: wentBlind(1, 'old'), head: 'new' }).run === 'full');
check('only the queue\'s own files changed since the blind run, so it still counts as this code',
  decide({ now, requests: asked, latest: swept(26), blind: wentBlind(1, 'before-digest'), head: 'digest', blindCodeUnchanged: true }).run === 'slice');
check('a blind run older than the last whole-set run is history and changes nothing',
  decide({ now, requests: asked, latest: swept(26, { head: 'old' }), blind: wentBlind(30, 'same'), head: 'same' }).run === 'full');
check('a runner asking for the whole set straight away still gets it',
  decide({ now, requests: [{ t: ago(0.1), by: 'a-task', why: 'launcher fixed', now: true }], latest: swept(26), blind: wentBlind(1, 'same'), head: 'same' }).run === 'full');

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
  decide({ now, requests: asked, latest: swept(26, { head: 'same', complete: false, partial: true }), head: 'same', screenLocked: true }).run === 'nothing');
check('new code and the floor elapsed, so the lock-safe part runs again',
  decide({ now, requests: asked, latest: swept(26, { head: 'old', complete: false, partial: true }), head: 'new', screenLocked: true }).run === 'full');
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

console.log('walks every rotating check runs');
s = pickSlice({ walks, cursor: 10, changed: ['walk-091'], always: ['walk-050'], minutes: 10, perWalkSeconds: 12 });
check('a walk named for every check runs first, ahead of the changed ones and the cursor',
  s.walks[0] === 'walk-050' && s.walks[1] === 'walk-091', s.walks.slice(0, 3));
check('and it is counted inside the budget, not on top of it', s.walks.length === 50, s.walks.length);
check('and it says which ones were there for that reason', JSON.stringify(s.always) === '["walk-050"]', s.always);
s = pickSlice({ walks, cursor: 40, changed: [], always: ['walk-050'], minutes: 10, perWalkSeconds: 12 });
check('the rotation reaching it as well does not run it twice',
  s.walks.filter((w) => w === 'walk-050').length === 1, s.walks.length);
s = pickSlice({ walks, cursor: 0, changed: [], always: ['gone-walk'], minutes: 10, perWalkSeconds: 12 });
check('a name that is no longer a walk in the set is left out', !s.walks.includes('gone-walk') && s.always.length === 0, s.always);
check('the end to end editing session walk is in every check',
  DEFAULTS.everyCheck.includes('an-editing-session-walk'), DEFAULTS.everyCheck);
check('the 3D grippers walk is in every check',
  DEFAULTS.everyCheck.includes('3d-grippers-on-a-picked-layer-walk'), DEFAULTS.everyCheck);
check('the walk that proves a walk press still fires a SwiftUI button is in every check',
  DEFAULTS.everyCheck.includes('a-press-fires-a-plain-button-walk'), DEFAULTS.everyCheck);

console.log('how long a walk takes, measured off the checks that ran (2026-10-06: planned at 12s, ran at 17.6s)');
// Until 2026-10-06 a check was planned at a fixed twelve seconds a walk, so it
// always picked fifty walks, while walks had grown to about eighteen seconds:
// every "ten minute" check ran about fifteen, an hour and a half of the loop's
// day it was never meant to spend.
const slice = (seconds, extra = {}) => ({ ev: 'slice_pass', walks: 50, seconds, rotating: true, ...extra });
let m = sliceWalkSeconds([slice(880), slice(880), slice(880)]);
check('even checks give their cost back: 880s for fifty walks is 17.6s a walk', Math.abs(m.seconds - 17.6) < 0.01, m);
check('...and say it was measured, and over how many checks', m.measured === true && m.checks === 3, m);
m = sliceWalkSeconds([slice(880), slice(880), slice(880), slice(3000)]);
check('one slow check does not move it (the median, not the mean)', Math.abs(m.seconds - 17.6) < 0.01, m);
m = sliceWalkSeconds([slice(880), slice(880), slice(600, { timedOut: true })]);
check('a check stopped on the clock is not read as its walks being cheap', Math.abs(m.seconds - 17.6) < 0.01 && m.checks === 2, m);
m = sliceWalkSeconds([slice(880), slice(880), slice(200, { couldNotRun: 20 })]);
check('a check a locked screen cut down is not read as quick walks', Math.abs(m.seconds - 17.6) < 0.01 && m.checks === 2, m);
m = sliceWalkSeconds([slice(880), slice(880), slice(30, { walks: 3 }), slice(40)]);
check('a check of a handful of walks, or one that did not really run, is thrown out', Math.abs(m.seconds - 17.6) < 0.01 && m.checks === 2, m);
m = sliceWalkSeconds([{ ev: 'sweep_pass', walks: 700, seconds: 7000 }, slice(880)]);
check('a whole-set run is not a rotating check', m.checks === 1, m);
m = sliceWalkSeconds([...Array(10).fill(slice(600)), ...Array(10).fill(slice(900))]);
check('only the last ten checks count, so it follows the walks as they grow', Math.abs(m.seconds - 18) < 0.01 && m.checks === 10, m);
m = sliceWalkSeconds([]);
check('with no check recorded it says so rather than inventing a number', m.measured === false && m.checks === 0, m);
s = pickSlice({ walks: Array.from({ length: 800 }, (_, i) => `w${i}`), cursor: 0, minutes: 10, perWalkSeconds: 17.6 });
check('ten minutes at the measured 17.6s a walk is 34 walks, not fifty', s.walks.length === 34, s.walks.length);
check('...which is about ten minutes, not fifteen', Math.abs(s.walks.length * 17.6 / 60 - 10) < 0.5, s.walks.length * 17.6 / 60);
s = pickSlice({ walks: Array.from({ length: 800 }, (_, i) => `w${i}`), cursor: 790, minutes: 10, perWalkSeconds: 17.6 });
check('the cursor still moves on by what ran and wraps, so no walk is skipped for good', s.nextCursor === 24 && s.lap === true, s);
{
  const q = mkdtempSync(join(tmpdir(), 'sweep-schedule-measure-'));
  try {
    mkdirSync(join(q, 'queue'), { recursive: true });
    const lines = [
      JSON.stringify({ ev: 'task_done', id: 'x' }),
      'not json at all',
      ...Array(5).fill(JSON.stringify(slice(900))),
    ];
    writeFileSync(join(q, 'queue', 'history.jsonl'), lines.join('\n') + '\n');
    m = sliceWalkSecondsFromDisk(q);
    check('read off queue/history.jsonl, past lines that are not checks or not JSON', Math.abs(m.seconds - 18) < 0.01 && m.measured, m);
    check('...and says where the number came from', /rotating check/.test(m.from), m.from);
    writeFileSync(join(q, 'queue', 'history.jsonl'), JSON.stringify({
      ev: 'sweep_pass', walks: 500, seconds: 7000, couldNotRun: 0,
    }) + '\n');
    m = sliceWalkSecondsFromDisk(q);
    check('with no check yet it falls back on the whole-set runs', Math.abs(m.seconds - 14) < 0.01 && /sweep/.test(m.from), m);
    rmSync(join(q, 'queue', 'history.jsonl'));
    m = sliceWalkSecondsFromDisk(q);
    check('and with no history at all it still gives a number', m.seconds > 0 && m.measured === false, m);
  } finally {
    rmSync(q, { recursive: true, force: true });
  }
}

console.log('a check sized by what its own walks cost (2026-11-20: Ask walks at 100 to 390s planned at the 19.8s median)');
// From position 157 the set holds a block of Ask walks at 100 to 390s each.
// Planned at the median pace, thirty of them went in, and eight checks out of
// nine were stopped on the thirty minute clock.
{
  const set = Array.from({ length: 100 }, (_, i) => `walk-${String(i).padStart(3, '0')}`);
  const slow = {};
  for (let i = 10; i < 30; i++) slow[set[i]] = 200;
  let p = pickSlice({ walks: set, cursor: 10, changed: [], always: [], minutes: 10, perWalkSeconds: 20, walkSeconds: slow });
  check('three 200s walks fill ten minutes, not thirty walks at the median', p.walks.length === 3 && p.nextCursor === 13, p.walks);
  check('...and the plan says it ends inside the ten minutes', p.estimatedSeconds <= 600, p.estimatedSeconds);
  p = pickSlice({ walks: set, cursor: 0, changed: [], always: [], minutes: 10, perWalkSeconds: 20, walkSeconds: slow });
  check('a walk with no time on record is costed at the measured pace, and the plan stops before a slow walk that would not fit',
    p.walks.length === 12 && p.nextCursor === 12, { n: p.walks.length, next: p.nextCursor });
  p = pickSlice({ walks: set, cursor: 10, changed: [], always: [], minutes: 10, perWalkSeconds: 20, walkSeconds: { 'walk-010': 900 } });
  check('a single walk longer than the whole budget still runs, so the rotation always moves', p.walks.length === 1 && p.nextCursor === 11, p);
  p = pickSlice({ walks: set, cursor: 0, changed: ['walk-090', 'walk-091', 'walk-092', 'walk-093'], always: [], minutes: 10, perWalkSeconds: 20, walkSeconds: { 'walk-090': 200, 'walk-091': 200, 'walk-092': 200, 'walk-093': 20 } });
  check('changed walks take at most half the check: the rest wait for the next one',
    p.changed.length === 2 && p.owed.length === 2 && p.rotated.length > 0, { changed: p.changed, owed: p.owed, rotated: p.rotated.length });
  check('...a small changed walk still fits in beside a big one', p.changed.includes('walk-093'), p.changed);
  p = pickSlice({ walks: set, cursor: 0, owed: ['walk-092'], changed: ['walk-095'], always: [], minutes: 10, perWalkSeconds: 20 });
  check('what an earlier check owes runs ahead of newer changes', p.walks[0] === 'walk-092' && p.changed[1] === 'walk-095', p.walks.slice(0, 3));
  p = pickSlice({ walks: set, cursor: 0, changed: Array.from({ length: 27 }, (_, i) => set[50 + i]), always: [], minutes: 10, perWalkSeconds: 20 });
  check('twenty seven changed walks no longer fill the check and leave the rotation standing (2026-11-21)',
    p.rotated.length >= 10 && p.owed.length > 0, { rotated: p.rotated.length, owed: p.owed.length });
}

console.log('a check stopped on the clock moves on past what it finished');
{
  const set = Array.from({ length: 100 }, (_, i) => `walk-${String(i).padStart(3, '0')}`);
  const pick = { ...pickSlice({ walks: set, cursor: 20, changed: ['walk-090'], always: ['walk-000'], minutes: 10, perWalkSeconds: 60 }), from: 20 };
  // walk-000 (every check), walk-090 (changed), walk-020..walk-027 (rotation)
  const log = [
    '==> Building the probe bundle...',
    'walk-000                   16s  ok',
    'walk-020                   61s  ok',
    'walk-021                   70s  FAILED  step 3 (expect): no',
    'walk-022                   12s  DEFERRED  somebody is using the Mac, and this walk photographs an open menu',
    'walk-023                  ',
  ].join('\n');
  const answered = answeredInLog(log);
  check('the log answers the walks with a verdict, a failure and a deferral included',
    ['walk-000', 'walk-020', 'walk-021', 'walk-022'].every((w) => answered.has(w)), [...answered]);
  check('...and not the walk the stop caught part way', !answered.has('walk-023'), [...answered]);
  check('a walk that found no app to run in is not answered', !answeredInLog('walk-001   0s  COULD NOT START  the probe did not launch').has('walk-001'));
  let r = settleSlice(pick, answered);
  check('the cursor moves past the three rotation walks it finished, to the one it was in', r.cursor === 23 && r.moved === 3, r);
  check('...the changed walk it never reached is owed to the next check', JSON.stringify(r.owed) === '["walk-090"]', r.owed);
  check('...and it does not read as a check that got through', r.complete === false, r);
  const next = pickSlice({ walks: set, cursor: r.cursor, owed: r.owed, changed: [], always: ['walk-000'], minutes: 10, perWalkSeconds: 60 });
  check('the next check starts at the walk that was cut off', next.rotated[0] === 'walk-023' && next.walks.includes('walk-090'), next.walks);
  r = settleSlice(pick, answeredInLog(pick.walks.map((w) => `${w}   10s  ok`).join('\n')));
  check('a check that answered everything moves on to where the plan said', r.cursor === pick.nextCursor && r.complete && !r.owed.length, r);
  r = settleSlice(pick, null);
  check('with no log at all it trusts the plan, as before', r.cursor === pick.nextCursor, r);
  r = settleSlice(pick, new Set());
  check('a check that answered nothing leaves the cursor where it was', r.cursor === 20 && r.moved === 0, r);
  const wrap = { ...pickSlice({ walks: set, cursor: 97, changed: [], always: [], minutes: 10, perWalkSeconds: 60 }), from: 97 };
  r = settleSlice(wrap, new Set(['walk-097', 'walk-098', 'walk-099', 'walk-000']));
  check('a stop after the wrap lands past the wrap and counts the lap', r.cursor === 1 && r.lap === true, r);
  r = settleSlice(wrap, new Set(['walk-097']));
  check('a stop before the wrap does not count a lap', r.cursor === 98 && r.lap === false, r);
}

console.log('three checks in a row through a block of slow walks');
// The deadlock of 2026-11-20 to 11-22, replayed: walks 10 to 33 are Ask walks
// at 100 to 390s. Each check is run against a thirty minute clock by a stand-in
// runner that takes each walk's real time.
{
  const set = Array.from({ length: 200 }, (_, i) => `walk-${String(i).padStart(3, '0')}`);
  const own = {};
  const times = [146, 327, 179, 16, 154, 59, 70, 24, 283, 6, 260, 146, 178, 387, 219, 120, 100, 300, 390, 150, 210, 160, 100, 140];
  times.forEach((t, k) => { own[set[10 + k]] = t; });
  const always = ['walk-000', 'walk-001'];
  own['walk-000'] = 68; own['walk-001'] = 34;
  const cap = 1800;
  const run = (p) => {
    let t = 0; const lines = [];
    for (const w of [...p.walks].sort()) {
      const cost = own[w] || 20;
      if (t + cost > cap) { lines.push(w); return { log: lines.join('\n'), stopped: true, seconds: cap }; }
      t += cost; lines.push(`${w}  ${cost}s  ok`);
    }
    return { log: lines.join('\n'), stopped: false, seconds: t };
  };
  // Before: every walk at the 19.8s median, and a stop moves nothing.
  let cursor = 10; const before = [];
  for (let k = 0; k < 3; k++) {
    const p = pickSlice({ walks: set, cursor, changed: [], always, minutes: 10, perWalkSeconds: 19.8 });
    const o = run(p); before.push(o.stopped);
    if (!o.stopped) cursor = p.nextCursor;
  }
  check('replayed the old way, every check is stopped on the clock and the cursor never moves', before.every(Boolean) && cursor === 10, { before, cursor });
  cursor = 10; const starts = []; const stops = []; const took = [];
  for (let k = 0; k < 3; k++) {
    starts.push(cursor);
    const p = { ...pickSlice({ walks: set, cursor, changed: [], always, minutes: 10, perWalkSeconds: 19.8, walkSeconds: own }), from: cursor };
    const o = run(p); stops.push(o.stopped); took.push(o.seconds);
    cursor = settleSlice(p, answeredInLog(o.log)).cursor;
  }
  check('now each of three checks starts further on than the last', starts[0] < starts[1] && starts[1] < starts[2] && cursor > starts[2], { starts, cursor });
  check('...none is stopped on the clock', stops.every((x) => !x), stops);
  check('...and each ends inside about ten minutes', took.every((t) => t <= 600), took);
  // And if the times on record are wrong, a stop still moves the cursor.
  cursor = 10;
  const p = { ...pickSlice({ walks: set, cursor, changed: [], always, minutes: 30, perWalkSeconds: 19.8 }), from: cursor };
  const o = run(p);
  check('with times too low to trust, the check is stopped and still moves on past what it finished',
    o.stopped && settleSlice(p, answeredInLog(o.log)).cursor > 10, settleSlice(p, answeredInLog(o.log)));
}

console.log('a check that still owes walks');
check('a stopped check is due again after the floor with no new code',
  decide({ now, requests: [], latest: swept(2), head: 'same', codeSinceCheck: false, rotation: { cursor: 5, lastHead: 'same', cutShort: true } }).run === 'slice',
  decide({ now, requests: [], latest: swept(2), head: 'same', codeSinceCheck: false, rotation: { cursor: 5, lastHead: 'same', cutShort: true } }));
check('...and so is one that carried changed walks over',
  decide({ now, requests: [], latest: swept(2), head: 'same', rotation: { cursor: 5, lastHead: 'same', owed: ['walk-9'] } }).run === 'slice');
check('...and it says why',
  /owes 1 changed walk/.test(decide({ now, requests: [], latest: swept(2), head: 'same', rotation: { cursor: 5, lastHead: 'same', owed: ['walk-9'] } }).why));
check('...but not inside the four hour floor',
  decide({ now, requests: [], latest: swept(2), head: 'same', lastSliceEnded: ago(1), rotation: { cursor: 5, lastHead: 'same', cutShort: true } }).run === 'nothing');
check('...and not when a whole-set run has covered this code since',
  decide({ now, requests: [], latest: swept(1, { head: 'same' }), head: 'same', rotation: { cursor: 5, lastHead: 'same', cutShort: true } }).run === 'nothing');
check('a check that got through everything is not due again without new code',
  decide({ now, requests: [], latest: swept(2), head: 'same', rotation: { cursor: 5, lastHead: 'same', owed: [], cutShort: false } }).run === 'nothing');

console.log('each walk\'s own time, read off the sweep\'s logs');
{
  const d = mkdtempSync(join(tmpdir(), 'sweep-walk-times-'));
  try {
    const put = (f, text, t) => { writeFileSync(join(d, f), text); utimesSync(join(d, f), t, t); };
    put('2026-11-20-184435.log', 'ask-a-walk   300s  ok\nplain-walk   20s  ok\nold-walk   50s  ok\n', 1000);
    put('slice-2026-11-21-1.log', 'ask-a-walk   150s  ok\nplain-walk   18s  FAILED  step 2: no\n', 2000);
    put('slice-2026-11-22-1.log', 'ask-a-walk   160s  ok\nplain-walk    0s  DEFERRED  somebody is here\nask-b-walk  ', 3000);
    put('notes.txt', 'nope-walk   999s  ok\n', 4000);
    const w = walkSecondsFromLogs(d);
    check('a walk is costed at the larger of its last two answers', w['ask-a-walk'] === 160, w);
    check('...a deferral is not an answer about what it costs', w['plain-walk'] === 20, w);
    check('...a walk seen once keeps that time', w['old-walk'] === 50, w);
    check('...a walk cut off part way and files that are not logs give nothing', !('ask-b-walk' in w) && !('nope-walk' in w), w);
    check('no sweep folder is no times, not a crash', Object.keys(walkSecondsFromLogs(join(d, 'missing'))).length === 0);
  } finally { rmSync(d, { recursive: true, force: true }); }
}

console.log('how long a lap of the set takes, from the numbers');
{
  const set = Array.from({ length: 600 }, (_, i) => `w${i}`);
  const lap = lapEstimate({ walks: set, perWalkSeconds: 20, minutes: 10, always: [], sliceFloorHours: 4 });
  check('600 walks at 20s, thirty a check, is twenty checks', lap.checks === 20 && lap.perCheck === 30, lap);
  check('...and at six checks a day, a little over three days', Math.abs(lap.days - 20 / 6) < 0.01, lap);
  const slow = lapEstimate({ walks: set, perWalkSeconds: 20, walkSeconds: { w5: 2000 }, minutes: 10, always: [], sliceFloorHours: 4 });
  check('a walk longer than a check costs a check of its own, and the lap still ends', slow.checks > lap.checks && slow.checks < 30, slow);
}

console.log('the CLI moves rotation.json by what the log answered');
{
  const d = mkdtempSync(join(tmpdir(), 'sweep-advance-'));
  try {
    mkdirSync(join(d, 'sweep'), { recursive: true });
    const set = Array.from({ length: 50 }, (_, i) => `walk-${String(i).padStart(3, '0')}`);
    const pick = { ...pickSlice({ walks: set, cursor: 10, changed: ['walk-040'], always: [], minutes: 10, perWalkSeconds: 60 }), from: 10, of: 50, laps: 3, head: 'abc' };
    writeFileSync(join(d, 'pick.json'), JSON.stringify(pick));
    writeFileSync(join(d, 'run.log'), 'walk-010   61s  ok\nwalk-011   61s  ok\nwalk-012  \n');
    const script = join(dirname(fileURLToPath(import.meta.url)), 'sweep-schedule.mjs');
    const out = execFileSync('node', [script, '--advance', join(d, 'pick.json'), '--log', join(d, 'run.log')],
      { env: { ...process.env, PHOTONZ_QUEUE_DIR: d }, encoding: 'utf8' });
    const rot = JSON.parse(readFileSync(join(d, 'sweep', 'rotation.json'), 'utf8'));
    check('rotation.json moves to the first walk the check did not finish', rot.cursor === 12 && rot.lastHead === 'abc', rot);
    check('...owes the changed walk and says it was cut short', JSON.stringify(rot.owed) === '["walk-040"]' && rot.cutShort === true, rot);
    check('...and prints where it went', JSON.parse(out).to === 12 && JSON.parse(out).moved === 2, out);
    check('...and writes that back into the pick for the check\'s record', JSON.parse(readFileSync(join(d, 'pick.json'), 'utf8')).settled.to === 12);
  } finally { rmSync(d, { recursive: true, force: true }); }
}

console.log('on disk, moving the clock and HEAD through a real repo');
// The pure checks above take codeSince* as given. These make real commits and
// let the CLI's own reading of the disk work them out, so the path list and the
// git plumbing are drilled too, not only the arithmetic.
const repo = mkdtempSync(join(tmpdir(), 'sweep-schedule-drill-'));
try {
  const g = (...a) => execFileSync('git', a, { cwd: repo, encoding: 'utf8' }).trim();
  const put = (f, body) => { mkdirSync(join(repo, f, '..'), { recursive: true }); writeFileSync(join(repo, f), body); };
  const commit = (f, body, msg) => { put(f, body); g('add', '-A'); g('commit', '-q', '-m', msg); return g('rev-parse', 'HEAD'); };
  g('init', '-q'); g('config', 'user.email', 'drill@example.com'); g('config', 'user.name', 'drill');
  const dir = join(repo, 'queue', 'sweep');
  const base = commit('Sources/App/a.swift', '1', 'app');
  mkdirSync(dir, { recursive: true });
  const at = (h) => now + h * HOUR;
  // The whole set ran on `base` at hour 0 and its rotation sits there too.
  writeFileSync(join(dir, 'latest.json'), JSON.stringify({ began: new Date(now).toISOString(), head: base, complete: true }));
  writeFileSync(join(dir, 'rotation.json'), JSON.stringify({ cursor: 0, lastHead: base }));
  const step = (label, h, want, extra = {}) => {
    const d = decideFromDisk({ repo, dir, now: at(h), ...extra });
    console.log(`       hour ${String(h).padStart(2)} HEAD ${g('rev-parse', '--short', 'HEAD')}: ${d.run} (${d.why})`);
    check(label, d.run === want, d);
    return d;
  };
  step('hour 1, nothing new since the whole-set run: nothing', 1, 'nothing');
  commit('queue/tasks/x.json', '{}', 'queue: a task log');
  step('hour 2, a queue-only commit with no request: nothing', 2, 'nothing');
  commit('docs/notes.md', 'x', 'docs');
  commit('Tests/T.swift', 'x', 'tests');
  step('hour 3, docs and tests only: nothing', 3, 'nothing');
  const app = commit('Sources/App/a.swift', '2', 'app change');
  step('hour 4, app code landed with no request: the rotating check', 4, 'slice');
  check('codeLandedBetween sees it', codeLandedBetween(base, app, repo) === true);
  writeFileSync(join(dir, 'rotation.json'), JSON.stringify({ cursor: 50, lastHead: app }));
  step('hour 5, that check has run: nothing', 5, 'nothing');
  commit('queue/digest.md', 'x', 'queue: digest');
  step('hour 6, a queue-only commit after the check: still nothing', 6, 'nothing');
  commit('Scripts/playtest/new-walk.json', '{}', 'a walk changed');
  step('hour 7, a walk script changed with no request: the rotating check', 7, 'slice');
  writeFileSync(join(dir, 'requested.json'), JSON.stringify({ requests: [{ t: new Date(at(7)).toISOString(), by: 'a-task', why: 'it landed code' }] }));
  step('hour 7, a request pending inside the floor: still the rotating check, not the whole set', 7, 'slice');
  step('hour 25, a day on with code landed and a request pending: the whole set', 25, 'full');
  rmSync(join(dir, 'requested.json'));
  step('hour 25, the same with no request: the whole set all the same', 25, 'full');
  step('hour 25, locked, code landed: the lock-safe part of the set', 25, 'full', { screenLocked: true });
  const swept25 = g('rev-parse', 'HEAD');
  writeFileSync(join(dir, 'latest.json'), JSON.stringify({ began: new Date(at(25)).toISOString(), head: swept25, complete: true }));
  commit('queue/history.jsonl', 'x', 'queue: history');
  step('hour 50, a day on but only queue files since: nothing', 50, 'nothing');
  check('codeLandedBetween says no for queue-only', codeLandedBetween(swept25, g('rev-parse', 'HEAD'), repo) === false);
  check('codeLandedBetween counts an unreadable commit as different', codeLandedBetween('0'.repeat(40), swept25, repo) === true);
} finally {
  rmSync(repo, { recursive: true, force: true });
}

console.log('defaults');
check('the floor is three days (2026-11-05: the user, about five tasks done a day and a whole set at five to six hours)', DEFAULTS.floorHours === 72, DEFAULTS.floorHours);
check('a rotating check is budgeted at ten minutes', DEFAULTS.sliceMinutes === 10, DEFAULTS.sliceMinutes);

console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
