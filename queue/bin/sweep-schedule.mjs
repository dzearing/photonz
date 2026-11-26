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
//   The full set runs at most once every FLOOR HOURS (72), so every three days, and
//   only when code has landed since the last one. Requests pile up in between
//   and are all served by the next run.
//
//   Between those, after a task that landed code and at most once every
//   SLICE FLOOR HOURS (4), the loop runs a ROTATING CHECK: about ten minutes of
//   walks, made of every walk whose script changed since the last check plus
//   the next chunk of the set in rotation. The cursor carries on where it
//   stopped, so the rotation works through the set in ten minute pieces: at
//   six checks a day a lap takes days, not one (lapEstimate prints the number
//   from the walks' own times). A check stopped on the clock moves on past the
//   walks it finished and owes the rest to the next one (settleSlice).
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
  // Hours between whole-set runs. 72, every three days, since 2026-11-05 (the
  // user: 96 tasks waiting and about five done a day; a whole set had reached
  // five to six hours, 22 per cent of the loop's week at a daily floor). It
  // was 24 from 2026-09-26 (walks made the user's Mac unusable) and twelve
  // before that. Until 2026-11-10 only the loop's environment said 72
  // (go-loop.sh PHOTONZ_SWEEP_FLOOR_HOURS), so the dashboard and
  // `sweep.sh schedule` went on saying once a day.
  floorHours: 72,
  // Hours between two rotating checks. Until 2026-11-05 a check ran after EVERY
  // task that landed code, and a "ten minute" check was taking about thirty
  // (14 walks in 30 minutes that evening), so the user kept finding the loop
  // between tasks and asked for it less often: at most one every four hours.
  // The whole set, every three days, catches the rest.
  sliceFloorHours: 4,
  // How long a rotating check is planned to take. Ten minutes is short enough
  // that it never reads as the loop stalling. It is filled walk by walk at each
  // walk's own recent time (pickSlice): about thirty walks of the usual kind,
  // or two or three of the slow Ask ones.
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
  // 3d-grippers-on-a-picked-layer-walk picks a layer and checks its 3D arcs
  // and depth arrow are drawn with no hover, then swings it: the user found
  // them gone on 2026-10-13 and asked that they never silently go again.
  // closed-windows-give-their-memory-back-walk opens and closes pictures and
  // fails if Photonz keeps what it closed: a colleague saw it near 4 GB and
  // every closed window was found still in memory (2026-10-23).
  // a-press-fires-a-plain-button-walk presses a picture tile, a swatch and
  // the colour well the way every walk presses a control: from macOS 27 those
  // presses landed and did nothing for six days (2026-10-26 to 11-01) and
  // dozens of walks went red with no app change behind them.
  // hear-the-scrub-walk plays and scrubs two sounds at once and fails if any
  // of it reaches the room (the probe audible, or holding an audio-out
  // assertion): on 2026-11-26 the person at the Mac heard a walk's music out
  // of the speakers. It needs no front, so it runs with somebody at the Mac,
  // when an-editing-session-walk (which holds the front) is skipped.
  everyCheck: ['a-press-fires-a-plain-button-walk', 'an-editing-session-walk',
    '3d-grippers-on-a-picked-layer-walk', 'closed-windows-give-their-memory-back-walk',
    'hear-the-scrub-walk'],
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
  // When the last rotating check finished (queue/sweep/last-slice.json), and
  // the least time between two of them.
  lastSliceEnded = null,
  sliceFloorHours = DEFAULTS.sliceFloorHours,
  // The walk names as they are now. Only needed to carry on from a stopped
  // whole-set run (queue/bin/sweep-resume.mjs); without it nothing resumes.
  set = null,
  // The walks whose own script changed since the stopped run's oldest part:
  // their answers are about a walk that is gone, so they run again.
  changedSinceStopped = [],
} = {}) {
  const pending = Array.isArray(requests) ? requests : [];

  const began = latest && latest.began ? Date.parse(latest.began) : NaN;
  const hoursSince = Number.isFinite(began) ? (now - began) / HOUR : null;
  const out = (run, why, extra = {}) => ({
    run, why, hoursSince,
    nextFullInHours: hoursSince === null ? 0 : Math.max(0, floorHours - hoursSince),
    ...extra,
  });

  // Nothing has ever been recorded, so there is no floor to stand on and no
  // rotation worth starting: the first thing the loop owes anybody is one
  // whole-set answer.
  if (hoursSince === null) return out('full', 'no whole-set run has ever been recorded');

  // The last whole-set run was STOPPED part way (the person came back to the
  // Mac, the loop was put down): the next whole-set run is only what it left
  // unanswered, and it runs as soon as the Mac is free rather than three days
  // later. It is the rest of the set's run, not a second one, so the floor does
  // not hold it back and its record keeps the stopped run's start
  // (queue/bin/sweep-resume.mjs). On 2026-10-22 a run stopped at 989 of 1011
  // was due to start again from walk one; from 2026-11-05 to 11-20 six runs in
  // a row were stopped and, code having landed each time, thrown away.
  //
  // It waits for the Mac to be left alone like the whole set does (sweep.sh
  // due), and until then the loop does what it would have done with nothing
  // to carry on from: `meanwhile` is that answer, so a remainder owed all day
  // never starves the rotating check after a landed change.
  const codeSinceFullKnown = latest && latest.head && head
    ? (latest.head === head ? false : codeSinceFull) : codeSinceFull;
  const rest = Array.isArray(set)
    ? resumable({ record: latest, set, head, codeSince: codeSinceFullKnown, screenLocked, blind,
      changed: changedSinceStopped, now, windowHours: floorHours })
    : null;
  if (rest && rest.ok) {
    const meanwhile = decide({
      now, requests, latest, blind, blindCodeUnchanged, rotation, head, codeSinceFull, codeSinceCheck,
      screenLocked, floorHours, lastSliceEnded, sliceFloorHours, set: null,
    });
    return out('full', rest.why, {
      resume: true, walks: rest.walks.length, unreached: rest.unreached.length, rerun: rest.rerun.length,
      changed: rest.changed.length, stale: rest.stale.length,
      meanwhile: { run: meanwhile.run, why: meanwhile.why },
    });
  }
  // Said whenever a stopped run could NOT be carried on from, so nobody reads
  // a whole-set run of five hours as the loop forgetting what it had reached.
  const notResumed = rest && rest.because === 'stale' ? `; ${rest.why}` : '';

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
    return out('full', `code has landed and it is ${hoursSince.toFixed(1)}h since the last whole-set run${asked}${notResumed}`);
  }

  // Inside the floor: the rotating check, once per change of code. A whole-set
  // run counts as having checked its code too, so a full sweep is never
  // followed straight away by a rotating check over the same code.
  // A check that did not get through what it picked (stopped on the clock, or
  // changed walks carried over for want of room) still owes those walks, so it
  // is due again once the floor below has passed, new code or not. Its
  // rotation.json has already moved lastHead on, so without this a stopped
  // check's walks would wait for the next landed change.
  const owes = !!(rotation && ((Array.isArray(rotation.owed) && rotation.owed.length) || rotation.cutShort));
  if (head && (sameCode || (checkedCode && !owes))) {
    return out('nothing', 'nothing new has landed since the last walk check');
  }
  const sinceSlice = lastSliceEnded ? (now - Date.parse(lastSliceEnded)) / HOUR : Infinity;
  if (Number.isFinite(sinceSlice) && sinceSlice < sliceFloorHours) {
    return out('nothing', `the last rotating check was ${sinceSlice.toFixed(1)}h ago; the next waits until ${sliceFloorHours}h have passed`);
  }
  if (checkedCode && owes) {
    const n = Array.isArray(rotation.owed) ? rotation.owed.length : 0;
    return out('slice', `the last rotating check did not get through its walks${n ? ` and owes ${n} changed walk(s)` : ''}, so the next one runs${asked}${notResumed}`);
  }
  return out('slice', `code has landed since the last walk check and it is ${hoursSince.toFixed(1)}h since the last whole-set run, so the rotating check runs${asked}${notResumed}`);
}

// Which walks a rotating check covers: the walks named for every check, then
// everything whose script changed (and what an earlier check still owes), then
// the next chunk of the set in rotation, up to the time budget.
//
// The budget is TIME, not a count. Each walk is costed at its own recent time
// where one is on record (`walkSeconds`, read off the sweep's logs by
// walkSecondsFromLogs), and only a walk with no record at the measured pace of
// a whole check (`perWalkSeconds`). Until 2026-11-22 every walk was costed at
// the median pace, about 20s, so thirty walks went in whatever they were; from
// position 157 those thirty held a block of Ask walks at 100 to 390s each, and
// eight checks in a row out of nine were stopped on the thirty minute clock.
//
// Changed walks take at most `changedShare` of what is left after the walks
// every check runs (always at least one of them), and the rest are carried to
// the next check in `owed`, so a day of rewritten walks can never fill a check
// and leave the rotation standing: on 2026-11-21 twenty seven changed walks
// filled all thirty one places and the cursor did not move. The rotation, for
// its part, always takes at least one walk, so every check moves it on.
export function pickSlice({
  walks = [],
  cursor = 0,
  changed = [],
  owed = [],
  always = DEFAULTS.everyCheck,
  minutes = DEFAULTS.sliceMinutes,
  perWalkSeconds = DEFAULTS.perWalkSeconds,
  walkSeconds = null,
  changedShare = 0.5,
} = {}) {
  const set = walks.slice();
  const empty = { walks: [], nextCursor: 0, changed: [], owed: [], always: [], rotated: [], rotatedAt: [], lap: false, budget: 0, budgetSeconds: 0, estimatedSeconds: 0 };
  if (!set.length) return empty;

  const per = Number(perWalkSeconds) > 0 ? Number(perWalkSeconds) : DEFAULTS.perWalkSeconds;
  const budgetSeconds = Math.max(1, Number(minutes) * 60);
  const cost = (name) => {
    const own = walkSeconds ? Number(walkSeconds[name]) : NaN;
    return own > 0 ? own : per;
  };
  const inSet = new Set(set);

  const picked = [];
  const seen = new Set();
  let used = 0;
  const take = (name) => { seen.add(name); picked.push(name); used += cost(name); };

  // The walks every check runs go in first, inside the budget.
  const alwaysPicked = [];
  for (const name of always || []) {
    if (!inSet.has(name) || seen.has(name)) continue;
    if (alwaysPicked.length && used + cost(name) > budgetSeconds) continue;
    take(name); alwaysPicked.push(name);
  }

  // A walk whose own script changed is the one most likely to be broken and the
  // cheapest thing to be sure about, so it goes ahead of the rotation however
  // far away the cursor is, up to its share. What an earlier check owes comes
  // first, so nothing waits behind newer changes for ever.
  const changedPicked = [];
  const owedNext = [];
  const share = Math.max(0, budgetSeconds - used) * changedShare;
  let changedUsed = 0;
  const wanted = [];
  for (const name of [...(owed || []), ...(changed || [])]) {
    if (!inSet.has(name) || seen.has(name) || wanted.includes(name)) continue;
    wanted.push(name);
  }
  for (const name of wanted) {
    if (changedPicked.length && changedUsed + cost(name) > share) { owedNext.push(name); continue; }
    changedUsed += cost(name);
    take(name); changedPicked.push(name);
  }

  // Then the set in order from the cursor, stopping at the first walk that
  // does not fit: the cursor never jumps a walk it did not run.
  const rotated = [];
  const rotatedAt = [];
  let i = cursor % set.length;
  if (i < 0) i += set.length;
  let stepped = 0;
  let lap = false;
  while (stepped < set.length) {
    const name = set[i];
    if (!seen.has(name)) {
      if (rotated.length && used + cost(name) > budgetSeconds) break;
      take(name); rotated.push(name); rotatedAt.push(i);
    }
    i = (i + 1) % set.length;
    stepped++;
    if (i === 0) lap = true;
  }

  return {
    walks: picked, nextCursor: i, changed: changedPicked, owed: owedNext, always: alwaysPicked,
    rotated, rotatedAt, lap,
    // `budget` is the old count of walks the minutes held at the median pace,
    // kept for anything that still prints it.
    budget: Math.max(1, Math.floor(budgetSeconds / per)),
    budgetSeconds, estimatedSeconds: Math.round(used),
  };
}

// The walks a run's log says were answered: a line with a time and a verdict
// (ok, FAILED, CRASHED, DEFERRED, COULD NOT RUN). A walk the stop caught part
// way is a bare name with no verdict and is not answered, and neither is one
// that said COULD NOT START: there was no app to run it in.
const ANSWER_LINE = /^([a-z0-9][a-z0-9-]*) +(\d+)s {2}([A-Z][A-Z ]*[A-Z]|ok)\b/;
export function answeredInLog(text = '') {
  const done = new Set();
  for (const line of String(text).split('\n')) {
    const m = line.match(ANSWER_LINE);
    if (m && m[3] !== 'COULD NOT START') done.add(m[1]);
  }
  return done;
}

// Where the rotation goes after a check, from what it actually answered.
// `answered` null means every walk it picked was answered (the old rule, kept
// for a pick nothing logged). The cursor moves past the walks of the rotation
// it answered, in order, and stops at the first it did not: a walk cut off part
// way, and every walk after it, run again next time, and nothing is skipped.
// Until 2026-11-22 a check stopped on the clock moved the cursor nowhere at
// all, so the next one ran the same slow walks first and was stopped again: the
// cursor sat at 157 from 2026-11-20 07:55Z through eight checks.
// Changed walks it did not answer join what it already owed.
export function settleSlice(pick = {}, answered = null) {
  const did = (n) => !answered || answered.has(n);
  const rotated = Array.isArray(pick.rotated) ? pick.rotated : [];
  const at = Array.isArray(pick.rotatedAt) ? pick.rotatedAt : [];
  const from = Number(pick.from) || 0;
  let moved = 0;
  while (moved < rotated.length && did(rotated[moved])) moved++;
  let cursor;
  let lap;
  if (moved === rotated.length || at[moved] === undefined) {
    cursor = Number(pick.nextCursor) || 0;
    lap = !!pick.lap;
    if (moved < rotated.length) { cursor = from; lap = false; } // no positions on record: stay put
  } else {
    cursor = at[moved];
    lap = cursor < from;
  }
  const owed = [];
  for (const n of [...(pick.owed || []), ...(pick.changed || []).filter((w) => !did(w))]) {
    if (!owed.includes(n)) owed.push(n);
  }
  const unanswered = (pick.walks || []).filter((w) => !did(w));
  return { cursor, lap, moved, of: rotated.length, owed, unanswered, complete: unanswered.length === 0 };
}

// What each walk has really cost lately, read off the run logs the sweep keeps
// (queue/sweep/*.log: the whole-set runs and the last rotating checks). A walk
// is costed at the larger of its last two answers, because Ask walks wander
// (ask-draws-a-dog-walk took 151s on one check and 260s on another) and a
// check planned on the low one is a check stopped on the clock.
export function walkSecondsFromLogs(dir = sweepDir(), { keep = 2 } = {}) {
  if (!existsSync(dir)) return {};
  const files = readdirSync(dir).filter((f) => f.endsWith('.log'))
    .map((f) => ({ f, t: statSync(join(dir, f)).mtimeMs }))
    .sort((a, b) => a.t - b.t);
  const seen = new Map();
  for (const { f } of files) {
    let text = '';
    try { text = readFileSync(join(dir, f), 'utf8'); } catch { continue; }
    for (const line of text.split('\n')) {
      const m = line.match(ANSWER_LINE);
      // A walk that was turned away (DEFERRED, COULD NOT RUN or START) cost
      // nothing and says nothing about what running it costs.
      if (!m || !['ok', 'FAILED', 'CRASHED'].includes(m[3])) continue;
      if (!seen.has(m[1])) seen.set(m[1], []);
      seen.get(m[1]).push(Number(m[2]));
    }
  }
  const out = {};
  for (const [name, times] of seen) out[name] = Math.max(...times.slice(-keep));
  return out;
}

// How long a lap of the set takes at the rotating check's pace, read from the
// numbers: the checks a lap needs, planned walk by walk at each walk's own time
// exactly the way pickSlice plans them (the walks every check runs included,
// with nothing changed), and at most one check every sliceFloorHours.
export function lapEstimate({
  walks = [], walkSeconds = null, perWalkSeconds = DEFAULTS.perWalkSeconds,
  minutes = DEFAULTS.sliceMinutes, always = DEFAULTS.everyCheck,
  sliceFloorHours = DEFAULTS.sliceFloorHours,
} = {}) {
  if (!walks.length) return { checks: 0, perCheck: 0, days: 0, checksPerDay: 24 / sliceFloorHours };
  let cursor = 0;
  let checks = 0;
  let covered = 0;
  while (covered < walks.length && checks < walks.length) {
    const s = pickSlice({ walks, cursor, changed: [], always, minutes, perWalkSeconds, walkSeconds });
    const step = s.lap ? walks.length - cursor + s.nextCursor : s.nextCursor - cursor;
    covered += Math.max(1, step);
    cursor = s.nextCursor;
    checks++;
  }
  const checksPerDay = 24 / sliceFloorHours;
  return { checks, perCheck: Math.round(walks.length / checks), days: checks / checksPerDay, checksPerDay };
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
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync, statSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { perWalkSeconds as sweepPerWalkSeconds } from './sweep-size.mjs';
import { resumable } from './sweep-resume.mjs';

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

// The walks whose script changed since the oldest part of a stopped run: the
// commit its first part ran on, so a walk rewritten between two parts is run
// again even when the later part did not reach it.
export function changedSinceRecord(record, to = null, repo = REPO) {
  if (!record || record.complete !== false) return [];
  const parts = Array.isArray(record.parts) && record.parts.length ? record.parts : [record];
  const base = (parts.find((p) => p && p.head) || {}).head || record.head || null;
  return changedWalks(base, repo, to || 'HEAD');
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
  const lastSlice = readJSON(join(dir, 'last-slice.json'));
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
    lastSliceEnded: lastSlice && lastSlice.ended ? lastSlice.ended : null,
    sliceFloorHours: Number(process.env.PHOTONZ_SLICE_FLOOR_HOURS || DEFAULTS.sliceFloorHours),
    set: walkNames(repo),
    changedSinceStopped: changedSinceRecord(latest, at, repo),
  });
}

// Walk scripts that changed since `base`. A walk rewritten an hour ago is the
// likeliest thing in the set to be wrong and the cheapest thing to be sure
// about, so it never waits for the rotation to come round to it.
export function changedWalks(base, repo = REPO, to = 'HEAD') {
  if (!base) return [];
  const out = git(['diff', '--name-only', base, to || 'HEAD', '--', 'Scripts/playtest'], repo);
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

  // The rest of a stopped whole-set run: what to run and why, as JSON, and
  // with --out the walk names one to a line for playtest-all.sh --only. Its
  // `claim` is what sweep.sh writes into .claimed.json so the record merges.
  if (argv.includes('--resume-plan')) {
    const latest = readJSON(join(dir, 'latest.json'));
    const set = walkNames();
    const plan = resumable({
      record: latest, set, head,
      codeSince: latest ? codeLandedBetween(latest.head, head) : null,
      changed: changedSinceRecord(latest, head),
      windowHours: floorHours,
      screenLocked: argv.includes('--locked'),
      blind: readJSON(join(dir, 'blind.json')),
    });
    const outFile = arg('--out', null);
    if (plan.ok && outFile) writeFileSync(outFile, plan.walks.join('\n') + '\n');
    const claimFile = arg('--claim', null);
    if (plan.ok && claimFile) writeFileSync(claimFile, JSON.stringify({ resumeOf: latest, set }) + '\n');
    console.log(JSON.stringify({ ok: plan.ok, why: plan.why, because: plan.because || null,
      walks: plan.walks.length, unreached: plan.unreached.length, rerun: plan.rerun.length,
      changed: plan.changed.length, stale: plan.stale.length, of: set.length }));
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
    // What an earlier check owes is answered by a whole-set run that began
    // after it, so a full run clears the debt.
    const fullSince = latest && latest.complete !== false && latest.began && rotation.at
      && Date.parse(latest.began) > Date.parse(rotation.at);
    const own = forced > 0 ? null : walkSecondsFromLogs(dir);
    const s = pickSlice({
      walks,
      cursor: Number(rotation.cursor) || 0,
      changed: changedWalks(base),
      owed: fullSince ? [] : (rotation.owed || []),
      minutes: Number(arg('--minutes', process.env.PHOTONZ_SLICE_MINUTES || DEFAULTS.sliceMinutes)),
      perWalkSeconds: pace.seconds,
      walkSeconds: own,
    });
    const timed = own ? s.walks.filter((w) => own[w] > 0).length : 0;
    if (argv.includes('--json')) console.log(JSON.stringify({ ...s, of: walks.length, from: Number(rotation.cursor) || 0, laps: Number(rotation.laps) || 0, head, perWalkSeconds: +pace.seconds.toFixed(1), perWalkFrom: pace.from, timed }));
    else for (const w of s.walks) console.log(w);
    process.exit(0);
  }

  // Move the rotation on, from the pick that was actually run rather than from
  // a second guess at it. Picking twice would be one env var away from
  // advancing the cursor past walks nobody ran. With --log, only past what the
  // run's log says was answered (settleSlice): a check stopped on the clock
  // moves on by the walks it finished, and owes the changed ones it did not.
  // Prints what it did as one JSON line, and writes it back into the pick
  // (`settled`) so the record of the check can say where the cursor went.
  if (argv.includes('--advance')) {
    const pickFile = arg('--advance');
    const pick = readJSON(pickFile);
    if (!pick) { console.error('!! nothing to advance from'); process.exit(1); }
    const logFile = arg('--log', null);
    const answered = logFile ? answeredInLog(existsSync(logFile) ? readFileSync(logFile, 'utf8') : '') : null;
    const r = settleSlice(pick, answered);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'rotation.json'), JSON.stringify({
      cursor: r.cursor,
      lastHead: pick.head || head,
      laps: (Number(pick.laps) || 0) + (r.lap ? 1 : 0),
      ran: (pick.walks || []).length - r.unanswered.length,
      changed: pick.changed || [],
      owed: r.owed,
      // Whether it got through every walk it picked. One that did not is due
      // again after the four hour floor even with no new code (decide).
      cutShort: !r.complete,
      of: pick.of || 0,
      at: new Date().toISOString(),
    }, null, 2) + '\n');
    const settled = { from: Number(pick.from) || 0, to: r.cursor, moved: r.moved, of: r.of, owed: r.owed.length, unanswered: r.unanswered.length, lap: r.lap };
    try { writeFileSync(pickFile, JSON.stringify({ ...pick, settled }) + '\n'); } catch { /* the record falls back on nextCursor */ }
    console.log(JSON.stringify(settled));
    process.exit(0);
  }

  // Printed by `queue/bin/sweep.sh schedule`, so there is one copy of these
  // sentences and it is the one the code runs off.
  const f = DEFAULTS.floorHours;
  const sf = Number(process.env.PHOTONZ_SLICE_FLOOR_HOURS || DEFAULTS.sliceFloorHours);
  const perDay = 24 / sf;
  const pace = sliceWalkSecondsFromDisk();
  const own = walkSecondsFromLogs(dir);
  const set = walkNames();
  const lap = lapEstimate({ walks: set, walkSeconds: own, perWalkSeconds: pace.seconds, sliceFloorHours: sf });
  const timed = set.filter((w) => own[w] > 0).length;
  const days = (n) => (n < 1.5 ? 'about a day' : `about ${Math.round(n)} days`);
  // What the checks really did lately, once the history says how far they went.
  const moves = [];
  const hist = join(REPO, 'queue', 'history.jsonl');
  if (existsSync(hist)) {
    for (const line of readFileSync(hist, 'utf8').split('\n')) {
      if (!line.includes('"slice_pass"') || !line.includes('"moved"')) continue;
      try { const o = JSON.parse(line); if (Number.isFinite(o.moved)) moves.push(o.moved); } catch { /* torn */ }
    }
  }
  const recent = moves.slice(-12);
  let seen = '';
  if (recent.length >= 3) {
    const per = recent.reduce((a, b) => a + b, 0) / recent.length;
    seen = `\n  The last ${recent.length} checks moved the rotation on ${per.toFixed(0)} walks each; at that\n  pace a lap takes ${per > 0 ? days(set.length / per / perDay) : 'for ever'}.`;
  }
  const everyDays = f % 24 === 0
    ? (f === 24 ? 'once a day' : `every ${['', '', 'two', 'three', 'four', 'five', 'six', 'seven'][f / 24] || f / 24} days`)
    : `${f} hours apart`;
  console.log(`The walk sweep's schedule

  The full set runs at most once every ${f} hours, so ${everyDays}, and only when
  code has landed since the last one. Asking for a sweep does not start one: the
  requests pile up and the next run serves them all.

  Landed code is the ask: neither check waits for a request. Code is anything
  under ${WALK_PATHS.join(', ')}; a commit of only the queue's
  own files, docs or unit tests starts nothing.

  In between, after a task that lands code, the loop runs a rotating check of
  about ${DEFAULTS.sliceMinutes} minutes, at most one every ${sf} hours: the walks every check runs
  (${DEFAULTS.everyCheck.join(', ')}),
  every walk whose script changed since the last check (at most half the
  check; the rest wait for the next one), then the next chunk of the set in
  rotation, carrying on where it stopped.

  How many walks fit is measured, not guessed: each walk is planned at its own
  recent time from the run logs (${timed} of ${set.length} walks have one), and a walk
  with none at ${pace.seconds.toFixed(1)}s, ${pace.from}. With no
  changed walks a check moves the rotation on about ${lap.perCheck} walks on average, many
  of the quick ones or two or three of the slow Ask ones. At ${+perDay.toFixed(1)} checks a day at
  most, a lap of the ${set.length} walks takes ${lap.checks} checks, ${days(lap.days)}, so most walks are
  answered by the whole set, every ${f / 24 === 3 ? 'three' : f / 24} days, before the rotation reaches them.${seen}

  A check stopped on the clock (three times its budget) keeps what it
  finished: the rotation moves on past the walks it answered, the walk it was
  in and every one after it run first next time, and a changed walk it never
  reached is carried over. Such a check is due again after ${sf} hours even if no
  new code has landed.

  A rotating check is not a sweep. It never closes the standing walk task and
  its green is never the state of the walk set. A walk it finds broken goes
  onto the open task that owns it, or else onto the standing walk task, which
  it opens if none is open: one new task per check at most. An owner blocked
  on a card does not count: the standing task takes that walk too.

  A whole-set run that is stopped part way (the person came back) picks up
  where it stopped, code landed or not: as soon as the Mac is free the next
  one runs only the walks it never answered, the ones it saw fail, any whose
  script changed since and any whose answer is over ${f} hours old, and the
  parts count as one run of the set once every walk has an answer inside one
  ${f} hour window. Until the Mac is free the rotating check carries on.

  A runner that changed something every walk touches can jump the floor:
      queue/bin/sweep.sh request --now "<why the whole set, right now>"

  Where the loop's day actually goes:  queue/bin/loop-day.mjs`);
}
