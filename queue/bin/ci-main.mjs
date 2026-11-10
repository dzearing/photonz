#!/usr/bin/env node
// Whether the checks on main are passing, said where people and runners look.
//
// From 2026-11-03 to 2026-11-10 every push to main failed CI, 87 failures and
// five successes in two hundred runs, and nobody noticed for a week: the tests
// all passed, one step comparing the walk count in the docs with the real one
// failed, and nothing the loop showed or a runner read mentioned CI at all. A
// real failure would have hidden behind it the same way. So the loop reads the
// last finished run on main between tasks and this file turns it into:
//
//   the dashboard   a line under the heartbeat and a strip naming the step
//   the loop        its banner and queue/loop.log, every task while it is red
//   the runner      a paragraph at the top of its prompt, before it starts
//
//   queue/bin/ci-main.mjs refresh [--force]   ask GitHub (at most every 3 min)
//   queue/bin/ci-main.mjs brief               refresh, then the runner paragraph
//   queue/bin/ci-main.mjs line                refresh, then one line (empty if green)
//   queue/bin/ci-main.mjs show                what is on disk, as JSON
//
// A CANCELLED run says nothing: main's CI cancels a run when a newer push
// arrives, so most runs end that way (107 of 200 that week). The answer is the
// newest run that finished on its own. Reading it needs `gh` signed in; when it
// is not, or GitHub cannot be reached, the last reading is kept and marked, and
// nothing is said to be red that was not seen red.
//
// Drill: queue/bin/ci-main-drill.mjs
import { readFileSync, writeFileSync, existsSync, renameSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const CI_FILE = join(process.env.PHOTONZ_QUEUE_DIR || join(REPO, 'queue'), 'ci-main.json');
const REFRESH_MS = 3 * 60 * 1000;

// Conclusions that are a verdict on the code. Everything else (cancelled,
// skipped, neutral, still running) is passed over.
const VERDICTS = new Set(['success', 'failure', 'timed_out', 'startup_failure', 'action_required']);
const RED = new Set(['failure', 'timed_out', 'startup_failure']);

// ---- pure: runs and jobs in, a state out -----------------------------------
// runs: `gh run list --json databaseId,conclusion,status,headSha,createdAt,
//        updatedAt,displayTitle,url`, newest first.
// jobs: `gh run view <id> --json jobs` .jobs of the run that decided it.
export function readRuns(runs = [], jobs = [], at = Date.now()) {
  const finished = runs.filter((r) => r.status === 'completed' && VERDICTS.has(r.conclusion));
  const last = finished[0] || null;
  if (!last) return { checkedAt: new Date(at).toISOString(), red: false, run: null, failing: [], lastGreen: null, redSince: null, redRuns: 0 };
  const red = RED.has(last.conclusion);
  const greenIdx = finished.findIndex((r) => r.conclusion === 'success');
  const lastGreen = greenIdx < 0 ? null : { at: finished[greenIdx].updatedAt || finished[greenIdx].createdAt, url: finished[greenIdx].url, sha: (finished[greenIdx].headSha || '').slice(0, 9) };
  // Every finished red run since the last green one, oldest last.
  const redStreak = red ? (greenIdx < 0 ? finished : finished.slice(0, greenIdx)).filter((r) => RED.has(r.conclusion)) : [];
  const failing = red ? (jobs || [])
    .filter((j) => RED.has(j.conclusion))
    .map((j) => ({ job: j.name, steps: (j.steps || []).filter((s) => RED.has(s.conclusion)).map((s) => s.name) })) : [];
  return {
    checkedAt: new Date(at).toISOString(),
    red,
    run: { id: last.databaseId, url: last.url, sha: (last.headSha || '').slice(0, 9), title: last.displayTitle || '', conclusion: last.conclusion, at: last.updatedAt || last.createdAt },
    failing,
    lastGreen,
    // Only as far back as the list reaches: when no green run is in it, this
    // is the oldest red one seen and the words say "at least".
    redSince: red ? (redStreak[redStreak.length - 1].createdAt || null) : null,
    redSinceIsFloor: red && greenIdx < 0,
    redRuns: redStreak.length,
  };
}

// "Build app bundle (arm64) at The sweep's size is the size it really is"
export function failingWhere(state) {
  if (!state || !state.red) return '';
  const parts = (state.failing || []).map((f) => (f.steps.length ? `${f.job}, at the step "${f.steps.join('", "')}"` : f.job));
  return parts.length ? parts.join('; ') : `the run ended "${state.run.conclusion}"`;
}

const days = (iso, at) => {
  const h = (at - Date.parse(iso)) / 3600000;
  if (h < 1) return 'under an hour';
  if (h < 36) { const n = Math.round(h); return `${n} hour${n === 1 ? '' : 's'}`; }
  const n = Math.round(h / 24); return `${n} day${n === 1 ? '' : 's'}`;
};

// One line, for the loop log, the banner and the dashboard's tooltip. Empty
// when main is green or nothing is known.
export function ciLine(state, at = Date.now()) {
  if (!state || !state.red) return '';
  let s = `main's checks are failing: ${failingWhere(state)}`;
  if (state.redSince) s += `; red for ${state.redSinceIsFloor ? 'at least ' : ''}${days(state.redSince, at)} (${state.redRuns} failed run${state.redRuns === 1 ? '' : 's'})`;
  return s;
}

// The paragraph a runner reads before its task. Not an order to drop the task:
// most runners' work has nothing to do with the failing step. It is so nobody
// pushes on top of a red main without knowing, and so whoever's change broke it
// can see that it did.
export function ciBrief(state, at = Date.now()) {
  if (!state || !state.red) return '';
  const r = state.run;
  return [
    '## Main is red right now',
    '',
    `The last finished check run on main FAILED: ${failingWhere(state)}.`,
    `Run: ${r.url} (commit ${r.sha}, "${r.title}", ${days(r.at, at)} ago).` +
      (state.redSince ? ` Main has been red for ${state.redSinceIsFloor ? 'at least ' : ''}${days(state.redSince, at)}, ${state.redRuns} failed run${state.redRuns === 1 ? '' : 's'}` +
        (state.lastGreen ? `; last green ${days(state.lastGreen.at, at)} ago.` : '.') : ''),
    `See why with: gh run view ${r.id} --log-failed | tail -60`,
    '',
    'Before you push, look. If the failure is in something your task touches, making it pass is part of your task. ' +
      'If it is not, find the open task that owns it (node queue/bin/queue.mjs search "<the step name>") and fold what you see into it; ' +
      'if none does, file one at p1 with that command\'s output in its notes. Never call your own work verified by CI while main is red.',
    '',
  ].join('\n');
}

// ---- the file ---------------------------------------------------------------
export function readCiMain(file = CI_FILE) {
  if (!existsSync(file)) return null;
  try { return JSON.parse(readFileSync(file, 'utf8')); } catch { return null; }
}

function writeCiMain(state, file = CI_FILE) {
  const tmp = `${file}.tmp`;
  writeFileSync(tmp, JSON.stringify(state, null, 2) + '\n');
  renameSync(tmp, file);
}

// One retry: GitHub answers the run list with a 502 now and then (seen
// 2026-11-10), and a second ask a moment later is usually fine.
const gh = (args) => {
  const once = () => execFileSync('gh', args, { cwd: REPO, encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'] });
  try { return once(); } catch { return once(); }
};

export function refresh({ force = false, at = Date.now(), file = CI_FILE, run = gh } = {}) {
  const prev = readCiMain(file);
  if (!force && prev && prev.checkedAt && at - Date.parse(prev.checkedAt) < REFRESH_MS && !prev.error) return prev;
  try {
    const runs = JSON.parse(run(['run', 'list', '--branch', 'main', '--workflow', 'CI', '--limit', '100',
      '--json', 'databaseId,conclusion,status,headSha,createdAt,updatedAt,displayTitle,url']));
    const finished = runs.find((r) => r.status === 'completed' && VERDICTS.has(r.conclusion));
    let jobs = [];
    if (finished && RED.has(finished.conclusion)) {
      // The same run as last time needs no second look at its jobs.
      if (prev && prev.run && prev.run.id === finished.databaseId && prev.failing && prev.failing.length) {
        jobs = prev.failing.map((f) => ({ name: f.job, conclusion: 'failure', steps: f.steps.map((name) => ({ name, conclusion: 'failure' })) }));
      } else {
        jobs = JSON.parse(run(['run', 'view', String(finished.databaseId), '--json', 'jobs'])).jobs || [];
      }
    }
    const state = readRuns(runs, jobs, at);
    writeCiMain(state, file);
    return state;
  } catch (e) {
    const msg = String((e.stderr && e.stderr.toString()) || e.message || e).trim().split('\n')[0];
    const kept = { ...(prev || { red: false, run: null, failing: [] }), error: msg, errorAt: new Date(at).toISOString() };
    try { writeCiMain(kept, file); } catch { /* the reading is a report, never a reason to stop the loop */ }
    return kept;
  }
}

// ---- cli ----------------------------------------------------------------------
if (process.argv[1] && process.argv[1].endsWith('ci-main.mjs')) {
  const [cmd = 'line', ...rest] = process.argv.slice(2);
  const force = rest.includes('--force');
  if (cmd === 'show') {
    console.log(JSON.stringify(readCiMain(), null, 2));
  } else if (cmd === 'refresh') {
    const s = refresh({ force });
    console.log(s.error ? `!! could not read main's checks: ${s.error}` : (ciLine(s) || `main's checks pass (${s.run ? s.run.url : 'no finished run'})`));
  } else if (cmd === 'brief') {
    process.stdout.write(ciBrief(refresh({ force })));
  } else if (cmd === 'line') {
    const l = ciLine(refresh({ force }));
    if (l) console.log(l);
  } else {
    console.error('usage: ci-main.mjs refresh [--force] | brief | line | show');
    process.exit(2);
  }
}
