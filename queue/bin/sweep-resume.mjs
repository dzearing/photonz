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
//   sound only on   the same code. "Code" is everything a walk runs
//                   (WALK_PATHS in sweep-schedule.mjs, the same rule that says
//                   when code has landed); the loop commits its own queue
//                   files all day and those change nothing a walk can see.
//                   When code HAS landed, the stopped run's answers are about
//                   code that is gone, and the whole set runs again when the
//                   day is up, exactly as it did before this file. Running the
//                   remainder plus "the walks the change touched" was weighed
//                   and turned down: any change under Sources can reach any
//                   walk, and nothing here can tell which ones it did.
//   complete when   every walk in the set has an answer in the merged record,
//                   and the run that finished it was not itself cut short. A
//                   walk with no answer anywhere means the merged record is
//                   NOT complete, however green the rest of it is.
//
// The once-a-day ceiling stands: the merged record keeps the stopped run's
// `began`, so the next whole-set run is still counted from when the day's run
// started, and finishing it is not a second run of the day. The person-away
// rule stands too: the remainder waits for the Mac to be left alone exactly as
// the whole set does (sweep.sh due).
//
// Pure, so the drill can hold it: queue/bin/sweep-resume-drill.mjs

const uniq = (xs) => [...new Set(xs)];

// What a recorded run left without an answer, against the set as it is now.
// `set` is the walk names in the order playtest-all.sh runs them.
export function remainderOf(record, set = []) {
  const failed = new Set((record && record.failed) || []);
  const ran = new Set((record && record.ranWalks) || []);
  const unreached = [];
  const rerun = [];
  for (const w of set) {
    if (failed.has(w)) rerun.push(w);
    else if (!ran.has(w)) unreached.push(w);
  }
  // In the set's own order, so the run reads like a slice of a normal sweep.
  const pick = new Set([...unreached, ...rerun]);
  return { walks: set.filter((w) => pick.has(w)), unreached, rerun, of: set.length };
}

// Whether the next whole-set run may be just the remainder of `record`.
// Returns { ok, why, ...remainder } and, when it is not ok, `because`, a short
// key the schedule uses to say why the whole set runs instead.
export function resumable({
  record = null,          // queue/sweep/latest.json
  set = [],               // walk names as they are now
  head = null,            // the commit the loop is on
  codeSince = null,       // whether anything a walk runs changed since record.head
  screenLocked = false,
  blind = null,           // queue/sweep/blind.json
} = {}) {
  const no = (because, why) => ({ ok: false, because, why, walks: [], unreached: [], rerun: [], of: set.length });
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
  if (!(record.head === head || codeSince === false)) {
    return no('code', 'code has landed since the last whole-set run was stopped, so what it reached '
      + 'is about code that is gone and the whole set runs again');
  }
  // The set itself moved (a walk added or removed). The walk scripts are code
  // too, so this is belt and braces, but a remainder against the wrong set is
  // exactly the hole this file must never leave.
  if (record.total && record.total !== set.length) {
    return no('set', `the walk set was ${record.total} walks when the run stopped and is ${set.length} now`);
  }
  // A lock would only refuse the walks that need a control's name, which is
  // most of what a remainder is made of. Wait for the screen.
  if (screenLocked) return no('locked', 'the screen is locked, so the rest of the stopped run waits for it to be unlocked');
  // The run that was meant to finish it went blind on this code. Trying again
  // would go blind at the same walk; that is the blind rule's business.
  const blindAfter = blind && blind.began && record.ended && Date.parse(blind.began) > Date.parse(record.ended);
  if (blindAfter && blind.head && (blind.head === head || codeSince === false)) {
    return no('blind', 'the run that was finishing the stopped one went blind on this code');
  }
  const rest = remainderOf(record, set);
  if (!rest.walks.length) return { ...no('nothing-left', 'the stopped run left nothing unanswered'), ...rest, ok: false };
  const parts = Array.isArray(record.parts) ? record.parts.length : 1;
  const failing = rest.rerun.length ? ` and the ${rest.rerun.length} it saw fail` : '';
  return {
    ok: true,
    ...rest,
    why: `the whole-set run of ${record.began} was stopped at ${record.walks} of ${set.length}`
      + `${parts > 1 ? ` after ${parts} parts` : ''} and nothing a walk runs has changed since, so the `
      + `${rest.unreached.length} walks it never answered${failing} run to finish it`,
  };
}

// The stopped run and the run that carried on from it, written down as one run
// of the set. `prev` is the record that was resumed, `cur` the record the
// carrying-on run would have written on its own (sweep-record.mjs's shape).
export function mergeRuns(prev, cur, set = []) {
  const answeredNow = new Set(cur.ranWalks || []);
  const failedNow = new Set(cur.failed || []);
  const failedBefore = new Set(prev.failed || []);
  const ranAll = new Set([...(prev.ranWalks || []), ...(cur.ranWalks || [])]);
  const inSet = new Set(set);
  // A walk this run answered is answered by this run. One it did not reach
  // keeps whatever the stopped run said about it, failures included: an
  // unconfirmed failure stays a failure until something runs it again.
  const isFailed = (w) => failedNow.has(w) || (failedBefore.has(w) && !answeredNow.has(w));
  const ranWalks = set.filter((w) => ranAll.has(w))
    // Never lose an answer for a walk the set no longer names; it cannot happen
    // on the same code, and if it ever does the record keeps it rather than
    // pretending it was not run.
    .concat([...ranAll].filter((w) => !inSet.has(w)));
  const failed = ranWalks.filter(isFailed);
  const crashed = uniq([
    ...(cur.crashed || []).map((c) => c.name),
    ...(prev.crashed || []).filter((c) => !answeredNow.has(c.name)).map((c) => c.name),
  ]).map((name) => (cur.crashed || []).find((c) => c.name === name)
    || (prev.crashed || []).find((c) => c.name === name));
  const refusedWalks = uniq([
    ...(prev.refusedWalks || []).filter((w) => !ranAll.has(w)),
    ...(cur.refusedWalks || []),
  ]).filter((w) => !ranAll.has(w));
  const unanswered = set.filter((w) => !ranAll.has(w));
  const cutShort = !!(cur.timedOut || cur.interrupted || cur.blind);
  const complete = unanswered.length === 0 && !cutShort && refusedWalks.length === 0;
  const keyOf = (r) => `${r.t}|${r.by}`;
  const requests = [];
  for (const r of [...(prev.requests || []), ...(cur.requests || [])]) {
    if (!requests.some((x) => keyOf(x) === keyOf(r))) requests.push(r);
  }
  const partOf = (r) => ({
    began: r.began, ended: r.ended, seconds: Number(r.seconds) || 0, walks: r.walks,
    failed: (r.failed || []).length, log: r.log || null,
    interrupted: !!r.interrupted, timedOut: !!r.timedOut,
  });
  const parts = (Array.isArray(prev.parts) && prev.parts.length ? prev.parts : [partOf(prev)])
    .concat([{ ...partOf(cur), seconds: Number(cur.seconds) || 0 }]);
  return {
    // The day's run began when the stopped run began: the once-a-day floor is
    // counted from it, so finishing a run is never a second run of the day.
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
    requests,
    log: cur.log,
    complete,
    timedOut: !!cur.timedOut,
    interrupted: !!cur.interrupted,
    unfinished: cur.unfinished || null,
    screenLocked: !!cur.screenLocked,
    partial: refusedWalks.length > 0 && ranWalks.length > 0,
    head: cur.head || prev.head || null,
    parts,
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
    },
  };
}
