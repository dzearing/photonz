// What a sweep makes of the run it just watched, and the words it says about
// it. One reading, used by the status line, the standing failing-walks task and
// the dashboard, so those three can never disagree about what happened.
//
// There are five answers a sweep can come back with:
//
//   complete   it ran every walk in the set. The counts are the state of the set.
//   partial    the Mac's screen was locked, so it ran the walks a lock cannot
//              touch and the rest were refused (PlaytestLockSafety). Real
//              counts for a real part of the set, and never the whole of it.
//   locked     the screen was locked and not one walk got through.
//   blind      the app stopped launching part way through, so every walk from
//              there on had nothing to run in and was written down as failing
//              in 0s. Those are unanswered, never failures, and a run with that
//              hole in it is never the state of the set. On 2026-09-21 one of
//              these reported 438 of 553 walks broken on code that passed 537
//              of 544 that morning.
//   cut short  it was stopped part way, either on the clock or because whoever
//              was running it died. What it never reached is unknown, not
//              passing, and what failed in its last moments is not confirmed
//              either: a stop takes the probe app down with it, so the walk in
//              flight and the one after it fail for the stop rather than for
//              the app. A cut-short run names its failures as UNCONFIRMED and
//              leaves confirming them to the next full sweep.
//
// The partial one is why this file exists. The Mac was locked from 2026-09-15
// and the sweep filed NOTHING for three days rather than report on half a set,
// while about 224 of the 521 walks were running under that lock perfectly well
// and photographing the app for real. Silence is not the honest answer to that:
// saying what ran, and saying plainly it is a part, is.
//
// Drill: queue/bin/sweep-parse-drill.mjs

// One walk's line out of playtest-all.sh: "name   7s  ok", with whatever the
// verdict said after it ("FAILED  step 23 (shortcut): ...").
const WALK_LINE = /^([a-z0-9][a-z0-9-]*) +(\d+)s {2}(ok|FAILED|CRASHED|COULD NOT RUN|COULD NOT START)(?: {2}(.*))?$/;
// Its summary line. The crash count is only there when the app died in one of
// the walks, and the refused count only when a locked screen turned some away.
const COUNTS = /^==> (\d+) passed, (\d+) failed(?:, (\d+) crashed)?(?:, (\d+) could not run)?(?:, (\d+) could not start)?$/m;
// What the app died of, one line per crashed walk, in the paragraph above the
// counts: "    unique-layer-names-walk: EXC_CRASH (SIGABRT) in ...".
const CRASH_WHY = /^ {4}([a-z0-9][a-z0-9-]*): (\S.*)$/;
// A walk name in the indented list under the summary. Deliberately narrow: the
// locked run prints prose at the same indent, and a sentence must never be read
// as the name of a failing walk.
const LISTED = /^ {4}([a-z0-9][a-z0-9-]*)$/;
// A walk that was started and never finished: its name, padded, and nothing
// after it. Only ever read off the LAST line of a log, so a stray name
// elsewhere is not mistaken for one.
const UNFINISHED_LINE = /^([a-z0-9][a-z0-9-]*) *$/;

// How many walks in a row have to find the app missing before the run is called
// BLIND rather than unlucky. One walk can fail to get the probe up on its own
// (a previous copy still shutting down), and that is a flake. Five in a row is
// not: the app is not coming back, and every walk after it is being marked
// broken for something that is not about the walk at all.
export const BLIND_AFTER = 5;

// The two ways a walk says "there was no app to drive". The second is the
// sentence playtest-all printed before 2026-09-22, when a probe that would not
// launch took playtest.sh's `set -e` out from under it and left no verdict at
// all; logs from then still have to read correctly, which is what the
// 2026-09-21 run that started all this is.
const wouldNotStart = (w) => w.verdict === 'COULD NOT START'
  || (w.verdict === 'FAILED' && w.why === 'no done.json');

// Which walks were answered by nothing at all, because the app had stopped
// launching. Only runs of BLIND_AFTER or more count, so a single flake stays a
// failure and is still looked at.
function blindStreaks(seen) {
  const blind = new Set();
  let run = [];
  const settle = () => {
    if (run.length >= BLIND_AFTER) for (const n of run) blind.add(n);
    run = [];
  };
  for (const w of seen) {
    if (wouldNotStart(w)) run.push(w.name);
    else settle();
  }
  settle();
  return blind;
}

export function parseSweepLog(text, { total = 0, timedOut = false, interrupted = false } = {}) {
  const lines = String(text || '').split('\n');
  const seen = [];
  for (const l of lines) {
    const m = l.match(WALK_LINE);
    if (m) seen.push({ name: m[1], verdict: m[3], why: (m[4] || '').trim() });
  }
  // The walk that was RUNNING when the stop arrived. playtest-all prints the
  // name padded to forty columns and only fills in the verdict when the walk is
  // over, so a killed run ends in a bare name with no verdict. Naming it matters
  // twice: it is not a pass, and it is the walk most likely to be a casualty of
  // the stop rather than a break.
  let unfinished = null;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (!lines[i].length) continue;
    const m = lines[i].match(UNFINISHED_LINE);
    if (m) unfinished = m[1];
    break;
  }
  const counts = text.match(COUNTS);
  // A walk whose APP DIED. It is a failure and is filed like one, and it is
  // also the one kind of failure that says nothing after it can be trusted, so
  // it is carried by name with what it died in. Before 2026-09-18 a crash
  // printed the same "no done.json" a slow walk prints and four sweeps in a row
  // read twenty-one crashes as seven slow walks.
  const crashed = [];
  for (const l of lines) {
    const m = l.match(CRASH_WHY);
    if (m && seen.some((w) => w.name === m[1] && w.verdict === 'CRASHED')) {
      crashed.push({ name: m[1], why: m[2] });
    }
  }
  for (const w of seen) {
    if (w.verdict === 'CRASHED' && !crashed.some((c) => c.name === w.name)) {
      crashed.push({ name: w.name, why: 'the app quit part way through' });
    }
  }
  const failed = [];
  if (counts) {
    // playtest-all lists each failing walk on its own indented line right after
    // the count line, and stops at the next "==>".
    const after = text.slice(text.indexOf(counts[0]) + counts[0].length).split('\n');
    for (const l of after) {
      if (l.trim().startsWith('==>')) break;
      const m = l.match(LISTED);
      if (m) failed.push(m[1]);
    }
  } else {
    // No summary line, so the run was stopped part way. Read the per-walk lines
    // it did print: "it got to walk 58 and these two failed" is worth far more
    // than a row of zeroes.
    for (const w of seen) if (w.verdict === 'FAILED' || w.verdict === 'CRASHED') failed.push(w.name);
  }
  // The walks that had no app to run in. On the night of 2026-09-21 the probe
  // stopped launching 117 walks into a sweep and the remaining 436 were written
  // down as failing, all of them in 0s; the loop then told every runner the app
  // was broken in 438 ways when four of the names, spot-checked, passed in 20s
  // each. A walk nothing ran is not a walk that failed: it is unanswered, and
  // it comes out of the failing list and out of the counts entirely.
  const blindSet = blindStreaks(seen);
  const blindWalks = seen.filter((w) => blindSet.has(w.name)).map((w) => w.name);
  for (let i = failed.length - 1; i >= 0; i--) if (blindSet.has(failed[i])) failed.splice(i, 1);

  const couldNotRun = counts && counts[4] !== undefined
    ? Number(counts[4])
    : seen.filter((w) => w.verdict === 'COULD NOT RUN').length;
  const crashedCount = counts && counts[3] !== undefined ? Number(counts[3]) : crashed.length;
  const ranAll = counts
    ? Number(counts[1]) + Number(counts[2]) + crashedCount
    : seen.filter((w) => w.verdict !== 'COULD NOT RUN' && w.verdict !== 'COULD NOT START').length;
  // Whatever the summary counted, the blind ones were never answers, so they do
  // not belong in "how many walks this run got through" either. Only the ones
  // the run itself counted as FAILED come back out: a walk that said COULD NOT
  // START was never in the failed total to begin with, and subtracting it twice
  // took a run of 20 answered walks down to zero.
  const blindCountedAsFailed = seen
    .filter((w) => blindSet.has(w.name) && w.verdict === 'FAILED').length;
  const ran = Math.max(0, ranAll - blindCountedAsFailed);
  const passed = counts ? Number(counts[1]) : ran - failed.length;
  const screenLocked = couldNotRun > 0;
  return {
    walks: ran,
    passed,
    failed,
    // Named, counted and kept apart from everything else: these walks got no
    // answer, which is not the same news as passing and not the same news as
    // failing. `from` is the walk the app stopped launching at.
    blind: blindWalks.length
      ? { from: blindWalks[0], count: blindWalks.length }
      : null,
    blindWalks,
    // Which walks actually ran, and which the lock turned away. A partial sweep
    // needs both by name: the failing list it writes is only about the walks it
    // ran, and everything it did not run has to be carried across rather than
    // read as having healed.
    ranWalks: seen
      .filter((w) => w.verdict !== 'COULD NOT RUN' && !blindSet.has(w.name))
      .map((w) => w.name),
    refusedWalks: seen.filter((w) => w.verdict === 'COULD NOT RUN').map((w) => w.name),
    couldNotRun,
    crashed,
    // How big the SET was. A run that covered it can count itself from what it
    // ran; a run that was cut short cannot, and inferring it that way is how a
    // narrowed run killed after two walks came out as "2 of 2 walks", which
    // reads as complete coverage. Unknown is 0, and the sentences leave the
    // "of N" off rather than making one up.
    total: total || ((timedOut || interrupted) ? 0 : ran + couldNotRun + blindWalks.length),
    screenLocked,
    // A partial sweep is one that has something to report AND something it
    // could not reach. Locked with nothing through is not partial: there is no
    // part to report.
    partial: screenLocked && ran > 0,
    // Complete means the counts ARE the state of the walk set. A run with
    // refusals in it never is, however many walks it got through, and neither
    // is one that lost the app part way: it has a hole in it the size of every
    // walk it could not put in front of an app.
    complete: Boolean(counts) && !timedOut && !interrupted && couldNotRun === 0
      && blindWalks.length === 0,
    timedOut: Boolean(timedOut),
    // The run did not stop itself: whoever was running it went away. On
    // 2026-09-18 the loop was killed 126 walks into a sweep and every one of
    // those answers was thrown away, along with the request that asked for it.
    interrupted: Boolean(interrupted),
    // The walk that was in flight when the stop landed, if the log ends
    // mid-line. Not a pass and not a failure: it never finished.
    unfinished: (timedOut || interrupted) ? unfinished : null,
  };
}

const took = (seconds) => (seconds >= 60 ? `${Math.round(seconds / 60)}m` : `${seconds}s`);

// Why a run stopped part way. The two reasons read very differently: a sweep
// that hit its own clock cap is usually a wedged probe, while a sweep that was
// interrupted says nothing about the app at all, only that whoever was running
// it went away.
export function cutShortBecause(r) {
  if (r.interrupted) return ' (the run was interrupted: whoever was running it went away)';
  if (r.timedOut) return ' (stopped on the clock)';
  return '';
}

// The app dying is the loudest thing a sweep can find, and the loop only ever
// reads the first sentence, so it goes there rather than in a line underneath.
function crashClause(r) {
  const c = r.crashed || [];
  if (!c.length) return '';
  const named = c.slice(0, 3).map((x) => `${x.name} (${x.why})`).join('; ');
  const more = c.length > 3 ? `, and ${c.length - 3} more` : '';
  return ` The app DIED in ${c.length} of them, which is not a walk running slowly: ${named}${more}.`;
}

// What to say about a recorded sweep, in plain sentences. The first one is the
// headline; the rest bound what it may be read as.
export function sweepSentences(r) {
  const said = sweepSentencesPlain(r);
  const crash = crashClause(r);
  if (crash) said[0] += crash;
  return said;
}

function sweepSentencesPlain(r) {
  const when = r.ended || 'just now';
  // The loudest thing a run can come back with, so it is said first and on its
  // own: not "the app is broken", but "there was no app".
  if (r.blind) {
    const answered = r.walks + (r.couldNotRun || 0);
    return [
      `Last sweep ${when} WENT BLIND: the app stopped launching at ${r.blind.from}, `
        + `and the ${r.blind.count} walks from there on never ran at all.`,
      `Those ${r.blind.count} are unknown. They are not failing: nothing was there to fail. `
        + `No walk is named broken on the strength of this run.`,
      answered
        ? `What it answered first stands: ${answered}${r.total ? ` of ${r.total}` : ''} walks in `
          + `${took(r.seconds || 0)}, ${r.passed} passed, ${r.failed.length} failed.`
        : `It never got an answer out of a single walk, so there is nothing in it about the app `
          + `except that the app would not start.`,
      `A run with a hole in it is not the state of the walk set, so the last run that really `
        + `covered the set stays the record and a full sweep is still owed.`,
    ];
  }
  if (r.partial) {
    return [
      `Last sweep ${when} ran only the part of the walk set a locked screen cannot touch: `
        + `${r.walks} of ${r.total} walks ran in ${took(r.seconds || 0)}, ${r.passed} passed, ${r.failed.length} failed.`,
      `The other ${r.couldNotRun} were refused because the screen is locked and they find a control by its name. `
        + `Those are unknown, not passing.`,
      `This is part of the set and not the state of the walk set, so a full sweep is still owed `
        + `and still pending: it runs once the screen is unlocked.`,
    ];
  }
  if (r.screenLocked) {
    return [
      `Last sweep ${when} COULD NOT RUN: the screen was locked, so every walk that looks a control up by name was refused.`,
      `Not one of the ${r.couldNotRun} walks it tried got through, so nothing was filed. It runs again once the screen is unlocked.`,
    ];
  }
  if (r.complete === false) {
    return [
      `Last sweep ${when} DID NOT FINISH${cutShortBecause(r)}: `
        + `it reached ${r.walks}${r.total ? ` of ${r.total}` : ''} walks in ${took(r.seconds || 0)}, of which ${r.passed} passed.`,
      `The walks it never reached are unknown, not passing.`
        + (r.failed.length
          ? ` The ${r.failed.length} that failed are UNCONFIRMED: a run that stops takes the probe app down with it, `
            + `so a walk failing in its last moments may be a casualty of the stop. The next full sweep decides.`
            + (r.unfinished ? ` ${r.unfinished} never finished at all.` : '')
          : ''),
      `The request that asked for this sweep is pending again; the loop runs another one.`,
    ];
  }
  return [`Last sweep ${when}: ${r.passed}/${r.walks} walks passed in ${took(r.seconds || 0)}.`];
}
