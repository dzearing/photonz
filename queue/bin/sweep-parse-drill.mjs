#!/usr/bin/env node
// Drill for what a sweep makes of the run it just watched.
//
// A sweep used to have two answers: it ran, or the screen was locked and it
// threw everything away. The second one was silence for three days straight
// (2026-09-15 to 2026-09-17), while about half the walk set was running under
// that lock perfectly well: a lock takes the NAME off a control, and half the
// walks never ask for one (PlaytestLockSafety). So there is a third answer now,
// a PARTIAL sweep: it ran the half it could, says so in numbers, and is never
// allowed to read as the state of the whole set.
//
// This drill holds the reading of the run log honest, because every downstream
// reader (the status line, the standing failing-walks task, the dashboard) is
// drawn from what this returns.
//
//   node queue/bin/sweep-parse-drill.mjs
import { parseSweepLog, sweepSentences } from './sweep-parse.mjs';

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};
const said = (r) => sweepSentences(r).join(' ');

// ---- 1. a sweep that ran the whole set --------------------------------------
console.log('a sweep that covered the set');
const FULL = `==> Building the probe bundle...
a-box-says-what-it-picks-walk               7s  ok
arrow-parts-walk                           11s  ok
pen-draws-a-path-walk                      14s  FAILED  no done.json

==> 2 passed, 1 failed
    pen-draws-a-path-walk
==> 3 walks in 0m 32s, 10s each on average; slowest pen-draws-a-path-walk at 14s
`;
let r = parseSweepLog(FULL, { total: 3 });
check('it counts what passed and what failed', r.passed === 2 && r.failed.length === 1, r);
check('it names the failing walk', r.failed[0] === 'pen-draws-a-path-walk', r.failed);
check('it is complete', r.complete === true, r);
check('it is not partial and not locked', r.partial === false && r.screenLocked === false, r);
check('nothing was refused', r.couldNotRun === 0, r);
r.ended = '2026-09-17T18:00:00Z'; r.seconds = 30;
check('and it says so with the stamps filled in',
  said(r) === 'Last sweep 2026-09-17T18:00:00Z: 2/3 walks passed in 30s.', said(r));

// ---- 2. the half a locked screen cannot touch -------------------------------
console.log('a sweep that ran the lock-safe half');
const PARTIAL = `==> Building the probe bundle...
a-box-says-what-it-picks-walk               7s  ok
a-notice-lets-a-click-through-walk          1s  COULD NOT RUN  it needs a control by name and the screen is locked
arrow-parts-walk                           11s  ok
first-run-walk                              9s  FAILED  expected the card
tutorial-mark-it-up-walk                    1s  COULD NOT RUN  it needs a control by name and the screen is locked

==> 2 walk(s) COULD NOT RUN: the Mac's screen is locked.
    The app keeps drawing, animating, taking the walk's clicks and being photographed.
    Unlock the screen to run the rest.
==> 2 passed, 1 failed, 2 could not run
    first-run-walk
==> 3 walks in 0m 27s, 9s each on average; slowest arrow-parts-walk at 11s
`;
r = parseSweepLog(PARTIAL, { total: 5 });
r.ended = '2026-09-17T18:00:00Z'; r.seconds = 27;
check('the walks that ran are counted', r.walks === 3 && r.passed === 2, r);
check('the refused ones are counted apart', r.couldNotRun === 2, r);
check('a walk that FAILED in the half that ran is named', r.failed.join() === 'first-run-walk', r.failed);
check('"Unlock the screen to run the rest" is not read as a walk name',
  !r.failed.some((w) => /unlock/i.test(w)), r.failed);
check('it says the screen was locked', r.screenLocked === true, r);
check('it says it is partial', r.partial === true, r);
check('it is NOT complete: a part of the set is not the set', r.complete === false, r);
check('it remembers how big the whole set is', r.total === 5, r);
let s = said(r);
check('it says which walks actually ran',
  r.ranWalks.join() === 'a-box-says-what-it-picks-walk,arrow-parts-walk,first-run-walk', r.ranWalks);
check('...and which the lock refused',
  r.refusedWalks.join() === 'a-notice-lets-a-click-through-walk,tutorial-mark-it-up-walk', r.refusedWalks);
check('the sentence says how many ran of how many', /3 of 5/.test(s), s);
check('it says how many were refused and why', /2 .*refused|refused .*2/.test(s) && /locked/.test(s), s);
check('it says out loud that this is part of the set', /part of the (walk )?set/.test(s), s);
check('it says a full sweep is still owed', /still owed|once the screen is unlocked/.test(s), s);
check('it never claims to be the state of the set', !/^Last sweep \S+: \d+\/\d+ walks passed/.test(s), s);
check('no em dash', !/—/.test(s), s);

// ---- 3. locked, and not one walk got through --------------------------------
console.log('a sweep where every walk was refused');
const NONE = `==> Building the probe bundle...
a-notice-lets-a-click-through-walk          1s  COULD NOT RUN  it needs a control by name and the screen is locked
tutorial-mark-it-up-walk                    1s  COULD NOT RUN  it needs a control by name and the screen is locked

==> 2 walk(s) COULD NOT RUN: the Mac's screen is locked.
    Unlock the screen to run the rest.
`;
r = parseSweepLog(NONE, { total: 2 });
r.ended = '2026-09-17T18:00:00Z'; r.seconds = 15;
check('nothing ran', r.walks === 0 && r.passed === 0, r);
check('everything was refused', r.couldNotRun === 2, r);
check('it is locked but not partial: there is no part to report', r.screenLocked === true && r.partial === false, r);
s = said(r);
check('it says the screen was locked and nothing ran', /locked/.test(s) && /COULD NOT RUN|could not run/.test(s), s);

// ---- 4. stopped on the clock ------------------------------------------------
console.log('a sweep stopped on the clock');
const CUT = `==> Building the probe bundle...
a-box-says-what-it-picks-walk               7s  ok
arrow-parts-walk                          180s  FAILED  no done.json
`;
r = parseSweepLog(CUT, { total: 322, timedOut: true });
r.ended = '2026-09-17T18:00:00Z'; r.seconds = 7200;
check('it reads the walks it reached', r.walks === 2 && r.passed === 1, r);
check('it names the failure it saw', r.failed.join() === 'arrow-parts-walk', r.failed);
check('it is incomplete and says it was stopped on the clock', r.complete === false && r.timedOut === true, r);
check('it is not dressed as a lock', r.screenLocked === false && r.partial === false, r);
s = said(r);
check('the cut-short wording is unchanged', /DID NOT FINISH \(stopped on the clock\)/.test(s), s);

console.log(failures ? '\n' + failures + ' FAILED' : '\nall good');
process.exit(failures ? 1 : 0);
