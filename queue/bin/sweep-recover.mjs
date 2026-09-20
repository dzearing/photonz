#!/usr/bin/env node
// Picks up a sweep that never reached the end, and makes it count.
//
// queue/bin/sweep.sh claims the pending requests into .claimed.json BEFORE it
// starts the run, because a request arriving during a sweep belongs to the next
// one. Everything else about the run - what it found, and whose request it was
// serving - was written down only at the END. So a run that was killed lost
// both halves at once, and the next successful run deleted the evidence:
//
//   2026-09-18 14:43Z  the loop starts a sweep
//   2026-09-18 15:09Z  the loop dies, 126 walks in, one of them failing
//   2026-09-19 15:31Z  the loop is started again by hand. requested.json is
//                      gone, latest.json still names the sweep BEFORE this one,
//                      and sweep.sh status says no sweep is pending. All true,
//                      and all of it means the commit that landed that morning
//                      was never checked and nobody was going to check it.
//
// This closes both. .claimed.json now carries the run's identity as well as its
// requests - which process is running it, which log it is writing, how big the
// set is - so a later pass can look at one left behind, see that nobody is
// running it any more, and finish the job the dead run did not:
//
//   * what it reached is recorded like any other run that did not cover the
//     set, through the same recordSweep() the live path uses;
//   * its failures go onto the standing walk task through the same
//     sweep-report.mjs, marked as unconfirmed because a stop takes the probe
//     app down with it;
//   * the requests it claimed go back on the pile, so the sweep is still owed.
//
// It runs at the top of every sweep.sh verb, so whoever looks first heals it,
// and it is safe to run at any time: a claim whose process is still alive is a
// sweep genuinely in flight and is left completely alone.
//
//   queue/bin/sweep-recover.mjs           heal an abandoned claim, if there is one
//   queue/bin/sweep-recover.mjs --force   heal the claim even though it is ours
//                                         (sweep.sh's own signal handler)
//   queue/bin/sweep-recover.mjs --quiet   say nothing when there is nothing to do
import { existsSync, readFileSync, unlinkSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { recordSweep } from './sweep-record.mjs';
import { sweepSentences } from './sweep-parse.mjs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const QUEUE = process.env.PHOTONZ_QUEUE_DIR ? resolve(process.env.PHOTONZ_QUEUE_DIR) : join(REPO, 'queue');
const SDIR = join(QUEUE, 'sweep');
const CLAIMED = join(SDIR, '.claimed.json');
const LATEST = join(SDIR, 'latest.json');
const REQ = join(SDIR, 'requested.json');

const force = process.argv.includes('--force');
const quiet = process.argv.includes('--quiet');
const say = (...a) => console.log(...a);

// Is a pid a process that is really still going? A process that has been
// killed but not yet reaped by its parent is a ZOMBIE: signal 0 still finds
// it, so the naive check reports it alive and the cleanup below says the hold
// on the Mac would not go when it already has.
function alive(pid) {
  if (!pid || !Number.isInteger(Number(pid)) || Number(pid) <= 1) return false;
  try { process.kill(Number(pid), 0); } catch { return false; }
  try {
    const state = execFileSync('ps', ['-p', String(pid), '-o', 'state='], { encoding: 'utf8' }).trim();
    return state.length > 0 && !state.startsWith('Z');
  } catch { return false; }
}

// Is the process that claimed this sweep still running it? Two questions, not
// one: pids are reused, so being alive is not enough. The command has to still
// be a sweep. Anything we cannot answer reads as "not running", because the
// cost of healing a live run is a duplicate record and the cost of never
// healing a dead one is the silence this file exists to end.
function stillRunning(pid) {
  if (!alive(pid)) return false;
  try {
    const cmd = execFileSync('ps', ['-p', String(pid), '-o', 'command='], { encoding: 'utf8' });
    return /sweep\.sh/.test(cmd);
  } catch { return false; }
}

if (!existsSync(CLAIMED)) {
  if (!quiet) say('==> No sweep was left half-done.');
  process.exit(0);
}

let claim = {};
try { claim = JSON.parse(readFileSync(CLAIMED, 'utf8')) || {}; } catch { claim = {}; }
const requests = Array.isArray(claim.requests) ? claim.requests : [];

if (!force && stillRunning(claim.pid)) {
  if (!quiet) say(`==> A sweep is running right now (pid ${claim.pid}); leaving it alone.`);
  process.exit(0);
}

// A SIGKILL to sweep.sh leaves its child running: playtest-all.sh is a
// background job, so it is orphaned and carries on through the rest of the
// set with nobody recording it, holding the Mac awake the whole time. Put it
// down by the pid the claim wrote, and only then the hold and the probe. Never
// pkill: the user's own dev app and their own caffeinate look exactly like
// ours to a pattern.
function putDownTheOrphan(claim) {
  const pid = Number(claim.runPid);
  if (!alive(pid)) return false;                               // already finished, and it cleaned up after itself
  say(`   Its run (pid ${pid}) is STILL GOING with nobody recording it. Stopping it.`);
  try { process.kill(pid, 'SIGTERM'); } catch { /* raced us */ }
  execFileSync('sleep', ['2']);
  try { process.kill(pid, 'SIGKILL'); } catch { /* gone */ }

  // The caffeinate playtest-all started, by the pid it wrote down. A SIGKILL
  // leaves its EXIT trap unrun, so nothing else will.
  const awake = claim.awakePidFile;
  if (awake && existsSync(awake)) {
    const apid = Number(readFileSync(awake, 'utf8').trim());
    if (apid) {
      try { process.kill(apid, 'SIGTERM'); } catch { /* gone */ }
      execFileSync('sleep', ['1']);
      say(alive(apid)
        ? `   The caffeinate holding the Mac awake (pid ${apid}) would not go. Kill it by hand.`
        : '   Released the hold keeping the Mac awake.');
    }
    try { unlinkSync(awake); } catch { /* fine */ }
  }

  // And the probe app, which a walk killed mid-step leaves up. Only here,
  // where we know a run really was in flight: this file runs at the top of
  // every sweep.sh verb, and quitting the probe on a tidy repo would pull it
  // out from under a task runner driving it.
  try {
    execFileSync(join(REPO, 'Scripts', 'probe-app.sh'), ['--quit'], { stdio: 'ignore', cwd: REPO });
    say('   Put the probe app away.');
  } catch { /* it was not up */ }
  return true;
}

putDownTheOrphan(claim);

const began = claim.began || null;
const logPath = claim.logPath && existsSync(claim.logPath) ? claim.logPath : null;
const logText = logPath ? readFileSync(logPath, 'utf8') : '';
// How long it got, measured off the log rather than a clock nobody was
// watching: the last thing it wrote is the last moment it was alive.
const ended = new Date(logPath ? statSync(logPath).mtimeMs : Date.now()).toISOString().replace(/\.\d+Z$/, 'Z');
const seconds = began ? Math.max(0, Math.round((Date.parse(ended) - Date.parse(began)) / 1000)) : 0;

say('!! A sweep was left half-done: it claimed '
  + `${requests.length} request(s)${began ? ` at ${began}` : ''} and never wrote down what it found.`);
if (!logPath) {
  // An old-style claim, or one whose log was rotated away. There is nothing to
  // record, but the requests are the half that matters most and they still go
  // back.
  say('   Its run log is gone, so there is nothing to record from it.');
}

const { result, recorded, older, handedBack } = recordSweep({
  logText,
  latest: LATEST, claimed: CLAIMED, req: REQ,
  began: began || ended, ended, seconds,
  runlogRel: claim.logRel || null,
  interrupted: true,
  total: Number(claim.total) || 0,
  head: claim.head || null,
  onlyIfNewer: true,
});

for (const line of sweepSentences(result)) say('   ' + line);
if (result.failed.length) say(`   Failing (unconfirmed): ${result.failed.join(', ')}`);
if (!recorded) {
  say(older
    ? '   A newer sweep has been recorded since, so this one is not written over it; its failures are already old news.'
    : '   Not one walk answered, so nothing is written down: the last recorded sweep stays the last recorded sweep.');
}
say(handedBack
  ? `   ${handedBack} request(s) put back: a sweep is owed again and the loop runs one between tasks.`
  : '   It was not serving anybody\'s request, so there is nothing to put back.');

// The failures it did see go onto the standing walk task, exactly as a live run
// would put them there. sweep-report refuses a run that reached no walk, never
// closes the standing task for a run that did not cover the set, and never
// files a task to announce a clean one, so it needs no special case here.
if (recorded) {
  try {
    execFileSync(process.execPath, [join(REPO, 'queue', 'bin', 'sweep-report.mjs'), LATEST],
      { stdio: 'inherit', cwd: REPO });
  } catch (e) {
    say(`   Could not write it onto the standing walk task: ${e.message}`);
  }
}

// The claim is settled either way. Left behind, it would be re-recovered on
// every call.
try { unlinkSync(CLAIMED); } catch { /* already gone */ }
