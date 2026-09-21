#!/usr/bin/env node
// Where the loop's wall clock actually went.
//
// The loop has one job: build the thing in focus. Everything else it does is
// overhead, and overhead that nobody measures grows. On 2026-09-21 it had
// grown until the walk sweep was taking well over half of every day, which is
// why this exists: not to argue about the sweep, but to make its cost a number
// anybody can print.
//
// Everything here is read out of queue/history.jsonl, which the loop already
// writes, so there is nothing new to keep up to date:
//
//   a task      task_started -> task_done | task_blocked | task_dropped
//   a sweep     sweep_pass, which carries the seconds it took, so the span is
//               [t - seconds, t]
//   a slice     slice_pass, the same shape, for the rotating partial check
//
// The daily digest and the manager pass are runner runs that leave no span of
// their own, so they land in "between" along with startup, git work and the
// loop sitting with nothing to claim.
//
// Spans are clipped to the window and merged, so a task that began before the
// window opened counts only the part inside it, and two things that overlap
// (they should not, but a recovered sweep can) are not counted twice.
// Everything left over is "between": runner startup, the manager pass, git
// work, and the loop sitting with nothing to claim.
//
//   queue/bin/loop-day.mjs               the last 24 hours
//   queue/bin/loop-day.mjs --hours 48    a different window
//   queue/bin/loop-day.mjs --since 2026-09-20T00:00:00Z
//   queue/bin/loop-day.mjs --json        the same, for a script
//
// Drill: queue/bin/loop-day-drill.mjs
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// What each kind of span is called when it is reported, in the order a reader
// wants them: the work first, then the things that are not the work.
export const CATEGORIES = ['tasks', 'sweeps', 'slices'];

export function readEvents(repo = REPO) {
  const file = join(repo, 'queue', 'history.jsonl');
  if (!existsSync(file)) return [];
  const out = [];
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (o && o.t && o.ev) out.push(o);
  }
  return out;
}

const ms = (t) => Date.parse(t);

// Turn the event stream into spans.
//
// The loop does ONE thing at a time: it claims a task, or it runs a sweep, or
// it runs the digest, never two at once. So a task's span ends at whichever
// comes first, its own terminal event or the next thing the loop started. That
// is not a nicety. queue/bin/sweep-report.mjs reopens the standing walk task
// every time a sweep files failures onto it, which puts a task_started in the
// history with no terminal event after it, and read literally that one task
// swallowed eight hours and three sweeps of 2026-09-20.
export function spansFrom(events, { now = Date.now() } = {}) {
  const runs = [];      // sweeps and slices, which carry their own length
  const marks = [];     // { t, type: 'start'|'end', id }
  for (const e of events) {
    const t = ms(e.t);
    if (!Number.isFinite(t)) continue;
    switch (e.ev) {
      case 'task_started':
        marks.push({ t, type: 'start', id: e.id });
        break;
      case 'task_done':
      case 'task_blocked':
      case 'task_dropped':
      case 'task_reset':
      case 'runner_failed':
        marks.push({ t, type: 'end', id: e.id });
        break;
      case 'sweep_pass':
      case 'slice_pass': {
        const secs = Number(e.seconds) || 0;
        if (secs > 0) {
          runs.push({
            kind: e.ev === 'sweep_pass' ? 'sweeps' : 'slices',
            from: t - secs * 1000, to: t,
            walks: Number(e.walks) || 0, partial: !!e.partial,
          });
        }
        break;
      }
      default:
        break;
    }
  }
  marks.sort((a, b) => a.t - b.t);
  runs.sort((a, b) => a.from - b.from);

  const spans = runs.slice();
  for (let i = 0; i < marks.length; i++) {
    if (marks[i].type !== 'start') continue;
    const from = marks[i].t;
    // Its own ending, if one ever comes.
    let to = now;
    for (let j = i + 1; j < marks.length; j++) {
      if (marks[j].id === marks[i].id && marks[j].type === 'end') { to = marks[j].t; break; }
      if (marks[j].type === 'start' && marks[j].id !== marks[i].id) { to = marks[j].t; break; }
    }
    // ...or the next thing the loop started, whichever is sooner.
    const nextRun = runs.find((r) => r.from > from);
    if (nextRun && nextRun.from < to) to = nextRun.from;
    spans.push({ kind: 'tasks', from, to, id: marks[i].id, open: to === now });
  }
  return spans.filter((s) => s.to > s.from);
}

// Clip to the window and merge overlaps WITHIN a kind, so the shares add up to
// at most the window and a double-recorded run cannot inflate one.
function coverage(spans, kind, from, to) {
  const clipped = spans
    .filter((s) => s.kind === kind)
    .map((s) => [Math.max(s.from, from), Math.min(s.to, to)])
    .filter(([a, b]) => b > a)
    .sort((a, b) => a[0] - b[0]);
  let total = 0, curA = null, curB = null;
  for (const [a, b] of clipped) {
    if (curA === null) { curA = a; curB = b; continue; }
    if (a <= curB) { curB = Math.max(curB, b); continue; }
    total += curB - curA; curA = a; curB = b;
  }
  if (curA !== null) total += curB - curA;
  return total;
}

export function loopDay({ events, from, to }) {
  const spans = spansFrom(events, { now: to });
  const window = to - from;
  const parts = {};
  for (const kind of CATEGORIES) parts[kind] = coverage(spans, kind, from, to);
  const accounted = Object.values(parts).reduce((a, b) => a + b, 0);
  parts.between = Math.max(0, window - accounted);
  const counts = {
    sweeps: spans.filter((s) => s.kind === 'sweeps' && s.to > from && s.from < to).length,
    slices: spans.filter((s) => s.kind === 'slices' && s.to > from && s.from < to).length,
    tasks: new Set(spans.filter((s) => s.kind === 'tasks' && s.to > from && s.from < to).map((s) => s.id)).size,
  };
  const share = {};
  for (const k of Object.keys(parts)) share[k] = window > 0 ? parts[k] / window : 0;
  return {
    from: new Date(from).toISOString(),
    to: new Date(to).toISOString(),
    windowMinutes: Math.round(window / 60000),
    minutes: Object.fromEntries(Object.entries(parts).map(([k, v]) => [k, Math.round(v / 60000)])),
    share,
    counts,
    sweepRuns: spans
      .filter((s) => s.kind === 'sweeps' && s.to > from && s.from < to)
      .map((s) => ({ ended: new Date(s.to).toISOString(), minutes: Math.round((s.to - s.from) / 60000), walks: s.walks, partial: s.partial })),
  };
}

const pct = (x) => `${(x * 100).toFixed(1)}%`;

export function sentences(r) {
  const out = [];
  out.push(`The loop's ${Math.round(r.windowMinutes / 60)} hours from ${r.from} to ${r.to}:`);
  out.push(`  tasks    ${String(r.minutes.tasks).padStart(5)}m  ${pct(r.share.tasks).padStart(6)}   ${r.counts.tasks} task(s)`);
  out.push(`  sweeps   ${String(r.minutes.sweeps).padStart(5)}m  ${pct(r.share.sweeps).padStart(6)}   ${r.counts.sweeps} full-set run(s)`);
  out.push(`  slices   ${String(r.minutes.slices).padStart(5)}m  ${pct(r.share.slices).padStart(6)}   ${r.counts.slices} rotating check(s)`);
  out.push(`  between  ${String(r.minutes.between).padStart(5)}m  ${pct(r.share.between).padStart(6)}   startup, digest, manager pass, idle`);
  const building = r.share.tasks;
  out.push(building > 0.5
    ? `The loop spent the majority of this window building: ${pct(building)} on tasks.`
    : `The loop did NOT spend the majority of this window building: ${pct(building)} on tasks, ${pct(r.share.sweeps + r.share.slices)} on walk checks.`);
  return out;
}

const isMain = process.argv[1] && process.argv[1].endsWith('loop-day.mjs');
if (isMain) {
  const argv = process.argv.slice(2);
  const arg = (name, dflt) => {
    const i = argv.indexOf(name);
    return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : dflt;
  };
  const to = argv.includes('--until') ? Date.parse(arg('--until')) : Date.now();
  const from = argv.includes('--since')
    ? Date.parse(arg('--since'))
    : to - Number(arg('--hours', 24)) * 3600 * 1000;
  const r = loopDay({ events: readEvents(), from, to });
  if (argv.includes('--json')) console.log(JSON.stringify(r, null, 2));
  else for (const line of sentences(r)) console.log(line);
}
