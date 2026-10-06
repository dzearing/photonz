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
//   The full set runs at most once every FLOOR HOURS (24), so once a day, and
//   only when code has landed since the last one. Requests pile up in between
//   and are all served by the next run.
//
//   Between those, after any task that landed code, the loop runs a ROTATING
//   CHECK: about ten minutes of walks, made of every walk whose script changed
//   since the last check plus the next chunk of the set in rotation. The cursor
//   carries on where it stopped, so the whole set is covered by rotation about
//   once a day anyway, spread out in ten minute pieces instead of two hour ones.
//
//   Landed code IS the ask. Neither check waits for a request: "code" is
//   anything under WALK_PATHS (the app, the walk scripts, the package), so a
//   commit of the queue's own files, docs or unit tests starts nothing. Until
//   2026-10-02 the gate returned nothing whenever no request was pending, and
//   runners are told to ask only for the whole set, so after the full run of
//   2026-10-01 nobody asked and seven app commits landed with no walk check.
//
//   A runner that has changed something every walk touches can still have one
//   now: queue/bin/sweep.sh request --now "<why>" jumps the floor.
//
// WHY A ROTATING CHECK AND NOT NOTHING. A floor on its own trades safety for
// speed: twelve hours and ten tasks could land between one whole-set answer and
// the next. The rotation keeps a real regression signal running the whole time
// at a small part of the price, and it is honest about what it is: it never closes
// the standing walk task and never reads as a sweep, because thirty walks
// passing is not the state of seven hundred.
//
// Drill: queue/bin/sweep-schedule-drill.mjs
export const DEFAULTS = {
  // Hours between whole-set runs. 24, once a day (was twelve until 2026-09-26, when walks made the user's Mac unusable): a full sweep is 113
  // minutes at 544 walks, which is 16 per cent of a day at this floor.
  floorHours: 24,
  // How long a rotating check is allowed to take, in walks-worth of time. Ten
  // minutes is short enough that it never reads as the loop stalling; at the
  // measured cost of a walk (about 18s on 2026-10-06) it is about thirty five
  // walks, so the rotation still comes round the set in about a day of checks.
  sliceMinutes: 10,
  // Only the last resort. A check is planned at what walks cost in the last
  // rotating checks (sliceWalkSecondsFromDisk), then in the last whole-set runs,
  // and only with neither on disk at this. Until 2026-10-06 this number WAS the
  // plan: twelve seconds a walk, so fifty walks a check, while walks had grown
  // to 17.6s and every ten minute check ran about fifteen.
  perWalkSeconds: 12,
  // Walks EVERY rotating check runs, ahead of the rest. Kept to the few that
  // drive a whole experience end to end the way a person gets it, because a
  // regression anywhere along that path shows up in them first:
  // an-editing-session-walk opens a talking recording at Next defaults, cuts
  // it, adds a clip, a transition and a moving title, plays it through
  // looking for a blank frame, and writes the MP4 (asked for on 2026-09-23).
  everyCheck: ['an-editing-session-walk'],
};

const HOUR = 3600 * 1000;

// What the loop should do between two tasks: run the whole set, run a rotating
// check, or nothing at all. Pure, so the drill can move the clock.
export function decide({
  now = Date.now(),
  requests = [],
  latest = null,          // queue/sweep/latest.json, the last whole-set run
  blind = null,           // queue/sweep/blind.json, the last whole-set run that went blind
  blindCodeUnchanged = false, // nothing outside queue/ has changed since blind.head
  rotation = null,        // queue/sweep/rotation.json, where the rotation is up to
  head = null,            // the commit the loop is on right now
  // Whether anything a walk runs (WALK_PATHS) changed between latest.head and
  // head, and between rotation.lastHead and head. null means not known, and
  // then only the commits themselves are compared, so a commit of nothing but
  // queue files reads as new code: the reader of the disk always knows.
  codeSinceFull = null,
  codeSinceCheck = null,
  screenLocked = false,
  floorHours = DEFAULTS.floorHours,
} = {}) {
  const pending = Array.isArray(requests) ? requests : [];

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

  // "The same code" is the same everything a walk runs, not the same commit:
  // the loop commits its own queue files all day.
  const sameCode = !!(head && latest.head && (latest.head === head || codeSinceFull === false));
  const lastChecked = rotation && rotation.lastHead ? rotation.lastHead : null;
  const checkedCode = !!(head && lastChecked && (lastChecked === head || codeSinceCheck === false));
  const asked = pending.length ? `, ${pending.length} request(s) pending` : '';

  // A whole-set run that went blind is kept out of latest.json (it is not the
  // state of the set), so on its own the floor still reads as a day gone and
  // the gate starts the whole set again, on the same code, to go blind at the
  // same walk. On 2026-09-28 that cost two fifty minute runs back to back
  // (the probe would not relaunch after the 1080p export walk). So a blind run
  // newer than the last real one stands in for it on its own commit: the
  // rotating check runs once instead, and the whole set waits for new code or
  // for somebody to ask for it straight away.
  const blindBegan = blind && blind.began ? Date.parse(blind.began) : NaN;
  // The loop commits its own queue files (the digest, task logs) all day, and
  // those move HEAD without touching anything a walk runs, so they do not make
  // it new code.
  const blindHere = !!(head && blind && (blind.head === head || blindCodeUnchanged)
    && Number.isFinite(blindBegan) && blindBegan > began);

  if (hoursSince >= floorHours && blindHere) {
    if (lastChecked === head) {
      return out('nothing', 'the whole set went blind on this commit and its rotating check has run; the next whole-set run waits for new code');
    }
    return out('slice', 'the whole set went blind on this commit, so the rotating check runs instead of a second whole-set run');
  }

  if (hoursSince >= floorHours) {
    // The last whole-set run already answered for this exact commit. Running it
    // again would cost two hours to print the same list.
    if (sameCode && latest.complete !== false) {
      return out('nothing', latest.head === head
        ? 'the last full sweep already covered this commit'
        : 'the last full sweep already covered this code; only the queue, docs or tests have changed since');
    }
    // A locked screen can only ever run the part of the set that never asks for
    // a control by name. Repeating that part against code it has already
    // covered tells nobody anything (Sources/PhotonzCore/PlaytestLockSafety.swift).
    if (screenLocked && sameCode) {
      return out('nothing', 'the lock-safe part has already run against this commit');
    }
    if (sameCode) {
      return out('full', `${hoursSince.toFixed(1)}h since the last whole-set run, which did not cover the set${asked}`);
    }
    return out('full', `code has landed and it is ${hoursSince.toFixed(1)}h since the last whole-set run${asked}`);
  }

  // Inside the floor: the rotating check, once per change of code. A whole-set
  // run counts as having checked its code too, so a full sweep is never
  // followed straight away by a rotating check over the same code.
  if (head && (checkedCode || sameCode)) {
    return out('nothing', 'nothing new has landed since the last walk check');
  }
  return out('slice', `code has landed since the last walk check and it is ${hoursSince.toFixed(1)}h since the last whole-set run, so the rotating check runs${asked}`);
}

// Which walks a rotating check covers: the walks named for every check, then
// everything whose script changed, then the next chunk of the set in rotation,
// up to the time budget.
export function pickSlice({
  walks = [],
  cursor = 0,
  changed = [],
  always = DEFAULTS.everyCheck,
  minutes = DEFAULTS.sliceMinutes,
  perWalkSeconds = DEFAULTS.perWalkSeconds,
} = {}) {
  const set = walks.slice();
  if (!set.length) return { walks: [], nextCursor: 0, changed: [], always: [], rotated: [], lap: false, budget: 0 };

  const per = Number(perWalkSeconds) > 0 ? Number(perWalkSeconds) : DEFAULTS.perWalkSeconds;
  const budget = Math.max(1, Math.floor((Number(minutes) * 60) / per));
  const inSet = new Set(set);

  // A walk whose own script changed is the one most likely to be broken and the
  // cheapest thing to be sure about, so it goes first however far away the
  // cursor is.
  const picked = [];
  const seen = new Set();
  const alwaysPicked = [];
  for (const name of always || []) {
    if (!inSet.has(name) || seen.has(name) || picked.length >= budget) continue;
    seen.add(name); picked.push(name); alwaysPicked.push(name);
  }
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

  return { walks: picked, nextCursor: i, changed: changedPicked, always: alwaysPicked, rotated, lap, budget };
}

// What a walk costs inside a rotating check, measured off the checks that ran.
// `events` is queue/history.jsonl, parsed. A check's seconds run from before
// the probe is built to after the last walk, so the build and the launch are in
// the number, spread over the walks, which is what the plan needs. The median of
// the last `last` checks, not the mean: one check that ran while the machine
// was busy (22.3s a walk on 2026-10-05) must not move the next one.
// Thrown out: a check stopped on the clock (its seconds are the cap, not its
// walks), one a locked screen cut down (a refused walk costs under a second,
// and planning on that would make the next unlocked check twice too long), and
// one of a handful of walks or an implausible pace (it did not really run).
const SLICE_PLAUSIBLE = { minWalks: 10, min: 3, max: 60 };
export function sliceWalkSeconds(events = [], { last = 10 } = {}) {
  const paces = [];
  for (const o of events) {
    if (!o || o.ev !== 'slice_pass' || o.timedOut) continue;
    if ((Number(o.couldNotRun) || 0) > 0) continue;
    const walks = Number(o.walks) || 0;
    const seconds = Number(o.seconds) || 0;
    if (walks < SLICE_PLAUSIBLE.minWalks || seconds <= 0) continue;
    const per = seconds / walks;
    if (per < SLICE_PLAUSIBLE.min || per > SLICE_PLAUSIBLE.max) continue;
    paces.push(per);
  }
  const recent = paces.slice(-last);
  if (!recent.length) return { seconds: DEFAULTS.perWalkSeconds, checks: 0, measured: false };
  const sorted = [...recent].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  const median = sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  return { seconds: median, checks: recent.length, measured: true };
}

// The same, read off the disk, with somewhere to fall back to: the whole-set
// runs (sweep-size.mjs) when no rotating check has been recorded yet, and the
// default only when there is no history at all.
export function sliceWalkSecondsFromDisk(repo = REPO) {
  const file = join(repo, 'queue', 'history.jsonl');
  const events = [];
  if (existsSync(file)) {
    for (const line of readFileSync(file, 'utf8').split('\n')) {
      if (!line.includes('"slice_pass"')) continue;
      try { events.push(JSON.parse(line)); } catch { /* a torn line */ }
    }
  }
  const m = sliceWalkSeconds(events);
  if (m.measured) return { ...m, from: `the median of the last ${m.checks} rotating checks` };
  const full = sweepPerWalkSeconds(repo);
  if (full.measured) return { seconds: full.seconds, checks: 0, measured: true, from: `the median of the last ${full.runs} whole-set sweeps` };
  return { seconds: DEFAULTS.perWalkSeconds, checks: 0, measured: false, from: 'the default, with nothing recorded to measure' };
}

// ---------------------------------------------------------------- the CLI ----
// Reading the state off disk lives here rather than in sweep.sh, so the shell
// asks one question and gets one answer.
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { perWalkSeconds as sweepPerWalkSeconds } from './sweep-size.mjs';

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

// What a walk actually runs: the app, the scripts that build and drive it (the
// walks themselves are Scripts/playtest), and what the package pulls in. Not the
// queue's own files, the docs, the site or the unit tests, which the loop and
// its runners commit all day without changing anything a walk could see.
export const WALK_PATHS = ['Sources', 'Scripts', 'Resources', 'Vendor', 'Package.swift', 'Package.resolved'];

// Whether anything under WALK_PATHS changed between two commits. null when
// either is missing; a commit git cannot read counts as changed.
export function codeLandedBetween(a, b, repo = REPO) {
  if (!a || !b) return null;
  if (a === b) return false;
  try {
    execFileSync('git', ['diff', '--quiet', a, b, '--', ...WALK_PATHS], { cwd: repo, stdio: 'ignore' });
    return false;
  } catch { return true; }
}

// The decision, read off the disk: the files under `dir` and the commits in
// `repo`. The CLI is this and a print; the drill calls it on a scratch repo.
export function decideFromDisk({
  repo = REPO, dir = sweepDir(repo), now = Date.now(), head = null,
  screenLocked = false, floorHours = DEFAULTS.floorHours,
} = {}) {
  const at = head || git(['rev-parse', 'HEAD'], repo) || null;
  const requested = readJSON(join(dir, 'requested.json'));
  const latest = readJSON(join(dir, 'latest.json'));
  const blind = readJSON(join(dir, 'blind.json'));
  const rotation = readJSON(join(dir, 'rotation.json'));
  return decide({
    now,
    requests: (requested && requested.requests) || [],
    latest,
    blind,
    blindCodeUnchanged: !!(blind && blind.head && at && blind.head !== at
      && codeLandedBetween(blind.head, at, repo) === false),
    rotation,
    head: at,
    codeSinceFull: latest ? codeLandedBetween(latest.head, at, repo) : null,
    codeSinceCheck: rotation ? codeLandedBetween(rotation.lastHead, at, repo) : null,
    screenLocked,
    floorHours,
  });
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
    const d = decideFromDisk({ dir, head, screenLocked: argv.includes('--locked'), floorHours });
    console.log(JSON.stringify(d));
    process.exit(0);
  }

  if (argv.includes('--pick')) {
    const rotation = readJSON(join(dir, 'rotation.json')) || { cursor: 0, lastHead: null, laps: 0 };
    const latest = readJSON(join(dir, 'latest.json'));
    const base = rotation.lastHead || (latest && latest.head) || null;
    const walks = walkNames();
    // Planned at what walks have really cost lately; --per-walk overrides it.
    const forced = Number(arg('--per-walk', NaN));
    const pace = forced > 0
      ? { seconds: forced, from: 'given with --per-walk' }
      : sliceWalkSecondsFromDisk();
    const s = pickSlice({
      walks,
      cursor: Number(rotation.cursor) || 0,
      changed: changedWalks(base),
      minutes: Number(arg('--minutes', process.env.PHOTONZ_SLICE_MINUTES || DEFAULTS.sliceMinutes)),
      perWalkSeconds: pace.seconds,
    });
    if (argv.includes('--json')) console.log(JSON.stringify({ ...s, of: walks.length, from: Number(rotation.cursor) || 0, laps: Number(rotation.laps) || 0, head, perWalkSeconds: +pace.seconds.toFixed(1), perWalkFrom: pace.from }));
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
  const pace = sliceWalkSecondsFromDisk();
  console.log(`The walk sweep's schedule

  The full set runs at most once every ${f} hours, so once a day, and only when
  code has landed since the last one. Asking for a sweep does not start one: the
  requests pile up and the next run serves them all.

  Landed code is the ask: neither check waits for a request. Code is anything
  under ${WALK_PATHS.join(', ')}; a commit of only the queue's
  own files, docs or unit tests starts nothing.

  In between, after any task that lands code, the loop runs a rotating check of
  about ${DEFAULTS.sliceMinutes} minutes: the walks every check runs (${DEFAULTS.everyCheck.join(', ')}),
  every walk whose script changed since the last check, then the next chunk of
  the set in rotation, carrying on where it stopped. Over a day the rotation
  covers the whole set anyway, in pieces.

  How many walks fit in those minutes is measured, not guessed: right now
  ${pace.seconds.toFixed(1)}s a walk, ${pace.from}, so about
  ${Math.max(1, Math.floor(DEFAULTS.sliceMinutes * 60 / pace.seconds))} walks a check.

  A rotating check is not a sweep. It never closes the standing walk task and
  its green is never the state of the walk set. A walk it finds broken goes
  onto the open task that owns it, or else onto the standing walk task, which
  it opens if none is open: one new task per check at most.

  A runner that changed something every walk touches can jump the floor:
      queue/bin/sweep.sh request --now "<why the whole set, right now>"

  Where the loop's day actually goes:  queue/bin/loop-day.mjs`);
}
