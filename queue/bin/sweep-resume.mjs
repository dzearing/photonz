// A whole-set walk run that was STOPPED picks up where it stopped.
//
// On 2026-10-22 the daily whole-set run began at 04:15 local, ran for 306
// minutes, reached 989 of 1011 walks and was put down at 09:21 because the
// user came back to the Mac (queue/bin/person-at-mac.sh). Everything it found
// was kept, and none of it counted: the record read "did not finish", the
// standing walk task could not be closed by it, and the next whole-set run was
// going to start again at walk one, five more hours of the user's Mac, for
// twenty two walks nobody had answered.
//
// So the next run, when nothing a walk runs has changed since, runs only what
// the stopped one left without an answer, and the two are written down as ONE
// run of the set:
//
//   the remainder   every walk in the set the stopped run never answered (the
//                   one in flight, the ones after it, any a lock refused), plus
//                   every walk it saw FAIL. Those failures are unconfirmed: a
//                   stop takes the probe down with it, so a walk failing in the
//                   last moments may be a casualty of the stop, and the only
//                   honest thing to do with it is run it again.
//   and also        every walk whose own script changed since the stopped run
//                   (its answer is about a walk that is gone), every walk new
//                   to the set (nothing has answered it), and every walk whose
//                   answer is older than the window (WINDOW_HOURS, the same
//                   three days as the floor between whole-set runs).
//   across code     yes, since 2026-11-21. Until then a stopped run was only
//                   carried on from when nothing a walk runs had changed, and
//                   the loop lands app code several times a day, so it never
//                   applied: the runs of 5, 8, 11, 14, 17 and 20 November were
//                   each stopped when the user came back (after 951, 854, 620,
//                   238, 118 and 112 walks), each was thrown away, and the set
//                   did not finish for over two weeks. The 72 hour floor,
//                   counted from each start, had walked the start from 03:38 to
//                   07:21, half an hour before the person sat down. What the
//                   set promises now is what the user asked for: every walk has
//                   an answer inside one three day window. A change that broke
//                   a walk already answered is what the rotating check after
//                   every landed change is for, and the next whole set.
//   complete when   every walk in the set has an answer in the merged record,
//                   every one of them inside the window, and the run that
//                   finished it was not itself cut short. A walk with no answer
//                   anywhere means the merged record is NOT complete, however
//                   green the rest of it is.
//
// The three day ceiling stands: the merged record keeps the stopped run's
// `began`, so the next whole-set run is still counted from when the stopped
// run started, and finishing it is not a second run of the set. The person-away
// rule stands too: the remainder waits for the Mac to be left alone exactly as
// the whole set does (sweep.sh due).
//
// Pure, so the drill can hold it: queue/bin/sweep-resume-drill.mjs

const uniq = (xs) => [...new Set(xs)];
const HOUR = 3600 * 1000;

// How old an answer may be and still count toward one run of the set: the same
// three days as the floor between whole-set runs (sweep-schedule.mjs
// DEFAULTS.floorHours, passed in by the schedule; repeated here only as the
// default so this file imports nothing).
export const WINDOW_HOURS = 72;

// The parts of a record, oldest first. A record written in one go is its own
// only part.
export function partsOf(record) {
  if (!record) return [];
  if (Array.isArray(record.parts) && record.parts.length) return record.parts;
  return [{ began: record.began, ended: record.ended, seconds: Number(record.seconds) || 0,
    walks: record.walks, head: record.head || null }];
}

// When each walk in a record was answered: the start of the part that answered
// it, in ms. A record from before parts said which walk they answered
// (answeredIn) is read as answered when it began, which is the oldest it can
// be, so nothing is ever counted fresher than it was.
export function answeredAt(record) {
  const at = new Map();
  if (!record) return at;
  const parts = partsOf(record);
  const idx = record.answeredIn && typeof record.answeredIn === 'object' ? record.answeredIn : null;
  const fallback = Date.parse(record.began);
  for (const w of record.ranWalks || []) {
    const i = idx && Number.isInteger(idx[w]) ? idx[w] : 0;
    const t = parts[i] && parts[i].began ? Date.parse(parts[i].began) : fallback;
    at.set(w, Number.isFinite(t) ? t : fallback);
  }
  return at;
}

// What a recorded run left without an answer, against the set as it is now.
// `set` is the walk names in the order playtest-all.sh runs them; `changed` the
// walks whose own script changed since the record's oldest part.
export function remainderOf(record, set = [], { now = null, windowHours = WINDOW_HOURS, changed = [] } = {}) {
  const failed = new Set((record && record.failed) || []);
  const ran = new Set((record && record.ranWalks) || []);
  const moved = new Set(changed || []);
  const at = answeredAt(record);
  const oldest = now === null ? -Infinity : now - windowHours * HOUR;
  const unreached = [];
  const rerun = [];
  const stale = [];
  const rewritten = [];
  for (const w of set) {
    if (!ran.has(w)) unreached.push(w);
    else if (failed.has(w)) rerun.push(w);
    else if (moved.has(w)) rewritten.push(w);
    else if ((at.get(w) ?? -Infinity) < oldest) stale.push(w);
  }
  // In the set's own order, so the run reads like a slice of a normal sweep.
  const pick = new Set([...unreached, ...rerun, ...stale, ...rewritten]);
  return { walks: set.filter((w) => pick.has(w)), unreached, rerun, stale, changed: rewritten, of: set.length };
}

// Whether the next whole-set run may be just the remainder of `record`.
// Returns { ok, why, ...remainder } and, when it is not ok, `because`, a short
// key the schedule uses to say why the whole set runs instead.
export function resumable({
  record = null,          // queue/sweep/latest.json
  set = [],               // walk names as they are now
  head = null,            // the commit the loop is on
  codeSince = null,       // whether anything a walk runs changed since record.head
  changed = [],           // walks whose own script changed since the record's oldest part
  now = Date.now(),
  windowHours = WINDOW_HOURS,
  screenLocked = false,
  blind = null,           // queue/sweep/blind.json
} = {}) {
  const no = (because, why) => ({ ok: false, because, why, walks: [], unreached: [], rerun: [], stale: [], changed: [], of: set.length });
  if (!record) return no('none', 'no whole-set run has been recorded');
  if (record.complete !== false) return no('complete', 'the last whole-set run covered the set');
  // A run stopped on its own clock is usually a probe that launched and never
  // drove; carrying on from it would only find the same wedge.
  if (!record.interrupted) {
    return no('not-stopped', record.timedOut
      ? 'the last whole-set run was stopped on its clock, which says the probe wedged, so the whole set runs again'
      : 'the last whole-set run did not stop part way');
  }
  if (!Array.isArray(record.ranWalks)) return no('old-record', 'the stopped run did not write down which walks it reached');
  if (!record.head || !head) return no('no-commit', 'the stopped run did not write down its commit');
  // A lock would only refuse the walks that need a control's name, which is
  // most of what a remainder is made of. Wait for the screen.
  if (screenLocked) return no('locked', 'the screen is locked, so the rest of the stopped run waits for it to be unlocked');
  // The run that was meant to finish it went blind on this code. Trying again
  // would go blind at the same walk; that is the blind rule's business.
  const blindAfter = blind && blind.began && record.ended && Date.parse(blind.began) > Date.parse(record.ended);
  if (blindAfter && blind.head && (blind.head === head || codeSince === false)) {
    return no('blind', 'the run that was finishing the stopped one went blind on this code');
  }
  const rest = remainderOf(record, set, { now, windowHours, changed });
  // Not one answer it holds is inside the window any more: there is nothing to
  // carry on from, and the next run is the whole set from the start.
  if (rest.walks.length && rest.walks.length === set.length) {
    return no('stale', `every answer the stopped run of ${record.began} holds is more than ${windowHours} hours old, so the whole set runs again`);
  }
  if (!rest.walks.length) return { ...no('nothing-left', 'the stopped run left nothing unanswered'), ...rest, ok: false };
  const parts = partsOf(record).length;
  const also = [];
  if (rest.rerun.length) also.push(`the ${rest.rerun.length} it saw fail`);
  if (rest.changed.length) also.push(`${rest.changed.length} whose script changed since`);
  if (rest.stale.length) also.push(`${rest.stale.length} whose answer is over ${windowHours} hours old`);
  const tail = also.length ? `, plus ${also.length > 1 ? `${also.slice(0, -1).join(', ')} and ${also[also.length - 1]}` : also[0]},` : '';
  const code = codeSince === false || record.head === head ? 'nothing a walk runs has changed since'
    : 'code has landed since and its answers still count';
  return {
    ok: true,
    ...rest,
    why: `the whole-set run of ${record.began} was stopped at ${record.walks} of ${set.length}`
      + `${parts > 1 ? ` after ${parts} parts` : ''}; ${code}, so the `
      + `${rest.unreached.length} walks it never answered${tail} run to finish it`,
  };
}

// The stopped run and the run that carried on from it, written down as one run
// of the set. `prev` is the record that was resumed, `cur` the record the
// carrying-on run would have written on its own (sweep-record.mjs's shape).
export function mergeRuns(prev, cur, set = [], { windowHours = WINDOW_HOURS } = {}) {
  const answeredNow = new Set(cur.ranWalks || []);
  const failedNow = new Set(cur.failed || []);
  const failedBefore = new Set(prev.failed || []);
  const inSet = new Set(set);
  // Only walks the set still names: once code may land between the parts, a
  // walk can be removed or renamed between them, and an answer for a walk that
  // no longer exists is not an answer for anything in the set.
  const ranAll = new Set([...(prev.ranWalks || []), ...(cur.ranWalks || [])].filter((w) => inSet.has(w)));
  // A walk this run answered is answered by this run. One it did not reach
  // keeps whatever the stopped run said about it, failures included: an
  // unconfirmed failure stays a failure until something runs it again.
  const isFailed = (w) => failedNow.has(w) || (failedBefore.has(w) && !answeredNow.has(w));
  const ranWalks = set.filter((w) => ranAll.has(w));
  const failed = ranWalks.filter(isFailed);
  const crashed = uniq([
    ...(cur.crashed || []).map((c) => c.name),
    ...(prev.crashed || []).filter((c) => !answeredNow.has(c.name) && inSet.has(c.name)).map((c) => c.name),
  ]).map((name) => (cur.crashed || []).find((c) => c.name === name)
    || (prev.crashed || []).find((c) => c.name === name));
  const refusedWalks = uniq([
    ...(prev.refusedWalks || []).filter((w) => !ranAll.has(w)),
    ...(cur.refusedWalks || []),
  ]).filter((w) => !ranAll.has(w) && inSet.has(w));
  const unanswered = set.filter((w) => !ranAll.has(w));
  const keyOf = (r) => `${r.t}|${r.by}`;
  const requests = [];
  for (const r of [...(prev.requests || []), ...(cur.requests || [])]) {
    if (!requests.some((x) => keyOf(x) === keyOf(r))) requests.push(r);
  }
  const partOf = (r) => ({
    began: r.began, ended: r.ended, seconds: Number(r.seconds) || 0, walks: r.walks,
    failed: (r.failed || []).length, log: r.log || null,
    interrupted: !!r.interrupted, timedOut: !!r.timedOut, head: r.head || null,
    ...(r.stoppedBy ? { stoppedBy: r.stoppedBy } : {}),
  });
  const prevParts = Array.isArray(prev.parts) && prev.parts.length ? prev.parts : [partOf(prev)];
  const parts = prevParts.concat([{ ...partOf(cur), seconds: Number(cur.seconds) || 0 }]);
  // Which part answered each walk, so the window can be read walk by walk.
  const prevIdx = prev.answeredIn && typeof prev.answeredIn === 'object' ? prev.answeredIn : {};
  const answeredIn = {};
  for (const w of ranWalks) {
    answeredIn[w] = answeredNow.has(w) ? parts.length - 1 : (Number.isInteger(prevIdx[w]) ? prevIdx[w] : 0);
  }
  // Every answer has to sit inside one window, counted back from the end of
  // the part that finished it. A remainder already reruns answers that have
  // aged out, so this only bites when the parts themselves spread too far.
  const endedAt = Date.parse(cur.ended);
  const oldestAnswer = ranWalks.reduce((m, w) => {
    const t = Date.parse(parts[answeredIn[w]] && parts[answeredIn[w]].began);
    return Number.isFinite(t) ? Math.min(m, t) : m;
  }, Infinity);
  const inWindow = !Number.isFinite(endedAt) || !Number.isFinite(oldestAnswer)
    || endedAt - oldestAnswer <= windowHours * HOUR;
  const cutShort = !!(cur.timedOut || cur.interrupted || cur.blind);
  const complete = unanswered.length === 0 && !cutShort && refusedWalks.length === 0 && inWindow;
  return {
    // The set's run began when the stopped run began: the floor between
    // whole-set runs is counted from it, so finishing a run is never a second
    // run of the set.
    began: prev.began,
    ended: cur.ended,
    // The time the set cost, both parts, and what this part cost on its own.
    // The loop's day (loop-day.mjs) and the size of a walk (sweep-size.mjs)
    // read the part, never the sum, from the event the loop logs.
    seconds: (Number(prev.seconds) || 0) + (Number(cur.seconds) || 0),
    walks: ranWalks.length,
    passed: ranWalks.length - failed.length,
    failed,
    couldNotRun: refusedWalks.length,
    total: set.length,
    crashed,
    blind: null, blindWalks: [],
    ranWalks, refusedWalks,
    answeredIn,
    requests,
    log: cur.log,
    complete,
    timedOut: !!cur.timedOut,
    interrupted: !!cur.interrupted,
    ...(cur.stoppedBy ? { stoppedBy: cur.stoppedBy } : {}),
    unfinished: cur.unfinished || null,
    screenLocked: !!cur.screenLocked,
    partial: refusedWalks.length > 0 && ranWalks.length > 0,
    head: cur.head || prev.head || null,
    parts,
    // Whether the parts ran on different code: said in the sentences, so a
    // set answered across a change is never read as one sitting on one build.
    acrossCode: uniq(parts.map((p) => p.head).filter(Boolean)).length > 1,
    // What this part did, for the sentences and the loop's event.
    resumed: {
      from: prev.began,
      reached: prev.walks,
      ran: cur.walks,
      seconds: Number(cur.seconds) || 0,
      reran: (cur.ranWalks || []).filter((w) => failedBefore.has(w)).length,
      confirmed: (cur.ranWalks || []).filter((w) => failedBefore.has(w) && failedNow.has(w)),
      cleared: (cur.ranWalks || []).filter((w) => failedBefore.has(w) && !failedNow.has(w)),
      unanswered: unanswered.length,
      outOfWindow: !inWindow,
    },
  };
}
