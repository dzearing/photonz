#!/usr/bin/env node
// Drill for WHERE a rotating check's broken walks land.
//
// The promise is that a walk the check between tasks finds broken reaches a
// task somebody will pick up, the same day. Until 2026-09-29 that held only
// while a standing walk task happened to be open; the rest of the time the
// failure went into queue/loop.log and nowhere else (thirteen times on
// 2026-09-28 alone). What this holds true:
//
//   - with no task open, the check opens the standing walk task, ONE of it,
//     naming only the walks it saw fail;
//   - the next check writes onto that task rather than opening a second;
//   - a walk another open task owns is written onto that task and not onto the
//     standing one, whether the owner declared it or only names it;
//   - unless every task that owns it is blocked on a card: then the standing
//     task takes it too (opened if it has to be), naming the owner, and so
//     does the full sweep's block, because nobody claims a blocked task;
//   - a clean check files nothing;
//   - the first full sweep reads the check's list back, so it can say a walk
//     stopped failing and close the task it did not open.
//
//   node queue/bin/slice-owner-drill.mjs
import { mkdtempSync, readFileSync, writeFileSync, readdirSync, rmSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

const qdir = mkdtempSync(join(tmpdir(), 'photonz-slice-owner-'));
for (const p of ['p0-critical', 'p1-high', 'p2-normal', 'p3-low']) mkdirSync(join(qdir, 'tasks', p), { recursive: true });
const env = { ...process.env, PHOTONZ_QUEUE_DIR: qdir };

const tasks = () => readdirSync(join(qdir, 'tasks')).flatMap((p) =>
  readdirSync(join(qdir, 'tasks', p)).filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(readFileSync(join(qdir, 'tasks', p, f), 'utf8'))));
const task = (id) => tasks().find((t) => t.id === id);
const standing = () => tasks().filter((t) => t.standing === 'walk-sweep');
const logText = (t) => (t.log || []).map((l) => l.note).join('\n');

// A task somebody filed by hand, as queue.mjs would write it.
function put(id, fields) {
  writeFileSync(join(qdir, 'tasks', 'p1-high', id + '.json'), JSON.stringify({
    id, title: id, goal: '', epic: 'x', priority: 'p1-high', seq: 10, status: 'pending',
    created: '2026-09-29T00:00:00Z', updated: '2026-09-29T00:00:00Z', deps: [], blockedBy: [],
    notes: '', acceptance: [], log: [{ t: '2026-09-29T00:00:00Z', note: 'created' }], ...fields,
  }, null, 2) + '\n');
}

// One rotating check: `ok` walks passing and the named ones failing.
let n = 0;
function runCheck(failing, { ok = 5, changed = [] } = {}) {
  n++;
  const pad = (s) => s.padEnd(40, ' ');
  const lines = [];
  for (let i = 0; i < ok; i++) lines.push(`${pad('good-walk-' + i)}   9s  ok`);
  for (const f of failing) lines.push(`${pad(f)}   8s  FAILED  step 3 (press): no control called "Blur"`);
  lines.push('', `==> ${ok} passed, ${failing.length} failed`);
  if (failing.length) lines.push(...failing.map((f) => '    ' + f));
  lines.push(`==> ${ok + failing.length} walks in 1m 0s`, '');
  const runlog = join(qdir, `run-${n}.log`);
  writeFileSync(runlog, lines.join('\n'));
  writeFileSync(join(qdir, 'pick.json'), JSON.stringify({ changed, from: 100, nextCursor: 150 }));
  return execFileSync('queue/bin/sweep-slice-record.mjs', [
    runlog, join(qdir, 'last-slice.json'),
    '2026-09-29T10:00:00Z', `2026-09-29T1${n}:10:00Z`, '600', String(ok + failing.length), '653', join(qdir, 'pick.json'), '0',
  ], { env, encoding: 'utf8' });
}

// ---- 1. nothing open, two walks broken --------------------------------------
console.log('a check that finds broken walks nobody owns, with no standing task open');
let out = runCheck(['alpha-walk', 'beta-walk'], { changed: ['beta-walk'] });
check('it opens exactly one task', tasks().length === 1, tasks().map((t) => t.id));
const s1 = standing()[0];
check('and that task is the standing walk task, marked so a sweep finds it', Boolean(s1), tasks());
check('it names both walks in its notes', /Failing walks \(2\): alpha-walk, beta-walk/.test(s1?.notes || ''), s1?.notes);
check('it says a check opened it, not a sweep', /rotating check/.test(s1?.notes || ''), s1?.notes);
check('its log carries the check line', /alpha-walk, beta-walk \(its script changed/.test(logText(s1 || {})), s1?.log);
check('it has a goal and a checklist', Boolean(s1?.goal) && (s1?.acceptance || []).length >= 2, s1);
check('it declares no walks of its own', s1 && s1.walks === undefined, s1?.walks);
check('the check says where they went', /opened the standing walk task/.test(out), out);

// ---- 2. the next check, same walks ------------------------------------------
console.log('the next check finds them still broken');
out = runCheck(['alpha-walk', 'beta-walk']);
check('no second task is opened', tasks().length === 1, tasks().map((t) => t.id));
check('the standing task is told again', logText(standing()[0]).split('\n').filter((l) => /^rotating check/.test(l)).length === 2, standing()[0].log);

// ---- 3. an owner declared, an owner guessed, and nobody ---------------------
console.log('walks another open task owns');
put('fix-alpha', { walks: ['alpha-walk'] });
put('about-gamma', { notes: 'gamma-walk fails because the popover moved' });
const before = logText(standing()[0]);
out = runCheck(['alpha-walk', 'gamma-walk', 'beta-walk']);
check('still no new task', tasks().length === 3, tasks().map((t) => t.id));
check('the declared owner is told about its walk', /alpha-walk failing/.test(logText(task('fix-alpha'))), task('fix-alpha').log);
check('  ...and is not told about walks it does not own',
  !/beta-walk|gamma-walk/.test(logText(task('fix-alpha'))), task('fix-alpha').log);
check('the task that names a walk is told, with how to disown it',
  /gamma-walk failing/.test(logText(task('about-gamma'))) && /walks about-gamma --none/.test(logText(task('about-gamma'))), task('about-gamma').log);
const added = logText(standing()[0]).slice(before.length);
check('only the walk nobody owns goes onto the standing task',
  /beta-walk/.test(added) && !/alpha-walk|gamma-walk/.test(added), added);

// ---- 4. every broken walk owned, standing task closed -----------------------
console.log('owned walks with no standing task open');
const sid = standing()[0].id;
const sf = tasks().find((t) => t.id === sid);
const sfile = readdirSync(join(qdir, 'tasks')).map((p) => join(qdir, 'tasks', p, sid + '.json'))
  .find((f) => { try { readFileSync(f); return true; } catch { return false; } });
writeFileSync(sfile, JSON.stringify({ ...sf, status: 'done' }, null, 2) + '\n');
out = runCheck(['alpha-walk']);
check('a walk its owner has is not a reason to open a standing task',
  standing().filter((t) => t.status !== 'done').length === 0, standing().map((t) => [t.id, t.status]));
check('  ...and the owner hears about it',
  logText(task('fix-alpha')).split('\n').filter((l) => /alpha-walk failing/.test(l)).length === 2, task('fix-alpha').log);

// ---- 5. a clean check -------------------------------------------------------
console.log('a clean check');
const count = tasks().length;
out = runCheck([]);
check('files nothing', tasks().length === count, tasks().map((t) => t.id));
check('and says nothing failed', /nothing failing/.test(out), out);

// ---- 6. many unowned walks, still one task ----------------------------------
console.log('a check with several unowned walks and no standing task');
out = runCheck(['d-walk', 'e-walk', 'f-walk']);
const open = standing().filter((t) => t.status !== 'done');
check('opens exactly one task for all of them', tasks().length === count + 1 && open.length === 1, tasks().map((t) => t.id));

// ---- 7. the full sweep takes it over ----------------------------------------
console.log('the first full sweep after a check opened the task');
const latest = join(qdir, 'latest.json');
writeFileSync(latest, JSON.stringify({
  ended: '2026-09-30T00:00:00Z', seconds: 6000, walks: 653, passed: 652, failed: ['e-walk'],
  crashed: [], couldNotRun: 0, total: 653, complete: true, requests: [], log: 'run.log',
}));
out = execFileSync('queue/bin/sweep-report.mjs', [latest], { env, encoding: 'utf8' });
const after = tasks().find((t) => t.id === open[0].id);
check('the sweep writes onto the task the check opened', /Updated the standing task/.test(out), out);
check('it reads the check\'s list back and says which stopped failing',
  /Stopped failing since the last sweep \(2\): d-walk, f-walk/.test(after.notes), after.notes);
check('the check\'s own paragraph is replaced, not kept as somebody\'s writing',
  !/Opened by the rotating check/.test(after.notes), after.notes);

// ---- 8. the owner is waiting on a card --------------------------------------
// A walk written only onto a blocked task waits for the user to answer a card
// before anybody looks at it. On 2026-10-16 path-outline-align-walk sat failing
// on a task blocked since 2026-10-08.
console.log('a walk whose owner is blocked on a card, with no standing task open');
const fileOf = (id) => readdirSync(join(qdir, 'tasks')).map((p) => join(qdir, 'tasks', p, id + '.json'))
  .find((f) => { try { readFileSync(f); return true; } catch { return false; } });
const close = (id) => writeFileSync(fileOf(id), JSON.stringify({ ...task(id), status: 'done' }, null, 2) + '\n');
for (const t of standing().filter((t) => t.status !== 'done')) close(t.id);
put('fix-zeta', { walks: ['zeta-walk'], status: 'blocked' });
put('about-eta', { notes: 'eta-walk fails since the popover moved', status: 'blocked' });
out = runCheck(['zeta-walk', 'eta-walk', 'alpha-walk']);
const parked = standing().filter((t) => t.status !== 'done');
check('it opens the standing walk task, because nobody could pick the walk up otherwise',
  parked.length === 1, standing().map((t) => [t.id, t.status]));
check('  ...and that task is one a runner can claim', parked[0]?.status === 'pending', parked[0]?.status);
check('its notes list the blocked owner\'s walks as failing',
  /Failing walks \(2\): zeta-walk, eta-walk/.test(parked[0]?.notes || ''), parked[0]?.notes);
check('its log names who owns each one and that the owner is waiting on a card',
  /zeta-walk \(owned by fix-zeta, which is waiting on a card\)/.test(logText(parked[0] || {}))
  && /eta-walk \(owned by about-eta, which is waiting on a card\)/.test(logText(parked[0] || {})),
  parked[0]?.log);
check('the blocked owner is still told', /zeta-walk failing/.test(logText(task('fix-zeta'))), task('fix-zeta').log);
check('a walk whose owner is free still goes only to that owner',
  !/alpha-walk/.test(logText(parked[0] || {})) && /alpha-walk failing/.test(out + logText(task('fix-alpha'))),
  parked[0]?.log);
check('the check says where they went', /waiting on a card/.test(out) && /opened the standing walk task/.test(out), out);

console.log('the same walk the next check, with the standing task open');
out = runCheck(['zeta-walk']);
check('no second task is opened', standing().filter((t) => t.status !== 'done').length === 1, standing().map((t) => [t.id, t.status]));
check('the standing task is told again, with the owner named',
  logText(standing().find((t) => t.status !== 'done')).split('\n')
    .filter((l) => /zeta-walk \(owned by fix-zeta, which is waiting on a card\)/.test(l)).length === 2,
  standing().find((t) => t.status !== 'done')?.log);

console.log('a walk owned by one blocked task and one free one');
put('also-zeta', { walks: ['zeta-walk'] });
const zBefore = logText(standing().find((t) => t.status !== 'done'));
out = runCheck(['zeta-walk']);
check('is left to the free owner',
  logText(standing().find((t) => t.status !== 'done')) === zBefore && /zeta-walk failing/.test(logText(task('also-zeta'))),
  standing().find((t) => t.status !== 'done')?.log);
rmSync(fileOf('also-zeta'));

// ---- 9. the full sweep, same owner ------------------------------------------
console.log('a full sweep with a walk whose owner is blocked on a card');
writeFileSync(latest, JSON.stringify({
  ended: '2026-10-16T00:00:00Z', seconds: 6000, walks: 653, passed: 650, failed: ['zeta-walk', 'alpha-walk', 'e-walk'],
  crashed: [], couldNotRun: 0, total: 653, complete: true, requests: [], log: 'run.log',
}));
out = execFileSync('queue/bin/sweep-report.mjs', [latest], { env, encoding: 'utf8' });
const swept = standing().find((t) => t.status !== 'done');
check('the standing task takes it as its own',
  /This task owns 2: zeta-walk, e-walk/.test(swept?.notes || ''), swept?.notes);
check('  ...saying who owns it and that the owner is waiting on a card',
  /zeta-walk -> fix-zeta \(waiting on a card/.test(swept?.notes || ''), swept?.notes);
check('a walk a free task owns stays that task\'s',
  /alpha-walk -> fix-alpha \(that task says it owns this walk\)/.test(swept?.notes || ''), swept?.notes);

console.log('a full sweep that finds only a blocked owner\'s walk, with no standing task open');
close(swept.id);
writeFileSync(latest, JSON.stringify({
  ended: '2026-10-17T00:00:00Z', seconds: 6000, walks: 653, passed: 652, failed: ['zeta-walk'],
  crashed: [], couldNotRun: 0, total: 653, complete: true, requests: [], log: 'run.log',
}));
out = execFileSync('queue/bin/sweep-report.mjs', [latest], { env, encoding: 'utf8' });
const fresh = standing().filter((t) => t.status !== 'done');
check('it files a standing task a runner can claim', fresh.length === 1 && fresh[0].status === 'pending', fresh);
check('  ...which owns the walk', /This task owns (the other )?1: zeta-walk/.test(fresh[0]?.notes || ''), fresh[0]?.notes);

rmSync(qdir, { recursive: true, force: true });
console.log(failures ? '\n' + failures + ' FAILED' : '\nall good');
process.exit(failures ? 1 : 0);
