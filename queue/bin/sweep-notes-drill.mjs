#!/usr/bin/env node
// Drill for the notes on the standing failing-walks task (sweep-notes.mjs and
// the writer in sweep-report.mjs).
//
// The thing being protected is small and easy to break again: a sweep may
// rewrite its own list and nothing else. On 2026-09-13 a manager pass wrote a
// triage of twelve failing walks into those notes and the next sweep replaced
// all of it, leaving a task whose acceptance said "the six walks in the notes"
// over notes that named thirteen. Run this after touching either file.
//
//   node queue/bin/sweep-notes-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

const REPO = resolve(import.meta.dirname, '../..');
const dir = mkdtempSync(join(tmpdir(), 'photonz-sweep-notes-'));
mkdirSync(join(dir, 'tasks', 'p2-normal'), { recursive: true });
mkdirSync(join(dir, 'sweep'), { recursive: true });

const notes = await import('./sweep-notes.mjs');
let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

const result = (over = {}) => ({
  began: '2026-09-13T10:00:00Z', ended: '2026-09-13T11:00:00Z', seconds: 3600,
  walks: 10, passed: 8, failed: ['alpha-walk', 'beta-walk'],
  requests: [{ by: 'some-task', why: 'I changed the composite path' }],
  log: 'queue/sweep/r1.log', complete: true, timedOut: false, ...over,
});

const HAND = 'TRIAGED by the manager pass: alpha-walk belongs to another task; beta-walk is a real break.';

// ---- splitting the two parts ------------------------------------------------
console.log('what a person wrote');
{
  const first = notes.mergeNotes('', result());
  check('a fresh block carries both markers',
    first.includes(notes.MACHINE_BEGIN) && first.includes(notes.MACHINE_END));
  check('nothing written yet means nothing trailing the end marker',
    notes.humanPart(first) === '', notes.humanPart(first));

  const withHand = `${first}\n\n${HAND}\n`;
  check('a hand-written paragraph is read back whole', notes.humanPart(withHand) === HAND, notes.humanPart(withHand));

  const second = notes.mergeNotes(withHand, result({ ended: '2026-09-13T15:00:00Z', failed: ['beta-walk', 'gamma-walk'], log: 'queue/sweep/r2.log' }));
  check('the next sweep keeps the paragraph', second.includes(HAND));
  check('...and updates the list', second.includes('Failing walks (2): beta-walk, gamma-walk'));
  check('...and drops the old list', !second.includes('alpha-walk, beta-walk'));
  check('...and does not stack up a second block',
    second.split(notes.MACHINE_BEGIN).length === 2 && second.split(notes.MACHINE_END).length === 2);
}

// ---- notes written before the markers existed -------------------------------
console.log('notes from before the markers');
{
  const legacy = [
    'Last sweep 2026-09-13T09:00:00Z: 8 of 10 walks passed in 60 minutes.',
    '',
    'Failing walks (2): alpha-walk, beta-walk',
    '',
    'Full output: queue/sweep/old.log. Re-run one of them on its own with',
    'Scripts/playtest.sh Scripts/playtest/<name>.json --no-build, which takes about ten seconds.',
    '',
    'Sweep asked for by: an older task: some reason',
    '',
    HAND,
  ].join('\n');
  check('the old machine block is recognised and dropped', notes.humanPart(legacy) === HAND, notes.humanPart(legacy));
  check('the old list is still read back for the diff',
    notes.previousFailures(legacy).join() === 'alpha-walk,beta-walk', notes.previousFailures(legacy));
  const merged = notes.mergeNotes(legacy, result({ failed: ['beta-walk'] }));
  check('migrating keeps the paragraph', merged.includes(HAND));
  check('migrating leaves one machine block', merged.split('Last sweep ').length === 2);

  const allHuman = 'Somebody typed a plain note here and no sweep has ever run.';
  check('notes that were never machine-made are all a person\'s',
    notes.humanPart(allHuman) === allHuman, notes.humanPart(allHuman));
  check('...and survive the first sweep', notes.mergeNotes(allHuman, result()).includes(allHuman));
}

// ---- a walk that stopped failing --------------------------------------------
console.log('walks that stopped failing');
{
  const first = notes.mergeNotes('', result());
  const second = notes.mergeNotes(first, result({ failed: ['beta-walk'] }));
  check('a walk that passes this time is named, not just dropped',
    second.includes('Stopped failing since the last sweep (1): alpha-walk'), second);
  const third = notes.mergeNotes(second, result({ failed: ['beta-walk'] }));
  check('nothing stopped failing means no line about it', !third.includes('Stopped failing'));
  const cut = notes.mergeNotes(first, result({ failed: ['beta-walk'], complete: false }));
  check('a sweep that was cut short claims nothing stopped failing', !cut.includes('Stopped failing'));
  check('...and says it did not finish', cut.includes('DID NOT FINISH'));

  // A sweep that ran only the walks a locked screen cannot touch. Its failures
  // are real and get listed; everything it could not reach must not read as
  // passing, and a walk missing from the list must not read as fixed.
  // `first` was a whole sweep with alpha-walk and gamma-walk failing. The
  // partial below runs beta-walk and gamma-walk and is refused alpha-walk.
  const whole = notes.mergeNotes('', result({ failed: ['alpha-walk', 'gamma-walk'] }));
  const part = notes.mergeNotes(whole, result({
    failed: ['beta-walk'], complete: false, partial: true, screenLocked: true,
    walks: 224, passed: 222, couldNotRun: 297, total: 521,
    ranWalks: ['beta-walk', 'gamma-walk'],
  }));
  check('a partial sweep says it ran only the part a lock cannot touch',
    /ran only the part of the walk set a locked screen cannot touch/.test(part), part);
  check('...and says how much of the set that was', part.includes('224 of 521 walks ran'), part);
  check('...and counts what the lock refused', part.includes('The other 297 were refused'), part);
  check('...and says the list is not the state of the set',
    part.includes('not the state of the walk set'), part);
  check('...and still names the walk that failed in it', part.includes('Failing walks (1): beta-walk'), part);
  check('...and claims nothing stopped failing', !part.includes('Stopped failing'), part);
  // The list this replaces was the last WHOLE check. A partial that quietly
  // drops the walks it never ran would read as the app healing overnight.
  check('...and carries across a walk it never ran that was failing before',
    /Not run this time and still failing from the last check \(1\): alpha-walk/.test(part), part);
  check('...and a walk it DID run and passed is gone from both lists',
    !part.includes('gamma-walk'), part);
  check('a carried-over walk is still read back as a previous failure next time',
    notes.previousFailures(part).sort().join() === 'alpha-walk,beta-walk', notes.previousFailures(part));
  check('...with no em dash', !part.includes('\u2014'), part);
}

// ---- failures another task already owns -------------------------------------
console.log('walks another task owns, guessed from its wording');
{
  const tasks = [
    { id: 'standing', status: 'pending', title: 'Walks that fail in the full sweep', notes: 'alpha-walk beta-walk' },
    { id: 'the-effect-panel-forgets', status: 'pending', title: 'The effect panel forgets', notes: 'reproduced with alpha-walk', acceptance: [] },
    { id: 'long-done', status: 'done', title: 'Old fix', notes: 'beta-walk' },
  ];
  const owners = notes.ownersOfWalks(['alpha-walk', 'beta-walk'], tasks, 'standing');
  check('the open task that names a walk is found', owners['alpha-walk']?.ids.join() === 'the-effect-panel-forgets', owners);
  check('...and is marked as a guess, not a claim', owners['alpha-walk']?.declared === false, owners);
  check('the standing task does not own its own list', !owners['standing']);
  check('a finished task does not own anything', owners['beta-walk'] === undefined, owners);

  const text = notes.mergeNotes('', result(), owners);
  check('the block says which failure belongs elsewhere', text.includes('alpha-walk -> the-effect-panel-forgets'));
  check('...and says the ownership was guessed', text.includes('alpha-walk -> the-effect-panel-forgets (guessed from its wording'));
  check('...and says how a task stops being guessed at', text.includes('queue.mjs walks <task id>'));
  check('...and says what is left for this task', text.includes('This task owns the other 1: beta-walk'));
}

// ---- a task that SAYS which walks are its own -------------------------------
// The guess is only as good as the words, and walk names turn up in tasks that
// are not about them. On 2026-09-14 dock-picked-first-walk came out owned by
// three open tasks, one of which was the task about this very problem, quoting
// the walk as an example. So a task can say, and what it says wins.
console.log('walks a task says are its own');
{
  const declaring = { id: 'the-effect-panel-forgets', status: 'pending', title: 'The effect panel forgets', walks: ['alpha-walk'], notes: 'also mentions beta-walk in passing' };
  const mentioner = { id: 'a-task-about-the-list', status: 'pending', title: 'A task about the list', notes: 'for example alpha-walk came out owned by two tasks' };
  const standing = { id: 'standing', status: 'pending', title: 'Walks that fail in the full sweep', notes: 'alpha-walk beta-walk' };
  const owners = notes.ownersOfWalks(['alpha-walk', 'beta-walk'], [standing, declaring, mentioner], 'standing');

  check('a task that says it owns a walk owns it', owners['alpha-walk']?.ids.join() === 'the-effect-panel-forgets', owners);
  check('...and the block says the task claimed it', notes.mergeNotes('', result(), owners).includes('alpha-walk -> the-effect-panel-forgets (that task says it owns this walk)'));
  check('a task that only quotes the walk as an example does not own it',
    !owners['alpha-walk']?.ids.includes('a-task-about-the-list'), owners);
  check('a task that has said is not also read for names it did not say',
    owners['beta-walk'] === undefined, owners);

  // Saying nothing is the old behaviour, unchanged: a walk nobody claims is
  // still guessed at, because a guess beats an empty list.
  const half = notes.ownersOfWalks(['beta-walk'], [standing, declaring, { id: 'says-nothing', status: 'pending', title: 'Says nothing', notes: 'broke in beta-walk' }], 'standing');
  check('a walk nobody claims still falls back to the wording',
    half['beta-walk']?.ids.join() === 'says-nothing' && half['beta-walk'].declared === false, half);

  // An empty list is a statement: "I talk about walks and own none of them".
  const quiet = notes.ownersOfWalks(['alpha-walk'], [standing, { id: 'a-task-about-the-list', status: 'pending', title: 'A task about the list', walks: [], notes: 'for example alpha-walk' }], 'standing');
  check('a task that says it owns none of them owns none of them', quiet['alpha-walk'] === undefined, quiet);

  // A declaration written the way it was run.
  const pasted = notes.ownersOfWalks(['alpha-walk'], [standing, { id: 'pasted', status: 'pending', title: 'Pasted', walks: ['Scripts/playtest/alpha-walk.json'] }], 'standing');
  check('a walk declared as the path that was run is the same walk',
    pasted['alpha-walk']?.ids.join() === 'pasted', pasted);
  check('declaredWalks says nothing when the task has not said', notes.declaredWalks({ id: 'x' }) === null);
  check('declaredWalks reads a comma-separated string too',
    notes.declaredWalks({ walks: 'alpha-walk, beta-walk.json' }).join() === 'alpha-walk,beta-walk', notes.declaredWalks({ walks: 'alpha-walk, beta-walk.json' }));

  // ...and a finished task cannot claim one either, however loudly it says so.
  const shut = notes.ownersOfWalks(['alpha-walk'], [standing, { id: 'long-done', status: 'done', walks: ['alpha-walk'] }], 'standing');
  check('a finished task owns nothing even when it said so', shut['alpha-walk'] === undefined, shut);
}

// ---- declaring through the CLI ----------------------------------------------
console.log('a task declaring its walks through queue.mjs');
{
  const cli = (...a) => execFileSync('node', [join(REPO, 'queue/bin/queue.mjs'), ...a],
    { env: { ...process.env, PHOTONZ_QUEUE_DIR: dir }, encoding: 'utf8' }).trim();
  const id = cli('addjson', JSON.stringify({ title: 'A walk drill task', goal: 'g', acceptance: ['a'], notes: 'mentions alpha-walk in passing' }));
  check('a new task has said nothing about walks', cli('walks', id).startsWith('has not said'), cli('walks', id));
  cli('walks', id, 'Scripts/playtest/beta-walk.json', 'beta-walk');
  const file = JSON.parse(readFileSync(join(dir, 'tasks', 'p2-normal', id + '.json'), 'utf8'));
  check('what it owns is stored by name, once', JSON.stringify(file.walks) === '["beta-walk"]', file.walks);
  check('...and the task log says so', (file.log || []).some((e) => e.note === 'owns these walks: beta-walk'), file.log);
  cli('walks', id, '--none');
  check('a task can say it owns none of them',
    JSON.stringify(JSON.parse(readFileSync(join(dir, 'tasks', 'p2-normal', id + '.json'), 'utf8')).walks) === '[]');
  check('...and reads back as having said it', cli('walks', id).startsWith('owns no walks'), cli('walks', id));
}

// ---- end to end, the way the sweep runs it ----------------------------------
console.log('two sweeps through sweep-report.mjs');
{
  const write = (name, obj) => {
    const p = join(dir, 'sweep', name);
    writeFileSync(p, JSON.stringify(obj));
    return p;
  };
  const r1 = write('r1.json', result());
  const r2 = write('r2.json', result({ ended: '2026-09-13T15:00:00Z', failed: ['beta-walk', 'gamma-walk'], log: 'queue/sweep/r2.log' }));
  const run = (file) => execFileSync('node', [join(REPO, 'queue/bin/sweep-report.mjs'), file],
    { env: { ...process.env, PHOTONZ_QUEUE_DIR: dir }, encoding: 'utf8' });

  run(r1);
  const file = join(dir, 'tasks', 'p2-normal', 'walks-that-fail-in-the-full-sweep.json');
  let task = JSON.parse(readFileSync(file, 'utf8'));
  check('the first sweep files the standing task', task.title === 'Walks that fail in the full sweep');
  check('...with a marked block', task.notes.includes(notes.MACHINE_BEGIN));

  task.notes += `\n\n${HAND}\n`;
  writeFileSync(file, JSON.stringify(task, null, 2));

  run(r2);
  task = JSON.parse(readFileSync(file, 'utf8'));
  check('the second sweep keeps the paragraph', task.notes.includes(HAND), task.notes);
  check('...updates the walk list', task.notes.includes('gamma-walk') && !task.notes.includes('alpha-walk,'), task.notes);
  check('...names the walk that stopped failing', task.notes.includes('Stopped failing since the last sweep (1): alpha-walk'), task.notes);
  check('...and still logs the run', (task.log || []).some((e) => e.note.startsWith('sweep 2026-09-13T15:00:00Z')), task.log);

  // A walk that fails in the part a locked screen CAN run is a real failure and
  // has to be claimable, exactly as in a full sweep. This is the whole point of
  // running the lock-safe part at all: before 2026-09-17 a locked Mac filed
  // nothing, so a regression in one of those walks waited for whenever the
  // screen was next unlocked.
  const r3 = write('r3.json', result({
    ended: '2026-09-17T18:00:00Z', failed: ['beta-walk', 'delta-walk'], log: 'queue/sweep/r3.log',
    complete: false, partial: true, screenLocked: true,
    walks: 224, passed: 222, couldNotRun: 297, total: 521,
  }));
  run(r3);
  task = JSON.parse(readFileSync(file, 'utf8'));
  check('a partial sweep still names its failures on the standing task',
    task.notes.includes('Failing walks (2): beta-walk, delta-walk'), task.notes);
  check('...and says the list came from part of the set',
    task.notes.includes('ran only the part of the walk set a locked screen cannot touch'), task.notes);
  check('...and does not claim the walks it never ran stopped failing',
    !task.notes.includes('Stopped failing'), task.notes);
  check('...and logs the run like any other', (task.log || []).some((e) => e.note.startsWith('sweep 2026-09-17T18:00:00Z')), task.log);
}

// ---- the standing task survives being renamed -------------------------------
// A sweep used to find its standing task by TITLE. The daily triage pass renames
// tasks so a title names an outcome, and on 2026-09-17 it renamed this one to
// "Every walk in the sweep either passes or is corrected". The next sweep could
// no longer see it, filed a second standing task beside it, and the triage of
// four failing walks sat on the task nothing was writing to any more.
console.log('a renamed standing task is still the standing task');
{
  const dir2 = mkdtempSync(join(tmpdir(), 'photonz-sweep-renamed-'));
  mkdirSync(join(dir2, 'tasks', 'p2-normal'), { recursive: true });
  mkdirSync(join(dir2, 'sweep'), { recursive: true });
  const write = (name, obj) => {
    const p = join(dir2, 'sweep', name);
    writeFileSync(p, JSON.stringify(obj));
    return p;
  };
  const run = (file) => execFileSync('node', [join(REPO, 'queue/bin/sweep-report.mjs'), file],
    { env: { ...process.env, PHOTONZ_QUEUE_DIR: dir2 }, encoding: 'utf8' });

  run(write('r1.json', result()));
  const file = join(dir2, 'tasks', 'p2-normal', 'walks-that-fail-in-the-full-sweep.json');
  let task = JSON.parse(readFileSync(file, 'utf8'));
  check('the task the sweep files is marked as the standing one', task.standing === 'walk-sweep', task.standing);

  task.title = 'Every walk in the sweep either passes or is corrected';
  writeFileSync(file, JSON.stringify(task, null, 2));

  run(write('r2.json', result({ ended: '2026-09-13T15:00:00Z', failed: ['gamma-walk'], log: 'queue/sweep/r2.log' })));
  const filed = readdirSync(join(dir2, 'tasks', 'p2-normal'));
  check('a sweep after the rename files nothing new', filed.length === 1, filed);
  task = JSON.parse(readFileSync(file, 'utf8'));
  check('...and writes its result to the renamed task', task.notes.includes('Failing walks (1): gamma-walk'), task.notes);
  check('...keeping the title the triage gave it', task.title === 'Every walk in the sweep either passes or is corrected', task.title);

  // The task that was filed before the marker existed is the one this had to
  // rescue, so a sweep also adopts an unmarked open task with the old title.
  rmSync(file);
  const legacy = {
    id: 'walks-that-fail-in-the-full-sweep', title: 'Walks that fail in the full sweep',
    epic: 'unmanned-loop', priority: 'p2-normal', seq: 10, status: 'pending', release: 'next', area: 'queue',
    created: '2026-09-12T17:04:44.529Z', updated: '2026-09-12T17:04:44.529Z', deps: [], blockedBy: [],
    notes: 'Last sweep 2026-09-12T17:00:00Z: 9 of 10 walks passed in 60 minutes.', acceptance: [], log: [],
  };
  writeFileSync(file, JSON.stringify(legacy, null, 2));
  run(write('r3.json', result({ ended: '2026-09-13T17:00:00Z', failed: ['delta-walk'], log: 'queue/sweep/r3.log' })));
  check('an unmarked task with the old title is adopted, not duplicated',
    readdirSync(join(dir2, 'tasks', 'p2-normal')).length === 1, readdirSync(join(dir2, 'tasks', 'p2-normal')));
  task = JSON.parse(readFileSync(file, 'utf8'));
  check('...and is marked so the next rename cannot orphan it', task.standing === 'walk-sweep', task.standing);

  // Two open tasks both marked: the sweep writes to the one with the history.
  const younger = join(dir2, 'tasks', 'p2-normal', 'walks-that-fail-in-the-full-sweep-9.json');
  writeFileSync(younger, JSON.stringify({ ...legacy, id: 'walks-that-fail-in-the-full-sweep-9', standing: 'walk-sweep',
    created: '2026-09-17T22:58:46.604Z', notes: '' }, null, 2));
  run(write('r4.json', result({ ended: '2026-09-13T19:00:00Z', failed: ['epsilon-walk'], log: 'queue/sweep/r4.log' })));
  check('with two marked tasks open the sweep writes to the older one',
    JSON.parse(readFileSync(file, 'utf8')).notes.includes('epsilon-walk')
    && !JSON.parse(readFileSync(younger, 'utf8')).notes.includes('epsilon-walk'));

  rmSync(dir2, { recursive: true, force: true });
}

rmSync(dir, { recursive: true, force: true });
console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
