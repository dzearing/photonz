#!/usr/bin/env node
// Drill for the one line the dashboard says about the walk sweep.
//
// The walks are the only check that tells the loop whether what it just built
// broke the app, and they cannot run at all while the Mac's screen is locked:
// a walk finds every control by its name and a locked screen takes the names
// away (Sources/Photonz/Playtest/PlaytestScreenState.swift). sweep.sh has always
// recorded that honestly as screenLocked, but queue-lib dropped the flag and
// the page rendered "walk sweep cut short at 0 walks", which is the wording for
// a sweep that ran out of time. The Mac locked on 2026-09-15 and two days of
// work shipped before anybody read the dashboard as anything but a slow sweep.
//
// So this holds both halves honest at once:
//   1. sweepState carries screenLocked through, and says how long the run of
//      locked sweeps has been going
//   2. the hero line names the lock, the waiting count and the age, and the
//      strip under it says what to do
//   3. with the screen unlocked the line is word for word what it always was
//
// The wording half runs the REAL functions out of dashboard.html rather than a
// copy of them, so a reworded line that stops naming the lock fails here.
//
//   node queue/bin/sweep-line-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const dir = mkdtempSync(join(tmpdir(), 'photonz-sweep-line-'));
process.env.PHOTONZ_QUEUE_DIR = dir;
mkdirSync(join(dir, 'sweep'), { recursive: true });
for (const p of ['p0-critical', 'p1-high', 'p2-normal', 'p3-low']) mkdirSync(join(dir, 'tasks', p), { recursive: true });

const lib = await import('./queue-lib.mjs');

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

// One fixed now, so a stamp written and a stamp expected are the same string
// rather than two reads of the clock a millisecond apart.
const NOW = Date.now();
const ago = (ms) => new Date(NOW - ms).toISOString();
const HOUR = 3600 * 1000, DAY = 24 * HOUR;

const putLatest = (o) => writeFileSync(join(dir, 'sweep', 'latest.json'), JSON.stringify(o, null, 2));
const putRequests = (rs) => writeFileSync(join(dir, 'sweep', 'requested.json'), JSON.stringify({ requests: rs }, null, 2));
const putHistory = (evs) => writeFileSync(join(dir, 'history.jsonl'), evs.map((e) => JSON.stringify(e)).join('\n') + '\n');
const pass = (t, extra = {}) => ({ t, ev: 'sweep_pass', walks: 322, passed: 322, failed: 0, seconds: 3000, complete: true, ...extra });
const lockedPass = (t) => ({ t, ev: 'sweep_pass', walks: 0, passed: 0, failed: 0, seconds: 15, complete: false, screenLocked: true });

// ---- 1. the state the page is drawn from ------------------------------------
console.log('what queue.mjs state says about a locked sweep');

putRequests([{ t: ago(2 * DAY), by: 'some-task', why: 'rewrote nine walks' }, { t: ago(HOUR), by: 'other-task', why: 'and nine more' }]);
putHistory([
  pass(ago(3 * DAY)),
  lockedPass(ago(2 * DAY)),        // the lock starts here
  lockedPass(ago(HOUR)),
  lockedPass(ago(5 * 60 * 1000)),
]);
putLatest({ began: ago(5 * 60 * 1000), ended: ago(5 * 60 * 1000), seconds: 15, walks: 0, passed: 0, failed: [], complete: false, timedOut: false, screenLocked: true });

let W = lib.sweepState();
check('the locked sweep says it was locked, not merely incomplete', W.last.screenLocked === true, W.last);
check('it still reports walks: 0, so nothing claims to have been checked', W.last.walks === 0 && W.last.passed === 0, W.last);
check('blindSince is the FIRST of the unbroken run of locked sweeps', W.blindSince === ago(2 * DAY), { blindSince: W.blindSince });
check('the waiting requests are still counted', W.pending === 2, W.pending);
check('the oldest request is the one to quote', W.oldestRequest === ago(2 * DAY), W.oldestRequest);

// A sweep that ran before the lock must not drag the start of the run back with
// it: the run begins at the first locked sweep after the last one that ran.
putHistory([lockedPass(ago(9 * DAY)), pass(ago(3 * DAY)), lockedPass(ago(2 * DAY)), lockedPass(ago(HOUR))]);
check('a locked sweep from before the last real one is not part of this run',
  lib.sweepState().blindSince === ago(2 * DAY), lib.sweepState().blindSince);

// Nothing recorded yet: the locked sweep itself is the floor, never null.
putHistory([]);
check('with no recorded sweeps the locked run starts at the sweep itself',
  lib.sweepState().blindSince === ago(5 * 60 * 1000), lib.sweepState().blindSince);

console.log('what it says when the screen is not the problem');
putHistory([pass(ago(2 * HOUR))]);
putLatest({ began: ago(2 * HOUR), ended: ago(2 * HOUR), seconds: 2900, walks: 322, passed: 319, failed: ['a-walk', 'b-walk', 'c-walk'], complete: true, timedOut: false });
W = lib.sweepState();
check('a sweep that ran is not locked', W.last.screenLocked === false, W.last);
check('and nothing claims the loop is blind', W.blindSince === null, W.blindSince);
check('failures are still counted', W.last.failed === 3 && W.last.passed === 319, W.last);

putLatest({ began: ago(2 * HOUR), ended: ago(HOUR), seconds: 3600, walks: 140, passed: 140, failed: [], complete: false, timedOut: true });
W = lib.sweepState();
check('a sweep that ran out of time is incomplete but not locked', W.last.complete === false && W.last.screenLocked === false, W.last);
check('and it is not called blind either', W.blindSince === null, W.blindSince);

// ---- 2. the wording, out of the real page -----------------------------------
// Pull the actual functions out of dashboard.html so this fails if the line is
// reworded into something that stops naming the lock.
const page = readFileSync(join(REPO, 'docs/design/mocks/pages/dashboard.html'), 'utf8');
function fn(name) {
  const at = page.indexOf('function ' + name + '(');
  if (at < 0) throw new Error('dashboard.html no longer defines ' + name + '()');
  let i = page.indexOf('{', at), depth = 0;
  for (let j = i; j < page.length; j++) {
    if (page[j] === '{') depth++;
    else if (page[j] === '}' && --depth === 0) return page.slice(at, j + 1);
  }
  throw new Error('could not read the body of ' + name + '()');
}
const src = ['esc', 'rel', 'span', 'sweepLine', 'blindStrip'].map(fn).join('\n');
const page_ = new Function('S', src + '\nreturn { sweepLine: sweepLine, blindStrip: blindStrip };');
const render = (sweep) => page_({ sweep });
const text = (html) => html.replace(/<[^>]*>/g, ' ').replace(/&#8217;|&rsquo;/g, '’').replace(/\s+/g, ' ').trim();

console.log('the line under the heartbeat, screen locked');
let R = render({ pending: 83, oldestRequest: ago(2 * DAY), blindSince: ago(2 * DAY), last: { ended: ago(5 * 60 * 1000), walks: 0, passed: 0, failed: 0, complete: false, screenLocked: true } });
let line = text(R.sweepLine());
check('it says the screen is locked', /screen is locked/.test(line), line);
check('it never says the sweep was cut short', !/cut short/.test(line), line);
check('it says how long it has been true', /2 days/.test(line), line);
check('it says how many sweeps are waiting', /83 waiting/.test(line), line);
check('it is one line, short enough for the corner it sits in', line.length < 80, line.length);
check('it is coloured as a problem, not as a slow sweep', /db-sweep blind/.test(R.sweepLine()), R.sweepLine());

let strip = text(R.blindStrip());
check('the strip under the hero names the lock', /screen is locked/.test(strip), strip);
check('the strip says what to do about it', /[Uu]nlock the Mac/.test(strip), strip);
check('the strip says how long, and how many are waiting', /2 days/.test(strip) && /83 sweeps are waiting/.test(strip), strip);
check('the strip says nothing since has been checked', /nothing built since has been checked/.test(strip), strip);
// The page only knows what the last ATTEMPT found, so it has to say when that
// was: otherwise an unlocked Mac with nothing waiting reads as locked forever.
check('the strip bounds the claim to the last try', /The last try was 5m ago/.test(strip), strip);
check('no em dash in any of it', !/—/.test(strip + line), strip + line);

// One waiting sweep reads as one sweep.
R = render({ pending: 1, oldestRequest: ago(3 * HOUR), blindSince: ago(3 * HOUR), last: { ended: ago(60000), walks: 0, passed: 0, failed: 0, complete: false, screenLocked: true } });
check('one waiting sweep is singular', /1 sweep is waiting/.test(text(R.blindStrip())), text(R.blindStrip()));
check('and the age reads in hours', /for 3 hours/.test(text(R.blindStrip())), text(R.blindStrip()));

// Locked with nothing waiting still says the whole-app check is not running.
R = render({ pending: 0, oldestRequest: null, blindSince: ago(2 * DAY), last: { ended: ago(60000), walks: 0, passed: 0, failed: 0, complete: false, screenLocked: true } });
check('with no requests waiting it still names the lock', /screen is locked/.test(text(R.sweepLine())), text(R.sweepLine()));
check('and does not claim sweeps are waiting', !/waiting/.test(text(R.sweepLine())), text(R.sweepLine()));

console.log('the line under the heartbeat, screen unlocked');
R = render({ pending: 0, oldestRequest: null, blindSince: null, last: { ended: ago(2 * HOUR), walks: 322, passed: 319, failed: 3, complete: true, screenLocked: false } });
check('a sweep that ran reads exactly as it always did', text(R.sweepLine()) === 'walk sweep 319/322 2h ago · 3 failing', text(R.sweepLine()));
check('and there is no strip', R.blindStrip() === '', R.blindStrip());

R = render({ pending: 4, oldestRequest: ago(HOUR), blindSince: null, last: { ended: ago(HOUR), walks: 140, passed: 140, failed: 0, complete: false, screenLocked: false } });
check('a sweep that ran out of time still reads as cut short', text(R.sweepLine()) === 'walk sweep cut short at 140 walks 1h ago · 4 more asked for', text(R.sweepLine()));
check('and it is not dressed as a lock', !/db-sweep blind/.test(R.sweepLine()), R.sweepLine());

R = render({ pending: 2, oldestRequest: ago(DAY), blindSince: null, last: null });
check('no sweep ever run still reads as it did', text(R.sweepLine()) === 'walk sweep: 2 asked for since 1d ago, none run yet', text(R.sweepLine()));

rmSync(dir, { recursive: true, force: true });
console.log(failures ? '\n' + failures + ' FAILED' : '\nall good');
process.exit(failures ? 1 : 0);
