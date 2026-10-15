#!/usr/bin/env node
// Reads one walk's focus trace for queue/bin/focus-drill.sh: lines the canary's
// record of who had the front up against the walk's own step log, and says
// whether the walk took the person's keys anywhere it had not declared.
//
//   node queue/bin/focus-drill-read.mjs <trace.jsonl> <walk out dir> <began ms> \
//        <ended ms> <name> <walk exit code> <walk.json> "<walk-needs-the-mac says>"
//
// Prints the verdict line and the steps it blames, exits 1 for TOOK FOCUS.
// The drill for this reader is queue/bin/focus-drill-read-drill.mjs.
//
// Why the clock is careful. A drag step activates the probe the moment it
// starts, which is the moment the step before it wrote its log line: 0 to 27 ms
// later across forty drags measured on 2026-10-14. The walk's log times are
// seconds from the walk's start, so placing a canary moment on a step needs the
// walk's start on the wall clock. Until that day it was worked out as done.json's
// file time minus its `seconds`, which is rounded to 10 ms, and about one check
// in three that put a drag's own activation on the step before it and cried
// TOOK FOCUS (`a-clip-s-sound-is-linked-under-it-walk`, 3 of 10 runs). The walk
// now writes its start (`startedAtMS`), and the file-time guess is only the
// fallback for a probe built before it did. Even with an exact start the canary
// counts whole milliseconds, so an event up to DRAG_SLACK_MS ahead of a DECLARED
// drag's start is that drag's; nothing else gets any slack.
import { readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const DRAG_SLACK_MS = 50;

const MENU = 'a probe menu held the keys';
const NOT_KEY = 'canary window not key';

// The walk's start on the wall clock, in ms: exact when the walk wrote it,
// otherwise done.json's file time less its rounded `seconds`.
export function walkZero(done, doneMtimeMs) {
  if (typeof done?.startedAtMS === 'number') return done.startedAtMS;
  return doneMtimeMs - (done?.seconds ?? 0) * 1000;
}

// lines: canary trace records; log: the walk's log.json; zero: walkZero(...);
// script: the walk's steps; expected: what walk-needs-the-mac.mjs printed;
// began/ended: the wall clock either side of the walk.
export function readFocus({ lines, log, zero, script = [], expected = '', began, ended }) {
  const canaryPid = lines.find(l => l.kind === 'start')?.pid;
  // Where the walk was, on the wall clock, from its own log. A log line is
  // written as a step FINISHES, so whatever happened after step N's line and
  // before step N+1's belongs to step N+1, named from the walk's own script.
  const done = [];
  if (zero != null) for (const e of log || []) if (e.step > 0) done.push({ step: e.step, ms: zero + e.t * 1000 });
  // A real drag takes the front on purpose for as long as the button is down
  // (walk-needs-the-mac.mjs names those steps); a theft anywhere else in the
  // walk, or at a drag step the walk did not declare, is still a theft.
  const declared = new Set((expected.match(/step \d+ \((?:windowDrag|dragGrip)/g) || []).map(s => +s.match(/\d+/)[0]));
  // When step N starts: the moment the latest step before it finished.
  const startOf = n => Math.max(-Infinity, ...done.filter(d => d.step < n).map(d => d.ms));
  const stepAt = ms => {
    let last = 0;
    for (const d of done) if (d.ms <= ms && d.step > last) last = d.step;
    let running = last + 1;
    // A declared drag starting a hair after this moment owns it: its own
    // activation, stamped a millisecond early, or a step clock a beat late.
    for (const n of declared) {
      if (n <= running) continue;
      const start = startOf(n);
      if (start >= ms && start - ms <= DRAG_SLACK_MS) { running = n; break; }
    }
    const what = script[running - 1]?.do;
    return what ? `step ${running} (${what})` : last ? `after step ${last}` : 'launch and setup';
  };
  const inWalk = l => l.ms >= +began && l.ms <= +ended;
  const took = new Map();
  const note = (ms, why) => {
    const at = stepAt(ms);
    if (!took.has(at)) took.set(at, new Set());
    took.get(at).add(why);
  };
  let lost = 0, ticks = 0, covered = 0;
  for (const l of lines.filter(inWalk)) {
    if (l.kind === 'activate' && l.pid !== canaryPid) note(l.ms, `activated ${l.app}`);
    if (l.kind !== 'tick') continue;
    ticks++;
    if (!l.landed) {
      lost++;
      const menu = (l.probe || []).some(p => p.layer >= 101);
      note(l.ms, menu ? MENU : !l.active ? `front was ${l.front}` : NOT_KEY);
    }
    if ((l.probe || []).some(p => p.above && p.layer < 101 && (p.alpha ?? 1) > 0)) { covered++; note(l.ms, 'probe window above the canary'); }
  }
  // A walk that photographs an open menu takes the keys for that picture and
  // nothing else; anything more than the menu (another app active, the walk's
  // window over the canary) is still a theft.
  const menuOnly = why => [...why].every(w => w === MENU || w === NOT_KEY);
  const onlyMenus = [...took.values()].every(menuOnly);
  const wholeWalk = /setup front/.test(expected);
  const asDeclared = wholeWalk || [...took.entries()].every(([at, why]) =>
    menuOnly(why) || declared.has(+((at.match(/^step (\d+)/) || [])[1])));
  const verdict = !took.size ? 'clean' : expected && onlyMenus ? 'menu shown'
    : expected && asDeclared ? 'as declared' : 'TOOK FOCUS';
  return { verdict, lost, ticks, covered, took };
}

export function report(name, code, expected, r) {
  const out = [`${name.padEnd(48)} ${r.verdict.padEnd(10)} ${r.lost}/${r.ticks} ticks lost, ${r.covered} covered, walk exit ${code}`];
  if (r.verdict === 'menu shown' || r.verdict === 'as declared') out.push(`    expected: it ${expected}`);
  for (const [at, why] of r.took) out.push(`    ${at}: ${[...why].join('; ')}`);
  return out.join('\n');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [trace, out, began, ended, name, code, walk, expected = ''] = process.argv.slice(2);
  const lines = readFileSync(trace, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l));
  let script = [], log = [], zero = null;
  try { script = JSON.parse(readFileSync(walk, 'utf8')).steps || []; } catch {}
  try {
    log = JSON.parse(readFileSync(out + '/log.json', 'utf8'));
    const done = JSON.parse(readFileSync(out + '/done.json', 'utf8'));
    zero = walkZero(done, statSync(out + '/done.json').mtimeMs);
  } catch {}
  const r = readFocus({ lines, log, zero, script, expected, began, ended });
  console.log(report(name, code, expected, r));
  process.exit(r.verdict === 'TOOK FOCUS' ? 1 : 0);
}
