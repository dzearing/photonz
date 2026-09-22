#!/usr/bin/env node
// Drill for a sweep that GOES BLIND: the app stops launching part way through,
// so every walk after that point is put in front of nothing.
//
// This is the run of 2026-09-21 18:47. It answered 117 walks normally, then the
// probe stopped coming up and the remaining 436 each came back in 0s with "no
// done.json". The sweep wrote that down as 438 failing walks out of 553, it
// replaced a record that had passed 537 of 544 that same morning, and for the
// next day `sweep.sh status` told every runner the app was broken in 438 ways.
// Four of the names were spot-checked and passed in about 20s each.
//
// What this holds true:
//
//   - a walk nothing ran is UNANSWERED: out of the failing list, out of the
//     counts, and never named as broken anywhere;
//   - one walk that cannot get the app up is still a flake and still a failure,
//     so a real break is not swallowed by the same machinery;
//   - a blind run is not written over latest.json, so the last run that really
//     covered the set stays the record and the twelve-hour floor does not get
//     reset by a run that saw nothing;
//   - the request that asked for the sweep is handed back, because a sweep is
//     still owed.
//
//   node queue/bin/sweep-blind-drill.mjs
import { mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { parseSweepLog, sweepSentences, BLIND_AFTER } from './sweep-parse.mjs';
import { recordSweep } from './sweep-record.mjs';

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};
const said = (r) => sweepSentences(r).join(' ');

// A run log in the shape playtest-all.sh writes: `head` walks that answered,
// then `blind` walks that found no app, in whichever of the two wordings.
function runLog({ ok = 3, realFailures = [], blind = 0, wording = 'old', summary = true } = {}) {
  const lines = ['==> Building the probe bundle...'];
  const pad = (n) => n.padEnd(40, ' ');
  for (let i = 0; i < ok; i++) lines.push(`${pad('good-walk-' + i)}   9s  ok`);
  for (const f of realFailures) lines.push(`${pad(f)}   8s  FAILED  step 12 (press): no control called "Blur"`);
  for (let i = 0; i < blind; i++) {
    lines.push(wording === 'old'
      ? `${pad('dark-walk-' + i)}   0s  FAILED  no done.json`
      : `${pad('dark-walk-' + i)}   0s  COULD NOT START  the probe would not launch, so nothing ran this walk`);
  }
  if (summary) {
    const failedNames = wording === 'old'
      ? realFailures.concat([...Array(blind).keys()].map((i) => 'dark-walk-' + i))
      : realFailures;
    lines.push('');
    if (wording === 'new' && blind) {
      lines.push(`==> ${blind} walk(s) COULD NOT START: the probe would not launch, beginning at dark-walk-0.`);
      lines.push('    Nothing ran them, so they are not a pass and not a failure. They are unknown.');
    }
    let counts = `==> ${ok} passed, ${failedNames.length} failed`;
    if (wording === 'new' && blind) counts += `, ${blind} could not start`;
    lines.push(counts);
    for (const n of failedNames) lines.push('    ' + n);
    lines.push(`==> ${ok + failedNames.length} walks in 25m 29s, 2s each on average; slowest good-walk-0 at 9s`);
  }
  return lines.join('\n') + '\n';
}

// ---- 1. the shape that started it: a long run of "no done.json" -------------
console.log('a run whose app stopped launching, in the old wording');
let r = parseSweepLog(runLog({ ok: 115, realFailures: ['copy-own-color-walk', 'delete-key-drops-a-piece-walk'], blind: 436 }), { total: 553 });
check('it is called blind', Boolean(r.blind), r.blind);
check('and says where the app went away', r.blind && r.blind.from === 'dark-walk-0', r.blind);
check('and how many walks that cost', r.blind && r.blind.count === 436, r.blind);
check('THE POINT: not one of them is named as a failing walk',
  r.failed.length === 2 && !r.failed.some((n) => n.startsWith('dark-walk')), r.failed);
check('the two that really failed are still named',
  r.failed.includes('copy-own-color-walk') && r.failed.includes('delete-key-drops-a-piece-walk'), r.failed);
check('the walk count is what it answered, not what it printed a line for', r.walks === 117, r.walks);
check('the set size it was measured against survives', r.total === 553, r.total);
check('it is NOT complete: a run with a hole in it is not the state of the set', r.complete === false, r.complete);
check('the blind walks are not counted as having run', r.ranWalks.length === 117, r.ranWalks.length);
check('and they are carried by name, so what went unanswered is knowable',
  r.blindWalks.length === 436 && r.blindWalks[0] === 'dark-walk-0', r.blindWalks.length);
r.ended = '2026-09-22T02:13:14Z'; r.seconds = 1533;
check('the first sentence says the app stopped launching, because it is the only one the loop reads',
  /WENT BLIND: the app stopped launching at dark-walk-0/.test(sweepSentences(r)[0]), sweepSentences(r)[0]);
check('it says plainly they are not failing', /not failing: nothing was there to fail/.test(said(r)), said(r));
check('and that the last real sweep stays the record', /stays the record/.test(said(r)), said(r));
check('what it did answer is still reported', /115 passed, 2 failed/.test(said(r)), said(r));

// ---- 2. the same thing in the wording playtest-all writes now ---------------
console.log('a run whose app stopped launching, in the wording it says now');
r = parseSweepLog(runLog({ ok: 20, realFailures: [], blind: 30, wording: 'new' }), { total: 50 });
check('a COULD NOT START walk is read the same way', Boolean(r.blind) && r.blind.count === 30, r.blind);
check('nothing is failing', r.failed.length === 0, r.failed);
check('and it counts only what answered', r.walks === 20 && r.passed === 20, r);
check('the summary line still parses with the new count on the end', r.total === 50, r.total);

// ---- 3. one flake is still a failure ----------------------------------------
console.log('one walk that could not get the app up');
for (let n = 1; n < BLIND_AFTER; n++) {
  r = parseSweepLog(runLog({ ok: 10, blind: n }), { total: 10 + n });
  check(`${n} in a row is a flake, not blindness`, r.blind === null, r.blind);
  check(`  ...and stays in the failing list, so a real break is not swallowed`,
    r.failed.length === n, r.failed);
}
r = parseSweepLog(runLog({ ok: 10, blind: BLIND_AFTER }), { total: 10 + BLIND_AFTER });
check(`${BLIND_AFTER} in a row is blindness`, Boolean(r.blind) && r.failed.length === 0, r);

// ---- 4. a run that went blind and then came back ----------------------------
console.log('a run that lost the app and got it back');
const RECOVERED = `==> Building the probe bundle...
${'alpha-walk'.padEnd(40)}   9s  ok
${'dark-walk-0'.padEnd(40)}   0s  FAILED  no done.json
${'dark-walk-1'.padEnd(40)}   0s  FAILED  no done.json
${'dark-walk-2'.padEnd(40)}   0s  FAILED  no done.json
${'dark-walk-3'.padEnd(40)}   0s  FAILED  no done.json
${'dark-walk-4'.padEnd(40)}   0s  FAILED  no done.json
${'beta-walk'.padEnd(40)}  11s  ok
${'gamma-walk'.padEnd(40)}   7s  FAILED  step 3 (press): no control called "Blur"

==> 3 passed, 6 failed
    dark-walk-0
    dark-walk-1
    dark-walk-2
    dark-walk-3
    dark-walk-4
    gamma-walk
==> 9 walks in 1m 00s, 6s each on average; slowest beta-walk at 11s
`;
r = parseSweepLog(RECOVERED, { total: 9 });
check('the hole is still a hole even though the app came back', Boolean(r.blind) && r.blind.count === 5, r.blind);
check('the walk that really failed afterwards is still named', r.failed.join() === 'gamma-walk', r.failed);
check('and the run is still not the state of the set', r.complete === false, r.complete);

// ---- 5. a clean run is untouched --------------------------------------------
console.log('a run where the app was there the whole time');
r = parseSweepLog(runLog({ ok: 540, realFailures: ['one-walk', 'two-walk'] }), { total: 542 });
check('nothing is called blind', r.blind === null, r.blind);
check('it is complete', r.complete === true, r.complete);
check('and it says the sentence it always said', /^Last sweep .*: 540\/542 walks passed/.test(sweepSentences({ ...r, ended: 'now', seconds: 60 })[0]),
  sweepSentences({ ...r, ended: 'now', seconds: 60 })[0]);

// ---- 6. what gets written down ----------------------------------------------
console.log('what a blind run leaves behind');
const dir = mkdtempSync(join(tmpdir(), 'photonz-blind-drill-'));
const at = (n) => join(dir, n);
const GOOD = {
  began: '2026-09-21T06:47:03Z', ended: '2026-09-21T08:39:53Z', seconds: 6770,
  walks: 544, passed: 537, failed: ['a-walk'], couldNotRun: 0, total: 544, complete: true,
};
writeFileSync(at('latest.json'), JSON.stringify(GOOD, null, 2) + '\n');
writeFileSync(at('.claimed.json'), JSON.stringify({ requests: [{ t: '2026-09-21T10:00:00Z', by: 'a task runner', why: 'the modes chip landed' }] }) + '\n');
writeFileSync(at('requested.json'), JSON.stringify({ requests: [] }) + '\n');

const out = recordSweep({
  logText: runLog({ ok: 115, realFailures: ['copy-own-color-walk'], blind: 436 }),
  latest: at('latest.json'), claimed: at('.claimed.json'), req: at('requested.json'),
  began: '2026-09-21T18:47:41Z', ended: '2026-09-22T02:13:14Z', seconds: 1533,
  runlogRel: 'queue/sweep/2026-09-21-184741.log', total: 553, head: 'deadbeef',
});
check('it says it went blind', out.blind === true, out.blind);
check('it is NOT recorded as the state of the walk set', out.recorded === false, out.recorded);
const stillThere = JSON.parse(readFileSync(at('latest.json'), 'utf8'));
check('THE POINT: the last run that really covered the set is untouched',
  stillThere.ended === GOOD.ended && stillThere.passed === 537, stillThere.ended);
check('so the twelve-hour floor is still counted from a run that could see', stillThere.began === GOOD.began, stillThere.began);
check('the blind run is written down all the same', existsSync(at('blind.json')));
const blindRec = JSON.parse(readFileSync(at('blind.json'), 'utf8'));
check('naming what it answered before it went dark', blindRec.walks === 116 && blindRec.passed === 115, blindRec.walks);
check('and the one walk that really failed', blindRec.failed.join() === 'copy-own-color-walk', blindRec.failed);
check('and never naming a blind walk as failing',
  !blindRec.failed.some((n) => n.startsWith('dark-walk')), blindRec.failed);
check('and carrying which run log it came out of', blindRec.log === 'queue/sweep/2026-09-21-184741.log', blindRec.log);
check('the request that asked for a sweep is handed back, because one is still owed',
  JSON.parse(readFileSync(at('requested.json'), 'utf8')).requests.length === 1, out.handedBack);

// A run that could see writes latest.json exactly as it always did.
writeFileSync(at('.claimed.json'), JSON.stringify({ requests: [] }) + '\n');
const clean = recordSweep({
  logText: runLog({ ok: 540, realFailures: ['one-walk'] }),
  latest: at('latest.json'), claimed: at('.claimed.json'), req: at('requested.json'),
  began: '2026-09-22T09:00:00Z', ended: '2026-09-22T11:00:00Z', seconds: 7200,
  runlogRel: 'queue/sweep/x.log', total: 541, head: 'cafe',
});
check('a run that could see is recorded as it always was', clean.recorded === true && clean.blind === false, clean.recorded);
check('  ...over the top of the old one', JSON.parse(readFileSync(at('latest.json'), 'utf8')).passed === 540);

// ---- 7. end to end: what a runner asking sweep.sh status is told -------------
console.log('what sweep.sh status says after a run went blind');
const qdir = mkdtempSync(join(tmpdir(), 'photonz-blind-queue-'));
const sdir = join(qdir, 'sweep');
execFileSync('mkdir', ['-p', sdir]);
writeFileSync(join(sdir, 'latest.json'), JSON.stringify(GOOD, null, 2) + '\n');
writeFileSync(join(sdir, 'blind.json'), JSON.stringify({ ...blindRec, ended: '2026-09-22T02:13:14Z' }, null, 2) + '\n');
let status = '';
try {
  status = execFileSync('queue/bin/sweep.sh', ['status'], {
    env: { ...process.env, PHOTONZ_QUEUE_DIR: qdir }, encoding: 'utf8',
  });
} catch (e) { status = String(e.stdout || '') + String(e.stderr || ''); }
check('it leads with the app having stopped launching', /THE APP STOPPED LAUNCHING/.test(status), status.split('\n')[0]);
check('it names no blind walk as failing',
  !status.split('\n').some((l) => /^Failing/.test(l) && /dark-walk/.test(l)), status);
check('it still reports the last run that really covered the set',
  /Last sweep 2026-09-21T08:39:53Z: 537\/544 walks passed/.test(status), status);

// The one JSON line the loop writes into history.jsonl after every run. A blind
// run leaves latest.json alone, so without this the loop would have recorded
// the PREVIOUS sweep's counts a second time, as a fresh answer for code that
// had in fact stopped launching.
const sweepJson = (args) => {
  try {
    return JSON.parse(execFileSync('queue/bin/sweep.sh', args, {
      env: { ...process.env, PHOTONZ_QUEUE_DIR: qdir }, encoding: 'utf8',
    }));
  } catch (e) { return { error: String(e) }; }
};
let sum = sweepJson(['summary']);
check('the event the loop records says the run went blind', sum.blind === true, sum);
check('and carries the last real sweep\'s numbers nowhere near it',
  sum.passed === 115 && sum.complete === false, sum);

// A blind run OLDER than the last real sweep has been answered by that sweep
// and is not news any more.
writeFileSync(join(sdir, 'blind.json'), JSON.stringify({ ...blindRec, ended: '2026-09-20T00:00:00Z' }, null, 2) + '\n');
try {
  status = execFileSync('queue/bin/sweep.sh', ['status'], {
    env: { ...process.env, PHOTONZ_QUEUE_DIR: qdir }, encoding: 'utf8',
  });
} catch (e) { status = String(e.stdout || '') + String(e.stderr || ''); }
check('a blind run older than the last real sweep is not brought up again',
  !/THE APP STOPPED LAUNCHING/.test(status), status);
sum = sweepJson(['summary']);
check('  ...and the event goes back to being about the last real sweep',
  sum.blind === undefined && sum.passed === 537 && sum.complete === true, sum);

// ---- 8. the rotating check, which reads the same log ------------------------
// A ten-minute check between tasks writes what it found onto the standing walk
// task. It goes through the same reader, so it must not write down a walk the
// app was never there for either.
console.log('a rotating check that lost the app');
const cdir = mkdtempSync(join(tmpdir(), 'photonz-blind-slice-'));
execFileSync('mkdir', ['-p', join(cdir, 'tasks', 'p2-normal')]);
const runlog = join(cdir, 'run.log');
writeFileSync(runlog, runLog({ ok: 6, realFailures: ['real-break-walk'], blind: 40 }));
writeFileSync(join(cdir, 'pick.json'), JSON.stringify({ changed: [], from: 0, nextCursor: 47 }));
const sliceOut = execFileSync('queue/bin/sweep-slice-record.mjs', [
  runlog, join(cdir, 'last-slice.json'),
  '2026-09-22T09:00:00Z', '2026-09-22T09:10:00Z', '600', '47', '559', join(cdir, 'pick.json'), '0',
], { env: { ...process.env, PHOTONZ_QUEUE_DIR: cdir }, encoding: 'utf8' });
check('it says the app stopped launching', /WENT BLIND/.test(sliceOut), sliceOut);
check('THE POINT: it does not write 40 walks onto the standing task',
  !/dark-walk/.test(sliceOut.split('\n').filter((l) => /failing/.test(l)).join(' ')), sliceOut);
check('the real break it did find is still named', /real-break-walk/.test(sliceOut), sliceOut);
const sliceRec = JSON.parse(readFileSync(join(cdir, 'last-slice.json'), 'utf8'));
check('and the record carries the blindness', sliceRec.blind && sliceRec.blind.count === 40, sliceRec.blind);

// A crashed walk is named, not printed as an object. r.crashed holds
// {name, why}, and spreading it straight into the failing line put
// "[object Object]" on the standing walk task.
writeFileSync(runlog, [
  'alpha-walk'.padEnd(40) + '   9s  ok',
  'boom-walk'.padEnd(40) + '   4s  CRASHED  EXC_CRASH (SIGABRT) in EditorState.document.getter',
  '',
  '==> 1 passed, 0 failed, 1 crashed',
  '    boom-walk',
  '==> 2 walks in 0m 13s',
  '',
].join('\n'));
const crashOut = execFileSync('queue/bin/sweep-slice-record.mjs', [
  runlog, join(cdir, 'last-slice.json'),
  '2026-09-22T09:00:00Z', '2026-09-22T09:10:00Z', '600', '2', '559', join(cdir, 'pick.json'), '0',
], { env: { ...process.env, PHOTONZ_QUEUE_DIR: cdir }, encoding: 'utf8' });
check('a crashed walk is named by its name', /boom-walk/.test(crashOut), crashOut);
check('and never as [object Object]', !/\[object Object\]/.test(crashOut), crashOut);

rmSync(cdir, { recursive: true, force: true });
rmSync(dir, { recursive: true, force: true });
rmSync(qdir, { recursive: true, force: true });

console.log(failures ? '\n' + failures + ' FAILED' : '\nall good');
process.exit(failures ? 1 : 0);
