#!/usr/bin/env node
// When the walk sweep is allowed to run, and what gets checked in between.
//
// THE PROBLEM THIS SOLVES. Until 2026-09-21 the only question the gate asked
// was "has a runner asked for a sweep?", and a runner asks after every task.
// So the whole set ran after every task: thirteen whole-set runs in twenty
// four hours, 835 minutes of a 1440 minute day, 58 per cent of the loop's wall
// clock spent re-running walks and 41 per cent building anything
// (queue/bin/loop-day.mjs --hours 24, measured that morning). The user asked
// twice why video was not moving; this was most of the answer.
//
// THE SCHEDULE. Written here once, and every place that tells a human about it
// reads it from queue/bin/sweep.sh schedule rather than typing it out again.
//
//   The full set runs at most once every FLOOR HOURS (12), so twice a day, and
//   only when code has landed since the last one. Requests pile up in between
//   and are all served by the next run.
//
//   Between those, after any task that landed code, the loop runs a ROTATING
//   CHECK: about ten minutes of walks, made of every walk whose script changed
//   since the last check plus the next chunk of the set in rotation. The cursor
//   carries on where it stopped, so the whole set is covered by rotation about
//   once a day anyway, spread out in ten minute pieces instead of two hour ones.
//
//   A runner that has changed something every walk touches can still have one
//   now: queue/bin/sweep.sh request --now "<why>" jumps the floor.
//
// WHY A ROTATING CHECK AND NOT NOTHING. A floor on its own trades safety for
// speed: twelve hours and ten tasks could land between one whole-set answer and
// the next. The rotation keeps a real regression signal running the whole time
// at a twelfth of the price, and it is honest about what it is: it never closes
// the standing walk task and never reads as a sweep, because fifty walks
// passing is not the state of five hundred.
//
// Drill: queue/bin/sweep-schedule-drill.mjs
export const DEFAULTS = {
  // Hours between whole-set runs. Twelve, so twice a day: a full sweep is 113
  // minutes at 544 walks, which is 16 per cent of a day at this floor.
  floorHours: 12,
  // How long a rotating check is allowed to take, in walks-worth of time. Ten
  // minutes is about fifty walks, which is a twelfth of the set and short
  // enough that it never reads as the loop stalling.
  sliceMinutes: 10,
  // Only a default; sweep-size.mjs measures the real one off the history.
  perWalkSeconds: 12,
};

const HOUR = 3600 * 1000;

// What the loop should do between two tasks: run the whole set, run a rotating
// check, or nothing at all. Pure, so the drill can move the clock.
export function decide({
  now = Date.now(),
  requests = [],
  latest = null,          // queue/sweep/latest.json, the last whole-set run
  rotation = null,        // queue/sweep/rotation.json, where the rotation is up to
  head = null,            // the commit the loop is on right now
  screenLocked = false,
  floorHours = DEFAULTS.floorHours,
} = {}) {
  const pending = Array.isArray(requests) ? requests : [];
  const nothing = (why) => ({ run: 'nothing', why, hoursSince: null, nextFullInHours: null });

  if (!pending.length) return nothing('no sweep has been asked for');

  const began = latest && latest.began ? Date.parse(latest.began) : NaN;
  const hoursSince = Number.isFinite(began) ? (now - began) / HOUR : null;
  const out = (run, why) => ({
    run, why, hoursSince,
    nextFullInHours: hoursSince === null ? 0 : Math.max(0, floorHours - hoursSince),
  });

  // Nothing has ever been recorded, so there is no floor to stand on and no
  // rotation worth starting: the first thing the loop owes anybody is one
  // whole-set answer.
  if (hoursSince === null) return out('full', 'no whole-set run has ever been recorded');

  // A runner that changed something every walk touches can say so.
  if (pending.some((r) => r && r.now)) {
    const who = pending.find((r) => r && r.now);
    return out('full', `asked for straight away by ${who.by || 'a task runner'}`);
  }

  const sameCode = !!(head && latest.head && latest.head === head);

  if (hoursSince >= floorHours) {
    // The last whole-set run already answered for this exact commit. Running it
    // again would cost two hours to print the same list.
    if (sameCode && latest.complete !== false) {
      return out('nothing', 'the last full sweep already covered this commit');
    }
    // A locked screen can only ever run the part of the set that never asks for
    // a control by name. Repeating that part against code it has already
    // covered tells nobody anything (Sources/PhotonzCore/PlaytestLockSafety.swift).
    if (screenLocked && sameCode) {
      return out('nothing', 'the lock-safe part has already run against this commit');
    }
    return out('full', `${hoursSince.toFixed(1)}h since the last whole-set run`);
  }

  // Inside the floor: the rotating check, once per commit. A whole-set run
  // counts as having checked its commit too, so a full sweep is never followed
  // straight away by a rotating check over the same code.
  const lastChecked = rotation && rotation.lastHead ? rotation.lastHead : null;
  if (head && (lastChecked === head || latest.head === head)) {
    return out('nothing', 'nothing new has landed since the last walk check');
  }
  return out('slice', `${hoursSince.toFixed(1)}h since the last whole-set run, so the rotating check runs instead`);
}

// Which walks a rotating check covers: everything whose script changed, then
// the next chunk of the set in rotation, up to the time budget.
export function pickSlice({
  walks = [],
  cursor = 0,
  changed = [],
  minutes = DEFAULTS.sliceMinutes,
  perWalkSeconds = DEFAULTS.perWalkSeconds,
} = {}) {
  const set = walks.slice();
  if (!set.length) return { walks: [], nextCursor: 0, changed: [], rotated: [], lap: false, budget: 0 };

  const per = Number(perWalkSeconds) > 0 ? Number(perWalkSeconds) : DEFAULTS.perWalkSeconds;
  const budget = Math.max(1, Math.floor((Number(minutes) * 60) / per));
  const inSet = new Set(set);

  // A walk whose own script changed is the one most likely to be broken and the
  // cheapest thing to be sure about, so it goes first however far away the
  // cursor is.
  const picked = [];
  const seen = new Set();
  const changedPicked = [];
  for (const name of changed) {
    if (!inSet.has(name) || seen.has(name)) continue;
    seen.add(name); picked.push(name); changedPicked.push(name);
    if (picked.length >= budget) break;
  }

  const rotated = [];
  let i = cursor % set.length;
  if (i < 0) i += set.length;
  let stepped = 0;
  let lap = false;
  while (picked.length < budget && stepped < set.length) {
    const name = set[i];
    if (!seen.has(name)) { seen.add(name); picked.push(name); rotated.push(name); }
    i = (i + 1) % set.length;
    stepped++;
    if (i === 0) lap = true;
  }

  return { walks: picked, nextCursor: i, changed: changedPicked, rotated, lap, budget };
}

// ---------------------------------------------------------------- the CLI ----
// Reading the state off disk lives here rather than in sweep.sh, so the shell
// asks one question and gets one answer.
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

export const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const readJSON = (f) => { try { return JSON.parse(readFileSync(f, 'utf8')); } catch { return null; } };

export function sweepDir(repo = REPO) {
  return join(process.env.PHOTONZ_QUEUE_DIR || join(repo, 'queue'), 'sweep');
}

// The same glob Scripts/playtest-all.sh iterates, sorted, so the rotation's
// cursor means the same thing from one run to the next.
export function walkNames(repo = REPO) {
  const dir = join(repo, 'Scripts', 'playtest');
  if (!existsSync(dir)) return [];
  return readdirSync(dir).filter((f) => f.endsWith('.json')).map((f) => basename(f, '.json')).sort();
}

function git(args, repo = REPO) {
  try { return execFileSync('git', args, { cwd: repo, encoding: 'utf8' }).trim(); } catch { return ''; }
}

// Walk scripts that changed since `base`. A walk rewritten an hour ago is the
// likeliest thing in the set to be wrong and the cheapest thing to be sure
// about, so it never waits for the rotation to come round to it.
export function changedWalks(base, repo = REPO) {
  if (!base) return [];
  const out = git(['diff', '--name-only', base, 'HEAD', '--', 'Scripts/playtest'], repo);
  if (!out) return [];
  return out.split('\n')
    .filter((f) => /^Scripts\/playtest\/[^/]+\.json$/.test(f))
    .map((f) => basename(f, '.json'));
}

const isMain = process.argv[1] && process.argv[1].endsWith('sweep-schedule.mjs');
if (isMain) {
  const argv = process.argv.slice(2);
  const arg = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d; };
  const dir = sweepDir();
  const head = arg('--head', git(['rev-parse', 'HEAD'])) || null;
  const floorHours = Number(process.env.PHOTONZ_SWEEP_FLOOR_HOURS || DEFAULTS.floorHours);

  if (argv.includes('--decide')) {
    const requested = readJSON(join(dir, 'requested.json'));
    const d = decide({
      requests: (requested && requested.requests) || [],
      latest: readJSON(join(dir, 'latest.json')),
      rotation: readJSON(join(dir, 'rotation.json')),
      head,
      screenLocked: argv.includes('--locked'),
      floorHours,
    });
    console.log(JSON.stringify(d));
    process.exit(0);
  }

  if (argv.includes('--pick')) {
    const rotation = readJSON(join(dir, 'rotation.json')) || { cursor: 0, lastHead: null, laps: 0 };
    const latest = readJSON(join(dir, 'latest.json'));
    const base = rotation.lastHead || (latest && latest.head) || null;
    const walks = walkNames();
    const s = pickSlice({
      walks,
      cursor: Number(rotation.cursor) || 0,
      changed: changedWalks(base),
      minutes: Number(arg('--minutes', process.env.PHOTONZ_SLICE_MINUTES || DEFAULTS.sliceMinutes)),
      perWalkSeconds: Number(arg('--per-walk', DEFAULTS.perWalkSeconds)),
    });
    if (argv.includes('--json')) console.log(JSON.stringify({ ...s, of: walks.length, from: Number(rotation.cursor) || 0, laps: Number(rotation.laps) || 0, head }));
    else for (const w of s.walks) console.log(w);
    process.exit(0);
  }

  // Move the rotation on, from the pick that was actually run rather than from
  // a second guess at it. Picking twice would be one env var away from
  // advancing the cursor past walks nobody ran.
  if (argv.includes('--advance')) {
    const pick = readJSON(arg('--advance'));
    if (!pick) { console.error('!! nothing to advance from'); process.exit(1); }
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'rotation.json'), JSON.stringify({
      cursor: pick.nextCursor || 0,
      lastHead: pick.head || head,
      laps: (Number(pick.laps) || 0) + (pick.lap ? 1 : 0),
      ran: (pick.walks || []).length,
      changed: pick.changed || [],
      of: pick.of || 0,
      at: new Date().toISOString(),
    }, null, 2) + '\n');
    process.exit(0);
  }

  // Printed by `queue/bin/sweep.sh schedule`, so there is one copy of these
  // sentences and it is the one the code runs off.
  const f = DEFAULTS.floorHours;
  console.log(`The walk sweep's schedule

  The full set runs at most once every ${f} hours, so twice a day, and only when
  code has landed since the last one. Asking for a sweep does not start one: the
  requests pile up and the next run serves them all.

  In between, after any task that lands code, the loop runs a rotating check of
  about ${DEFAULTS.sliceMinutes} minutes: every walk whose script changed since the last check,
  then the next chunk of the set in rotation, carrying on where it stopped. Over
  a day the rotation covers the whole set anyway, in pieces.

  A rotating check is not a sweep. It never closes the standing walk task and
  its green is never the state of the walk set.

  A runner that changed something every walk touches can jump the floor:
      queue/bin/sweep.sh request --now "<why the whole set, right now>"

  Where the loop's day actually goes:  queue/bin/loop-day.mjs`);
}
