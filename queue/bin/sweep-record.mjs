#!/usr/bin/env node
// Records what a sweep run found, in one place, for every shape a run can end
// in: covered the set, ran only the part a locked screen cannot touch, was
// refused outright, was stopped on the clock, or was INTERRUPTED because
// whoever was running it went away.
//
// It also decides what happens to the requests the run claimed. A sweep that
// COVERED THE SET has served them and they are gone. A sweep that did not, for
// whatever reason, hands them straight back: a partial run is real news about
// the walks it ran, and it is still not the full sweep somebody asked for.
//
// The interrupted case is why this is a module and not only a script. A run
// that is killed never reaches the end of sweep.sh, so nothing here runs at the
// time: queue/bin/sweep-recover.mjs calls recordSweep() later, off the run log
// the dead run left behind. Both paths write the same shape, so nothing
// downstream has to know which one happened.
//
//   queue/bin/sweep-record.mjs <runlog> <latest.json> <claimed.json> <requested.json> \
//       <began> <ended> <seconds> <runlogRelPath> <timedOut 0|1> <totalWalks> <headSha> [<interrupted 0|1>]
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { parseSweepLog, sweepSentences } from './sweep-parse.mjs';

// Record one run and settle its requests. Returns what it wrote and what it
// decided, so a caller can say it out loud rather than guessing.
export function recordSweep({
  logText, latest, claimed, req,
  began, ended, seconds, runlogRel,
  timedOut = false, interrupted = false, total = 0, head = null,
  // Only write latest.json if this run is newer than what is already there.
  // The recovery path reads a run that ended hours ago, and a stale record
  // written over a fresh one would be worse than the silence it is fixing.
  onlyIfNewer = false,
}) {
  const r = parseSweepLog(logText, { total: Number(total) || 0, timedOut, interrupted });

  let requests = [];
  try { requests = JSON.parse(readFileSync(claimed, 'utf8')).requests || []; } catch { /* none */ }

  const result = {
    began, ended, seconds: Number(seconds),
    walks: r.walks, passed: r.passed, failed: r.failed,
    couldNotRun: r.couldNotRun, total: r.total,
    // Which of those failures were the app DYING, and what it died in. A crash
    // is filed like any failure and read like nothing else: it takes the open
    // document with it and everything after it is a question mark.
    crashed: r.crashed,
    ranWalks: r.ranWalks, refusedWalks: r.refusedWalks,
    requests, log: runlogRel,
    complete: r.complete, timedOut: r.timedOut,
    interrupted: r.interrupted, unfinished: r.unfinished,
    screenLocked: r.screenLocked, partial: r.partial,
    // Which commit this ran against. While the screen stays locked the loop runs
    // the lock-safe part again only once new code has landed, so a partial sweep
    // does not repeat itself for forty minutes between every pair of tasks.
    head: head || null,
  };

  // A run cut short before a single walk answered has nothing to say, and
  // writing its row of zeroes over latest.json would throw away the last real
  // sweep and read on the dashboard as the state of the app. A probe that
  // cannot launch, a loop killed in the first minute: those are non-events.
  //
  // Not the same as a LOCKED run with nothing through. That one got as far as
  // being turned away by every walk in the set, which is news, and the
  // dashboard counts how long the lock has been going from exactly those
  // records. So the silence is only for a run with no walks AND no refusals.
  const nothingToSay = r.walks === 0 && r.couldNotRun === 0;
  let older = false;
  if (onlyIfNewer) {
    try {
      const was = JSON.parse(readFileSync(latest, 'utf8'));
      older = Boolean(was.ended && ended && Date.parse(was.ended) >= Date.parse(ended));
    } catch { /* nothing recorded yet */ }
  }
  const recorded = !nothingToSay && !older;
  if (recorded) writeFileSync(latest, JSON.stringify(result, null, 2) + '\n');

  // Hand the requests back unless the set was actually covered. This is the
  // half that goes missing when a run is killed: sweep.sh claims the requests
  // into .claimed.json before it starts, so a run that never reaches here
  // leaves nobody asking for the sweep it failed to do.
  let handedBack = 0;
  if (!r.complete && requests.length) {
    let pending = { requests: [] };
    try { pending = JSON.parse(readFileSync(req, 'utf8')); } catch { /* none pending */ }
    if (!Array.isArray(pending.requests)) pending.requests = [];
    // The claimed ones go first: they were asked for first, and the dashboard
    // reads the oldest to say how long a sweep has been waiting.
    const already = new Set(pending.requests.map((x) => `${x.t}|${x.by}`));
    pending.requests = requests.filter((x) => !already.has(`${x.t}|${x.by}`)).concat(pending.requests);
    writeFileSync(req, JSON.stringify(pending, null, 2) + '\n');
    handedBack = requests.length;
  }

  return { result, recorded, older, handedBack };
}

// ---- the command line ------------------------------------------------------
const invokedDirectly = process.argv[1] && process.argv[1].endsWith('sweep-record.mjs');
if (invokedDirectly) {
  const [logFile, latest, claimed, req, began, ended, seconds, runlogRel, timedOut, total, head, interrupted] =
    process.argv.slice(2);

  const { result, recorded, handedBack } = recordSweep({
    logText: existsSync(logFile) ? readFileSync(logFile, 'utf8') : '',
    latest, claimed, req, began, ended, seconds, runlogRel,
    timedOut: timedOut === '1', interrupted: interrupted === '1',
    total, head,
  });

  if (!recorded) {
    console.log('==> Not one walk answered and nothing was refused, so this run is not written down: '
      + 'the last recorded sweep stays the last recorded sweep.');
  }
  for (const line of sweepSentences(result)) console.log(line);
  if (result.failed.length) console.log(`Failing: ${result.failed.join(', ')}`);
  if (handedBack) {
    console.log(`${handedBack} sweep request(s) handed back: this run did not cover the set, so a sweep is still owed.`);
  }
}
