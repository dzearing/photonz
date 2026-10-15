#!/usr/bin/env node
// Drill for the reader behind queue/bin/focus-drill.sh (focus-drill-read.mjs).
//
// About one standing focus check in three cried A WALK TOOK THE PERSON'S FOCUS
// about a-clip-s-sound-is-linked-under-it-walk, blaming the step just before
// each of its drags. Reproduced on 2026-10-14: 3 of 10 runs. The probe was
// activating at the START of each drag, 0 to 27 ms after the step before it
// logged, and the walk's start was rebuilt from done.json's file time less a
// `seconds` rounded to 10 ms, so a few milliseconds of error put the drag's own
// activation on the step before. The walk now writes its start exactly
// (`startedAtMS`) and an event a hair ahead of a declared drag is that drag's.
//
// This holds both halves:
//   1. the real failing run, kept as a fixture, reads `as declared`
//   2. the alarm still fires for a theft outside a declared drag: in the
//      middle of an ordinary step, well ahead of a drag, or right before a drag
//      the walk never declared
//
//   node queue/bin/focus-drill-read-drill.mjs
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFocus, walkZero, DRAG_SLACK_MS } from './focus-drill-read.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = dirname(dirname(HERE));

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};
const blamed = r => [...r.took.keys()];

// --- 1. the real run --------------------------------------------------------
console.log('the run that cried theft on 2026-10-14');
const fx = JSON.parse(readFileSync(join(HERE, 'fixtures', 'focus-trace-linked-sound.json'), 'utf8'));
const walk = JSON.parse(readFileSync(join(REPO, 'Scripts/playtest/a-clip-s-sound-is-linked-under-it-walk.json'), 'utf8'));
const expected = 'needs the Mac to itself at step 11 (windowDrag, a real drag), step 20 (windowDrag, a real drag), '
  + 'step 26 (windowDrag, a real drag), step 38 (windowDrag, a real drag)';
const real = (lines, zero = walkZero({ seconds: fx.seconds }, fx.doneMtimeMs)) =>
  readFocus({ lines, log: fx.log, zero, script: walk.steps, expected, began: 0, ended: Infinity });
{
  const r = real(fx.lines);
  check('reads as declared', r.verdict === 'as declared', r.verdict);
  check('blames only the four drags', JSON.stringify(blamed(r)) === JSON.stringify(
    ['step 11 (windowDrag)', 'step 20 (windowDrag)', 'step 26 (windowDrag)', 'step 38 (windowDrag)']), blamed(r));
  check('still counts the 20 ticks the drags took', r.lost === 20, r.lost);
}

// The same run with one more activation, in the middle of step 5 (`tool`).
{
  const zero = walkZero({ seconds: fx.seconds }, fx.doneMtimeMs);
  const at = n => zero + fx.log.find(e => e.step === n).t * 1000;
  const pid = fx.lines.find(l => l.kind === 'activate').pid;
  const mid5 = (at(4) + at(5)) / 2;
  const extra = { kind: 'activate', ms: Math.round(mid5), pid, app: 'com.dzearing.photonz.probe' };
  const r = real([...fx.lines, extra]);
  check('an activation inside an ordinary step reads TOOK FOCUS', r.verdict === 'TOOK FOCUS', r.verdict);
  check('and blames that step', blamed(r).includes('step 5 (tool)'), blamed(r));
}

// --- 2. made-up walks with an exact clock -------------------------------------
console.log('made-up walks');
// Four steps, a second each; step 3 is a drag.
const script = [{ do: 'wait' }, { do: 'snapshot' }, { do: 'windowDrag' }, { do: 'wait' }];
const zero = 1_000_000;
const log = [1, 2, 3, 4].map(step => ({ step, t: step }));
const dragDeclared = 'needs the Mac to itself at step 3 (windowDrag, a real drag)';
const startOf3 = zero + 2000;
const run = (ms, exp = dragDeclared) => readFocus({
  lines: [{ kind: 'start', ms: zero - 500, pid: 1 }, { kind: 'activate', ms, pid: 2, app: 'probe' }],
  log, zero, script, expected: exp, began: 0, ended: Infinity,
});
{
  const r = run(startOf3 + 3);
  check('activation just after a declared drag starts: as declared', r.verdict === 'as declared', r.verdict);
}
{
  const r = run(startOf3 - 2);
  check('activation 2 ms ahead of a declared drag: as declared, on the drag',
    r.verdict === 'as declared' && blamed(r)[0] === 'step 3 (windowDrag)', [r.verdict, blamed(r)]);
}
{
  const r = run(startOf3 - DRAG_SLACK_MS - 10);
  check(`activation ${DRAG_SLACK_MS + 10} ms ahead of a declared drag: TOOK FOCUS on the step before`,
    r.verdict === 'TOOK FOCUS' && blamed(r)[0] === 'step 2 (snapshot)', [r.verdict, blamed(r)]);
}
{
  const r = run(zero + 1500);
  check('activation in the middle of an ordinary step: TOOK FOCUS', r.verdict === 'TOOK FOCUS', r.verdict);
}
{
  const r = run(startOf3 - 2, 'needs the Mac to itself at step 4 (windowDrag, a real drag)');
  check('2 ms ahead of a drag the walk never declared: TOOK FOCUS', r.verdict === 'TOOK FOCUS', r.verdict);
}
{
  const r = run(startOf3 - 2, '');
  check('a walk that declares nothing gets no slack at all', r.verdict === 'TOOK FOCUS', r.verdict);
}

// --- 3. the clock ------------------------------------------------------------
console.log('the walk clock');
check('the start the walk wrote wins', walkZero({ seconds: 15.8, startedAtMS: 1234.5 }, 99999) === 1234.5);
check('a probe built before it falls back to file time less seconds', walkZero({ seconds: 2 }, 5000) === 3000);

console.log(failures ? `${failures} FAILED` : 'all ok');
process.exit(failures ? 1 : 0);
