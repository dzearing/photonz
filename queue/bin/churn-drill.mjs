#!/usr/bin/env node
// Churn drill: prove the queue cannot be ballooned by a loop that claims and
// resets the same task forever.
//
//   node queue/bin/churn-drill.mjs
//
// On 2026-08-23 the loop claimed one task and exited without finalizing it
// 2,757 times, leaving a 556KB task file (5,515 log entries) and 8,114 history
// events that the dashboard re-parsed on every poll. The guards below have to
// hold no matter how many times that cycle repeats:
//
//   1. a task log never grows past LOG_MAX, and the elision stays truthful
//   2. identical consecutive notes coalesce instead of appending
//   3. a blind reset is not a free retry: it parks like any other failure
//   4. history compaction collapses old churn but keeps every real event,
//      in order, with the dashboard's charts unchanged
//   5. compaction triggers on its own once the file is over budget
//
// Runs against a throwaway queue; never touches the real one.
import { mkdtempSync, rmSync, writeFileSync, appendFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const sandbox = mkdtempSync(join(tmpdir(), 'photonz-churn-'));
process.env.PHOTONZ_QUEUE_DIR = join(sandbox, 'queue');
const q = await import('./queue-lib.mjs');
const HISTORY = join(process.env.PHOTONZ_QUEUE_DIR, 'history.jsonl');

let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? '  PASS  ' : '  FAIL  ') + name + (detail ? '\n          ' + detail : ''));
  if (!ok) failed++;
};
const iso = (msAgo) => new Date(Date.now() - msAgo).toISOString();
const writeHistory = (events) => writeFileSync(HISTORY, events.map((e) => JSON.stringify(e)).join('\n') + '\n');

try {
  // --- 1 + 2: the task log under a churning loop --------------------------
  const task = q.addTask({ title: 'Churn drill task', priority: 'p1-high', notes: 'drill' });
  // 500 claim/reset rounds, exactly the alternating pair the incident produced.
  for (let i = 0; i < 500; i++) {
    const t = q.findTask(task.id);
    q.appendLog(t, 'claimed by go loop');
    q.appendLog(t, 'runner exited without finalizing; reset to pending');
    q.saveTask(t);
  }
  const churned = q.findTask(task.id);
  check('task log is capped', churned.log.length <= q.LOG_MAX,
    churned.log.length + ' entries (cap ' + q.LOG_MAX + ')');
  check('the task file stays small enough to render', statSync(churned.file).size < 32 * 1024,
    statSync(churned.file).size + ' bytes');
  check('the opening entries survive the elision', churned.log[0].note.startsWith('created'),
    JSON.stringify(churned.log[0].note));
  check('the most recent entry survives the elision',
    churned.log[churned.log.length - 1].note.startsWith('runner exited'),
    JSON.stringify(churned.log[churned.log.length - 1].note));
  const marker = churned.log.find((e) => e.elided);
  check('an elision marker says how many entries went missing', !!marker && marker.elided > 800,
    marker ? marker.note : 'no marker');

  const coalesced = { log: [] };
  for (let i = 0; i < 40; i++) q.appendLog(coalesced, 'same note every time');
  check('identical consecutive notes coalesce into one counted entry',
    coalesced.log.length === 1 && coalesced.log[0].count === 40 && !!coalesced.log[0].since,
    JSON.stringify(coalesced.log));

  // --- 3: a blind reset is not a free retry -------------------------------
  const victim = q.addTask({ title: 'Never finalized', priority: 'p1-high', notes: 'drill' });
  const guards = [];
  for (let i = 0; i < 4; i++) {
    const t = q.findTask(victim.id);
    if (t.status === 'pending') { t.status = 'in_progress'; q.saveTask(t); }
    guards.push(q.guardStuck());
  }
  const after = q.findTask(victim.id);
  check('guard parks a task it has reset MAX_TASK_FAILURES times',
    after.parked === true && after.status === 'blocked',
    'status=' + after.status + ' parked=' + after.parked + ' failures=' + after.failures);
  check('guard reports what it parked',
    guards.some((g) => g.parked.includes(victim.id)),
    JSON.stringify(guards));
  check('a parked task is no longer claimable',
    (q.claimNext(null) || {}).id !== victim.id, 'claimed ' + JSON.stringify((q.claimNext(null) || {}).id));

  // --- 3b: a runner that exits 0 but never finalizes ----------------------
  // The 2026-08-23 shape: the runner looked successful and the loop treated
  // "exited" as "finished", re-claiming every ~6 seconds. A clean exit code
  // must not launder an unfinalized task into a free retry.
  const silent = q.addTask({ title: 'Runner exits clean but never finalizes', priority: 'p1-high', notes: 'drill' });
  const rounds = [];
  for (let i = 0; i < 5; i++) {
    const claimed = q.claimNext(null);
    if (!claimed || claimed.id !== silent.id) { rounds.push({ claimed: claimed && claimed.id }); continue; }
    rounds.push({ claimed: claimed.id, ...q.recordRunnerExit({ taskId: silent.id, exit: 0 }) });
  }
  const attempts = rounds.filter((r) => r.claimed === silent.id);
  check('a clean exit with the task still in_progress counts as a failure',
    attempts.every((r) => r.outcome !== 'ok'), JSON.stringify(attempts.map((r) => r.outcome)));
  check('the loop waits longer after each attempt',
    attempts.every((r, i) => i === 0 || r.backoff >= attempts[i - 1].backoff) && attempts[0].backoff > 0,
    'backoffs: ' + attempts.map((r) => r.backoff + 's').join(', '));
  check('it stops re-claiming after MAX_TASK_FAILURES attempts',
    attempts.length === q.MAX_TASK_FAILURES && q.findTask(silent.id).parked === true,
    attempts.length + ' attempts, parked=' + q.findTask(silent.id).parked);
  check('the park reason says what went wrong',
    /without finalizing/.test(q.findTask(silent.id).parkReason || ''),
    JSON.stringify(q.findTask(silent.id).parkReason));

  // --- 4: history compaction ----------------------------------------------
  const old = 5 * 24 * 3600 * 1000;  // well past the 48h churn retention window
  const synthetic = [
    { t: iso(old + 6000), ev: 'task_created', id: 'a', priority: 'p1-high' },
    ...Array.from({ length: 1200 }, (_, i) => [
      { t: iso(old - i * 1000), ev: 'task_started', id: 'a' },
      { t: iso(old - i * 1000 - 500), ev: 'task_reset', id: 'a' },
    ]).flat(),
    { t: iso(3600 * 1000), ev: 'task_started', id: 'b' },   // inside the window: kept as-is
    { t: iso(3500 * 1000), ev: 'task_reset', id: 'b' },
    { t: iso(1000), ev: 'task_done', id: 'a' },
  ];
  writeHistory(synthetic);
  const before = q.aggregateState().series;
  const r = q.compactHistory();
  const events = q.readHistory();
  check('compaction collapses churn', r.after < 10 && r.changed, r.before + ' -> ' + r.after + ' events');
  check('every real event survives',
    events.filter((e) => e.ev === 'task_created').length === 1 &&
    events.filter((e) => e.ev === 'task_done').length === 1,
    events.map((e) => e.ev).join(', '));
  const roll = events.find((e) => e.ev === 'task_started' && e.id === 'a');
  check('a rolled-up entry carries the count it stands for',
    !!roll && roll.repeats === 1200 && !!roll.until, JSON.stringify(roll));
  check('recent churn is left entry-per-attempt',
    events.some((e) => e.ev === 'task_started' && e.id === 'b' && !e.rolledUp),
    JSON.stringify(events.filter((e) => e.id === 'b')));
  check('events stay in chronological order',
    events.every((e, i) => i === 0 || e.t >= events[i - 1].t),
    events.map((e) => e.t).join(' '));
  check('the dashboard charts are unchanged by compaction',
    JSON.stringify(q.aggregateState().series) === JSON.stringify(before),
    JSON.stringify(q.aggregateState().series));
  check('compacting twice changes nothing', q.compactHistory().changed === false);

  // A storm that happened an hour ago is still "recent", but 3,000 entries of it
  // must not sit in the file just because they are young.
  const storm = [
    { t: iso(7200 * 1000), ev: 'task_created', id: 'd', priority: 'p1-high' },
    ...Array.from({ length: 3000 }, (_, i) => ({ t: iso(7000 * 1000 - i * 1000), ev: 'task_started', id: 'd' })),
  ];
  writeHistory(storm);
  const stormResult = q.compactHistory();
  const stormEvents = q.readHistory();
  check('a same-day storm is capped even inside the retention window',
    stormResult.after <= 210 && stormEvents.filter((e) => e.ev === 'task_created').length === 1,
    stormResult.before + ' -> ' + stormResult.after + ' events');
  check('the storm rollup accounts for every attempt',
    stormEvents.filter((e) => e.ev === 'task_started').reduce((n, e) => n + (e.repeats || 1), 0) === 3000,
    stormEvents.filter((e) => e.ev === 'task_started').reduce((n, e) => n + (e.repeats || 1), 0) + ' attempts accounted for');
  check('the newest attempts stay entry-per-attempt',
    stormEvents.slice(-3).every((e) => !e.rolledUp),
    JSON.stringify(stormEvents.slice(-3)));

  // --- 5: compaction runs on its own --------------------------------------
  const bulk = [
    { t: iso(old), ev: 'task_created', id: 'c', priority: 'p1-high' },
    ...Array.from({ length: 9000 }, (_, i) => ({ t: iso(old - i * 100), ev: 'task_started', id: 'c', note: 'x'.repeat(60) })),
  ];
  writeHistory(bulk);
  const bulkSize = statSync(HISTORY).size;
  q.appendEvent('task_done', { id: 'c' });
  check('an over-budget history compacts itself on the next append',
    bulkSize > q.HISTORY_MAX_BYTES && statSync(HISTORY).size < q.HISTORY_MAX_BYTES,
    Math.round(bulkSize / 1024) + 'KB -> ' + Math.round(statSync(HISTORY).size / 1024) + 'KB');
  check('the event that triggered compaction is still there',
    q.readHistory().some((e) => e.ev === 'task_done' && e.id === 'c'),
    q.readHistory().slice(-2).map((e) => e.ev).join(', '));

  // A history that is legitimately large (all real events) is over budget on
  // every append, and must not re-scan and rewrite itself every time. After one
  // fruitless compaction it stands down until the file has really grown.
  const solid = Array.from({ length: 9000 }, (_, i) => ({ t: iso(old - i * 100), ev: 'task_created', id: 'k' + i, note: 'y'.repeat(60) }));
  writeHistory(solid);
  q.appendEvent('task_done', { id: 'k0' });          // compacts nothing, records the size
  check('a legitimately large history keeps all of its events',
    q.readHistory().length === 9001, q.readHistory().length + ' events');
  appendFileSync(HISTORY, Array.from({ length: 20 }, (_, i) =>
    JSON.stringify({ t: iso(old - i * 100), ev: 'task_started', id: 'k0' })).join('\n') + '\n');
  q.appendEvent('task_done', { id: 'k1' });          // growth is tiny: no second scan
  check('it stands down until the file has really grown',
    q.readHistory().filter((e) => e.ev === 'task_started').length === 20,
    q.readHistory().filter((e) => e.ev === 'task_started').length + ' churn events still uncompacted');
} finally {
  rmSync(sandbox, { recursive: true, force: true });
}

console.log(failed ? `\n[churn-drill] ${failed} check(s) failed` : '\n[churn-drill] all checks passed');
process.exit(failed ? 1 : 0);
