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
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
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
}

// ---- failures another task already owns -------------------------------------
console.log('walks another task owns');
{
  const tasks = [
    { id: 'standing', status: 'pending', title: 'Walks that fail in the full sweep', notes: 'alpha-walk beta-walk' },
    { id: 'the-effect-panel-forgets', status: 'pending', title: 'The effect panel forgets', notes: 'reproduced with alpha-walk', acceptance: [] },
    { id: 'long-done', status: 'done', title: 'Old fix', notes: 'beta-walk' },
  ];
  const owners = notes.ownersOfWalks(['alpha-walk', 'beta-walk'], tasks, 'standing');
  check('the open task that names a walk is found', owners['alpha-walk']?.join() === 'the-effect-panel-forgets', owners);
  check('the standing task does not own its own list', !owners['standing']);
  check('a finished task does not own anything', owners['beta-walk'] === undefined, owners);

  const text = notes.mergeNotes('', result(), owners);
  check('the block says which failure belongs elsewhere', text.includes('alpha-walk -> the-effect-panel-forgets'));
  check('...and says what is left for this task', text.includes('This task owns the other 1: beta-walk'));
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
}

rmSync(dir, { recursive: true, force: true });
console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
