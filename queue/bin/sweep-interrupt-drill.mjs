#!/usr/bin/env node
// Drill: a sweep that is cut short still counts, and the ask for it survives.
//
// On 2026-09-18 the loop started a sweep at 14:43Z, got through 126 walks, and
// was killed at about 15:09Z. Everything about the run was written down only
// at the END, and the requests it was serving had been claimed at the START,
// so when the loop came back a day later:
//
//   queue/sweep/requested.json      gone: nobody was asking for a sweep
//   queue/sweep/latest.json         the sweep BEFORE it, against an older commit
//   126 walk answers, one failing   thrown away
//
// and sweep.sh status said, truthfully, that no sweep was pending. The commit
// that had landed that morning was never checked and nothing was going to
// check it.
//
// This holds both halves honest, end to end, with no app and no probe: a fake
// run log and a fake claim stand in for the killed run, and the real
// sweep-recover.mjs, sweep-record.mjs and sweep-report.mjs do the work.
//
//   node queue/bin/sweep-interrupt-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { execFileSync, spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSweepLog, sweepSentences } from './sweep-parse.mjs';
import { recordSweep } from './sweep-record.mjs';
import { machineBlock, previousFailures } from './sweep-notes.mjs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

// A run log that stops mid-line, exactly as a killed playtest-all.sh leaves
// one: playtest-all prints the walk name padded to forty columns and only
// fills in the verdict when the walk is over.
const KILLED = 'a-box-says-what-it-picks-walk               7s  ok\n'
  + 'arrow-parts-walk                           11s  ok\n'
  + 'measure-chip-snap-walk                      1s  FAILED  no done.json\n'
  + 'measure-handback                        ';
const NOTHING = '==> Building the probe bundle...\n==> Build failed.\n';
const LOCKED_OUT = '==> Building the probe bundle...\n'
  + 'a-notice-lets-a-click-through-walk          1s  COULD NOT RUN  it needs a control by name and the screen is locked\n'
  + 'align-layers-walk                           0s  COULD NOT RUN  it needs a control by name and the screen is locked\n';

// ---- 1. reading a killed run's log ------------------------------------------
console.log('the log a killed run leaves behind');
let r = parseSweepLog(KILLED, { total: 532, interrupted: true });
check('the walks it did answer are counted', r.walks === 3 && r.passed === 2, r);
check('the one that failed is named', r.failed.join() === 'measure-chip-snap-walk', r.failed);
check('it is not complete', r.complete === false, r.complete);
check('it says it was interrupted, not that it ran out of clock',
  r.interrupted === true && r.timedOut === false, r);
check('the walk that was still running is named, so it is not read as a pass',
  r.unfinished === 'measure-handback', r.unfinished);
check('and that walk is in neither the pass list nor the fail list',
  !r.ranWalks.includes('measure-handback') && !r.failed.includes('measure-handback'), r.ranWalks);
r.ended = '2026-09-18T15:09:00Z'; r.seconds = 1550;
let said = sweepSentences(r).join(' ');
check('it says how much of the set it covered', /reached 3 of 532 walks/.test(said), said);
check('it says WHY it stopped', /whoever was running it went away/.test(said), said);
check('and that its failures are not confirmed', /UNCONFIRMED/.test(said), said);
check('and that the request is pending again', /pending again/.test(said), said);

// A NARROWED run (PHOTONZ_SWEEP_ARGS, a handful of walks on purpose) has no
// set size to count itself against. Inferring one from what it ran is how a
// narrowed run killed after two walks came out as "2 of 2 walks", which reads
// as complete coverage of the set: the one thing a cut-short run may never say.
let narrow = parseSweepLog(KILLED, { total: 0, interrupted: true });
narrow.ended = '2026-09-18T15:09:00Z'; narrow.seconds = 33;
check('a cut-short run with no known set size counts no set at all',
  narrow.total === 0, narrow.total);
check('...and says "it reached 3 walks", never "3 of 3"',
  /reached 3 walks/.test(sweepSentences(narrow).join(' ')), sweepSentences(narrow)[0]);
// A run that COVERED what it was asked to still counts itself, narrowed or not.
const NARROW_OK = 'caliper-chip-join-walk                     10s  ok\n\n==> 1 passed, 0 failed\n';
check('a narrowed run that finished still counts its own size',
  parseSweepLog(NARROW_OK, { total: 0 }).total === 1);

// A run that stopped on the clock still reads as the clock, not as a kill.
r = parseSweepLog(KILLED, { total: 532, timedOut: true });
r.ended = '2026-09-18T15:09:00Z'; r.seconds = 1550;
check('a run stopped on the clock still says so',
  /stopped on the clock/.test(sweepSentences(r).join(' ')) && r.interrupted === false, r);

// ---- 2. recording one, and what happens to its requests ---------------------
console.log('recording a killed run');
const box = mkdtempSync(join(tmpdir(), 'sweep-interrupt-'));
const sw = (name) => join(box, name);
const REQUEST = { t: '2026-09-18T14:40:00.000Z', by: 'some-task', why: 'a change every walk touches' };

const claimWith = (requests) => {
  writeFileSync(sw('.claimed.json'), JSON.stringify({ requests }, null, 2));
};
const pending = () => {
  try { return JSON.parse(readFileSync(sw('requested.json'), 'utf8')).requests; } catch { return null; }
};

claimWith([REQUEST]);
rmSync(sw('requested.json'), { force: true });
let out = recordSweep({
  logText: KILLED, latest: sw('latest.json'), claimed: sw('.claimed.json'), req: sw('requested.json'),
  began: '2026-09-18T14:43:10Z', ended: '2026-09-18T15:09:00Z', seconds: 1550,
  runlogRel: 'queue/sweep/x.log', interrupted: true, total: 532, head: 'abc123',
});
check('what it reached is recorded', out.recorded === true, out.recorded);
let latest = JSON.parse(readFileSync(sw('latest.json'), 'utf8'));
check('the record says it did not cover the set', latest.complete === false, latest.complete);
check('the record says it was interrupted', latest.interrupted === true, latest.interrupted);
check('the record keeps the failing walk', latest.failed.join() === 'measure-chip-snap-walk', latest.failed);
check('the request that asked for it is pending again',
  (pending() || []).length === 1 && pending()[0].by === 'some-task', pending());

// ---- 3. a run that got through no walk at all -------------------------------
console.log('a run that answered nothing');
rmSync(sw('requested.json'), { force: true });
const before = readFileSync(sw('latest.json'), 'utf8');
claimWith([REQUEST]);
out = recordSweep({
  logText: NOTHING, latest: sw('latest.json'), claimed: sw('.claimed.json'), req: sw('requested.json'),
  began: '2026-09-18T16:00:00Z', ended: '2026-09-18T16:01:00Z', seconds: 60,
  runlogRel: 'queue/sweep/y.log', interrupted: true, total: 532,
});
check('nothing is written down', out.recorded === false, out.recorded);
check('so the last real sweep is still the last recorded one',
  readFileSync(sw('latest.json'), 'utf8') === before);
check('and the request is STILL pending, so a probe that cannot launch does not read as a clean run',
  (pending() || []).length === 1, pending());

// A locked run with nothing through is different: being turned away by every
// walk in the set IS news, and the dashboard counts the blind spell from it.
rmSync(sw('requested.json'), { force: true });
claimWith([REQUEST]);
out = recordSweep({
  logText: LOCKED_OUT, latest: sw('latest.json'), claimed: sw('.claimed.json'), req: sw('requested.json'),
  began: '2026-09-18T17:00:00Z', ended: '2026-09-18T17:01:00Z', seconds: 60,
  runlogRel: 'queue/sweep/z.log', total: 532,
});
check('a run every walk refused is still recorded, because a locked Mac is news',
  out.recorded === true && JSON.parse(readFileSync(sw('latest.json'), 'utf8')).screenLocked === true, out);

// ---- 4. an old run never overwrites a newer record --------------------------
console.log('an old run recovered late');
claimWith([REQUEST]);
out = recordSweep({
  logText: KILLED, latest: sw('latest.json'), claimed: sw('.claimed.json'), req: sw('requested.json'),
  began: '2026-09-18T10:00:00Z', ended: '2026-09-18T11:00:00Z', seconds: 3600,
  runlogRel: 'queue/sweep/old.log', interrupted: true, total: 532, onlyIfNewer: true,
});
check('a run older than what is recorded is not written over it',
  out.recorded === false && out.older === true, out);
check('its request still goes back on the pile', out.handedBack === 1, out);

// ---- 5. the notes on the standing task --------------------------------------
console.log('what the standing task is told');
const cut = { ...latest, ended: '2026-09-18T15:09:00Z', unfinished: 'measure-handback', log: 'queue/sweep/x.log' };
const block = machineBlock(cut, { previous: ['an-older-failure-walk'] });
check('the block says how much of the set it covered', /reached 3 of 532 walks/.test(block), block.slice(0, 300));
check('it marks the failures unconfirmed', /are UNCONFIRMED/.test(block), block);
check('it names the walk that never finished', /Never finished: measure-handback/.test(block), block);
check('it carries the older failures across rather than letting them read as healed',
  /Not run this time and still failing from the last check \(1\): an-older-failure-walk/.test(block), block);
check('it never says a walk stopped failing, because it is in no position to say',
  !/Stopped failing/.test(block), block);
check('and the failing list reads back cleanly, unconfirmed sentence and all',
  previousFailures(block).join() === 'measure-chip-snap-walk,an-older-failure-walk', previousFailures(block));

// ---- 6. the whole recovery, end to end --------------------------------------
console.log('recovering a claim nobody is running any more');
const q = mkdtempSync(join(tmpdir(), 'sweep-queue-'));
mkdirSync(join(q, 'sweep'), { recursive: true });
const qs = (n) => join(q, 'sweep', n);
writeFileSync(qs('2026-09-18-074310.log'), KILLED);
writeFileSync(qs('.claimed.json'), JSON.stringify({
  requests: [REQUEST], pid: 999999, began: '2026-09-18T14:43:10Z',
  logPath: qs('2026-09-18-074310.log'), logRel: 'queue/sweep/2026-09-18-074310.log',
  total: 532, head: 'ebbcfc3f',
}, null, 2));
// A standing walk task to be written onto, the way the real queue has one.
const standing = execFileSync(process.execPath, ['-e', `
  import('${join(REPO, 'queue/bin/queue-lib.mjs')}').then((q) => {
    const t = q.addTask({ title: 'Walks that fail in the full sweep', goal: 'g',
      epic: 'unmanned-loop', priority: 'p2-normal', acceptance: ['a'] });
    q.saveTask({ ...t, standing: 'walk-sweep' });
    console.log(t.id);
  });
`], { env: { ...process.env, PHOTONZ_QUEUE_DIR: q }, encoding: 'utf8' }).trim();

const recovered = execFileSync(process.execPath, [join(REPO, 'queue/bin/sweep-recover.mjs')],
  { env: { ...process.env, PHOTONZ_QUEUE_DIR: q }, encoding: 'utf8', cwd: REPO });
check('it says out loud that it found one', /left half-done/.test(recovered), recovered);
check('the claim is settled and gone', !existsSync(qs('.claimed.json')));
const rec = JSON.parse(readFileSync(qs('latest.json'), 'utf8'));
check('what the dead run reached is recorded',
  rec.walks === 3 && rec.interrupted === true && rec.complete === false, rec);
check('against the commit it was checking', rec.head === 'ebbcfc3f', rec.head);
const back = JSON.parse(readFileSync(qs('requested.json'), 'utf8')).requests;
check('and the request that asked for it is waiting again',
  back.length === 1 && back[0].by === 'some-task', back);

const task = JSON.parse(readFileSync(join(q, 'tasks', 'p2-normal', standing + '.json'), 'utf8'));
check('the failing walk it saw is on the standing task',
  /measure-chip-snap-walk/.test(task.notes), task.notes?.slice(0, 200));
check('and the standing task is NOT closed by a run that did not cover the set',
  task.status !== 'done', task.status);

// A request that arrived AFTER the claim is not lost or duplicated when the
// claimed ones come back in front of it.
console.log('a request that arrived while the dead run was running');
writeFileSync(qs('.claimed.json'), JSON.stringify({
  requests: [REQUEST], pid: 999999, began: '2026-09-18T14:43:10Z',
  logPath: qs('2026-09-18-074310.log'), logRel: 'queue/sweep/2026-09-18-074310.log', total: 532,
}, null, 2));
writeFileSync(qs('requested.json'), JSON.stringify({
  requests: [{ t: '2026-09-18T15:00:00.000Z', by: 'a-later-task', why: 'something else' }],
}, null, 2));
execFileSync(process.execPath, [join(REPO, 'queue/bin/sweep-recover.mjs')],
  { env: { ...process.env, PHOTONZ_QUEUE_DIR: q }, encoding: 'utf8', cwd: REPO });
const both = JSON.parse(readFileSync(qs('requested.json'), 'utf8')).requests;
check('both requests are pending, oldest first',
  both.length === 2 && both[0].by === 'some-task' && both[1].by === 'a-later-task', both);

// ---- 7. the run a SIGKILL orphaned is put down ------------------------------
console.log('the run a SIGKILL left going');
// A SIGKILL to sweep.sh does not touch playtest-all.sh: it is a background
// job, so it carries on through the rest of the set with nobody recording it
// and the caffeinate it started holding the Mac awake. Two stand-ins for those
// two processes, put down by the pids the claim wrote and by nothing else.
// Detached, because that is what they really are: a SIGKILL to sweep.sh
// reparents both to launchd, and a child this drill still owns would sit as a
// zombie after the kill and read as alive.
const orphan = spawn('/bin/sleep', ['120'], { stdio: 'ignore', detached: true });
const caffeine = spawn('/bin/sleep', ['120'], { stdio: 'ignore', detached: true });
orphan.unref(); caffeine.unref();
const awakeFile = qs('.awake.pid');
writeFileSync(awakeFile, String(caffeine.pid));
writeFileSync(qs('.claimed.json'), JSON.stringify({
  requests: [REQUEST], pid: 999999, runPid: orphan.pid, awakePidFile: awakeFile,
  began: '2026-09-18T14:43:10Z',
  logPath: qs('2026-09-18-074310.log'), logRel: 'x', total: 532,
}, null, 2));
const cleaned = execFileSync(process.execPath, [join(REPO, 'queue/bin/sweep-recover.mjs')],
  { env: { ...process.env, PHOTONZ_QUEUE_DIR: q }, encoding: 'utf8', cwd: REPO });
check('it notices the run is still going with nobody recording it',
  /STILL GOING with nobody recording it/.test(cleaned), cleaned);
const dead = (pid) => { try { process.kill(pid, 0); return false; } catch { return true; } };
await new Promise((ok) => setTimeout(ok, 300));
check('the orphaned run is stopped', dead(orphan.pid));
check('the hold keeping the Mac awake is released', dead(caffeine.pid));
check('and it says so', /Released the hold keeping the Mac awake/.test(cleaned), cleaned);
check('the pid file goes with it', !existsSync(awakeFile));

// ---- 8. a sweep that IS still running is left alone -------------------------
console.log('a sweep that is genuinely still running');
// A process whose command line names sweep.sh, which is what the liveness
// check looks for: a pid on its own is not enough, because pids are reused.
const impostor = join(q, 'sweep.sh');
writeFileSync(impostor, '#!/bin/bash\nsleep 30\n');
const live = spawn('/bin/bash', [impostor], { stdio: 'ignore' });
await new Promise((ok) => setTimeout(ok, 300));
writeFileSync(qs('.claimed.json'), JSON.stringify({
  requests: [REQUEST], pid: live.pid, began: new Date().toISOString(),
  logPath: qs('2026-09-18-074310.log'), logRel: 'x', total: 532,
}, null, 2));
const leftAlone = execFileSync(process.execPath, [join(REPO, 'queue/bin/sweep-recover.mjs')],
  { env: { ...process.env, PHOTONZ_QUEUE_DIR: q }, encoding: 'utf8', cwd: REPO });
check('it says a sweep is running and stops there', /running right now/.test(leftAlone), leftAlone);
check('and the claim is untouched', existsSync(qs('.claimed.json')));
// --force is how sweep.sh's own signal handler recovers its own live claim.
const forced = execFileSync(process.execPath, [join(REPO, 'queue/bin/sweep-recover.mjs'), '--force'],
  { env: { ...process.env, PHOTONZ_QUEUE_DIR: q }, encoding: 'utf8', cwd: REPO });
check('--force recovers it anyway', /left half-done/.test(forced) && !existsSync(qs('.claimed.json')), forced);
live.kill('SIGKILL');
await new Promise((ok) => setTimeout(ok, 200));
check('and the stand-in process is gone, because nothing this drill starts outlives it',
  (() => { try { process.kill(live.pid, 0); return false; } catch { return true; } })());

rmSync(box, { recursive: true, force: true });
rmSync(q, { recursive: true, force: true });
console.log(failures ? '\n' + failures + ' FAILED' : '\nall good');
process.exit(failures ? 1 : 0);
