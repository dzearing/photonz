#!/usr/bin/env node
// Records what a sweep run found, in one place, for every shape a run can end
// in: covered the set, ran only the part a locked screen cannot touch, was
// refused outright, or was stopped on the clock.
//
// It also decides what happens to the requests the run claimed. A sweep that
// COVERED THE SET has served them and they are gone. A sweep that did not, for
// whatever reason, hands them straight back: a partial run is real news about
// the walks it ran, and it is still not the full sweep somebody asked for.
//
//   queue/bin/sweep-record.mjs <runlog> <latest.json> <claimed.json> <requested.json> \
//       <began> <ended> <seconds> <runlogRelPath> <timedOut 0|1> <totalWalks> <headSha>
import { readFileSync, writeFileSync } from 'node:fs';
import { parseSweepLog, sweepSentences } from './sweep-parse.mjs';

const [logFile, latest, claimed, req, began, ended, seconds, runlogRel, timedOut, total, head] =
  process.argv.slice(2);

const r = parseSweepLog(readFileSync(logFile, 'utf8'), {
  total: Number(total) || 0,
  timedOut: timedOut === '1',
});

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
  screenLocked: r.screenLocked, partial: r.partial,
  // Which commit this ran against. While the screen stays locked the loop runs
  // the lock-safe part again only once new code has landed, so a partial sweep
  // does not repeat itself for forty minutes between every pair of tasks.
  head: head || null,
};
writeFileSync(latest, JSON.stringify(result, null, 2) + '\n');

// Hand the requests back unless the set was actually covered.
if (!r.complete && requests.length) {
  let pending = { requests: [] };
  try { pending = JSON.parse(readFileSync(req, 'utf8')); } catch { /* none pending */ }
  if (!Array.isArray(pending.requests)) pending.requests = [];
  pending.requests = requests.concat(pending.requests);
  writeFileSync(req, JSON.stringify(pending, null, 2) + '\n');
}

for (const line of sweepSentences(result)) console.log(line);
if (result.failed.length) console.log(`Failing: ${result.failed.join(', ')}`);
