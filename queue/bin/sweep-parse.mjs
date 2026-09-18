// What a sweep makes of the run it just watched, and the words it says about
// it. One reading, used by the status line, the standing failing-walks task and
// the dashboard, so those three can never disagree about what happened.
//
// There are four answers a sweep can come back with:
//
//   complete   it ran every walk in the set. The counts are the state of the set.
//   partial    the Mac's screen was locked, so it ran the walks a lock cannot
//              touch and the rest were refused (PlaytestLockSafety). Real
//              counts for a real part of the set, and never the whole of it.
//   locked     the screen was locked and not one walk got through.
//   cut short  it was stopped on the clock part way. What it never reached is
//              unknown, not passing.
//
// The partial one is why this file exists. The Mac was locked from 2026-09-15
// and the sweep filed NOTHING for three days rather than report on half a set,
// while about 224 of the 521 walks were running under that lock perfectly well
// and photographing the app for real. Silence is not the honest answer to that:
// saying what ran, and saying plainly it is a part, is.
//
// Drill: queue/bin/sweep-parse-drill.mjs

// One walk's line out of playtest-all.sh: "name   7s  ok".
const WALK_LINE = /^([a-z0-9][a-z0-9-]*) +(\d+)s {2}(ok|FAILED|CRASHED|COULD NOT RUN)/;
// Its summary line. The crash count is only there when the app died in one of
// the walks, and the refused count only when a locked screen turned some away.
const COUNTS = /^==> (\d+) passed, (\d+) failed(?:, (\d+) crashed)?(?:, (\d+) could not run)?$/m;
// What the app died of, one line per crashed walk, in the paragraph above the
// counts: "    unique-layer-names-walk: EXC_CRASH (SIGABRT) in ...".
const CRASH_WHY = /^ {4}([a-z0-9][a-z0-9-]*): (\S.*)$/;
// A walk name in the indented list under the summary. Deliberately narrow: the
// locked run prints prose at the same indent, and a sentence must never be read
// as the name of a failing walk.
const LISTED = /^ {4}([a-z0-9][a-z0-9-]*)$/;

export function parseSweepLog(text, { total = 0, timedOut = false } = {}) {
  const lines = String(text || '').split('\n');
  const seen = [];
  for (const l of lines) {
    const m = l.match(WALK_LINE);
    if (m) seen.push({ name: m[1], verdict: m[3] });
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
  const couldNotRun = counts && counts[4] !== undefined
    ? Number(counts[4])
    : seen.filter((w) => w.verdict === 'COULD NOT RUN').length;
  const crashedCount = counts && counts[3] !== undefined ? Number(counts[3]) : crashed.length;
  const ran = counts
    ? Number(counts[1]) + Number(counts[2]) + crashedCount
    : seen.filter((w) => w.verdict !== 'COULD NOT RUN').length;
  const passed = counts ? Number(counts[1]) : ran - failed.length;
  const screenLocked = couldNotRun > 0;
  return {
    walks: ran,
    passed,
    failed,
    // Which walks actually ran, and which the lock turned away. A partial sweep
    // needs both by name: the failing list it writes is only about the walks it
    // ran, and everything it did not run has to be carried across rather than
    // read as having healed.
    ranWalks: seen.filter((w) => w.verdict !== 'COULD NOT RUN').map((w) => w.name),
    refusedWalks: seen.filter((w) => w.verdict === 'COULD NOT RUN').map((w) => w.name),
    couldNotRun,
    crashed,
    total: total || ran + couldNotRun,
    screenLocked,
    // A partial sweep is one that has something to report AND something it
    // could not reach. Locked with nothing through is not partial: there is no
    // part to report.
    partial: screenLocked && ran > 0,
    // Complete means the counts ARE the state of the walk set. A run with
    // refusals in it never is, however many walks it got through.
    complete: Boolean(counts) && !timedOut && couldNotRun === 0,
    timedOut: Boolean(timedOut),
  };
}

const took = (seconds) => (seconds >= 60 ? `${Math.round(seconds / 60)}m` : `${seconds}s`);

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
      `Last sweep ${when} DID NOT FINISH${r.timedOut ? ' (stopped on the clock)' : ''}: `
        + `it reached ${r.walks} walks in ${took(r.seconds || 0)}, of which ${r.passed} passed.`,
      `The walks it never reached are unknown, not passing. Ask for another sweep if you need the whole set.`,
    ];
  }
  return [`Last sweep ${when}: ${r.passed}/${r.walks} walks passed in ${took(r.seconds || 0)}.`];
}
