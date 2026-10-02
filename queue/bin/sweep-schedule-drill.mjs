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
import { decide, pickSlice, DEFAULTS, decideFromDisk, codeLandedBetween, WALK_PATHS } from './sweep-schedule.mjs';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';

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
check('the floor is a day (2026-09-26: walks took the user\'s Mac away)', DEFAULTS.floorHours === 24, DEFAULTS.floorHours);
check('a rotating check is budgeted at ten minutes', DEFAULTS.sliceMinutes === 10, DEFAULTS.sliceMinutes);

console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
