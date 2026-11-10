#!/usr/bin/env node
// How big the walk sweep really is, worked out rather than remembered.
//
// Eleven files tell whoever is working here how many scripted walks there are
// and how long a full sweep takes, and that number is not decoration: it is the
// whole reason a task runner is forbidden to start a sweep, and it is what the
// sweep's own wall-clock stop is set against. It was typed in by hand, so it
// went stale: on 2026-09-19 every one of those files still said 322 walks and
// about 52 minutes while the set had grown to 532 and a full run was nearer a
// hundred minutes. Half the sentence that justified the two-hour cap had
// stopped being true, and nothing anywhere noticed.
//
// So nobody types the number again. It comes from two things on disk:
//
//   walks       ls Scripts/playtest/*.json, which is the exact glob
//               Scripts/playtest-all.sh iterates, so it cannot drift from what
//               a sweep actually runs.
//   per walk    the median of the last ten real sweeps in queue/history.jsonl.
//               A sweep records how many walks ran, how many a locked screen
//               refused, and how many seconds it took; a refused walk costs
//               about 0.9s, so the cost of a real one is
//               (seconds - refused * 0.9) / ran.
//
// Both files are tracked by git, so this works on a fresh checkout and in CI.
//
//   queue/bin/sweep-size.mjs            the numbers and the arithmetic behind them
//   queue/bin/sweep-size.mjs --json     the same, for a script
//   queue/bin/sweep-size.mjs --check    every place that quotes them still agrees
//   queue/bin/sweep-size.mjs --write    bring those places back into line
//   queue/bin/sweep-size.mjs --sync     what the loop runs after every task: if
//                                       what is COMMITTED has drifted past half
//                                       the CI band, rewrite and commit it
//
// --check runs in CI (.github/workflows/ci.yml), which is what stops the next
// hundred walks making the docs wrong in silence again.
//
// Drill: queue/bin/sweep-size-drill.mjs
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// A walk a locked screen turned away prints its line in about this long: it is
// refused before the app is even asked to do anything. Measured across the
// 2026-09-19 sweeps, where 270 refusals came to 242 seconds.
const REFUSAL_SECONDS = 0.9;

// The seconds a sweep is ALLOWED per walk before it is stopped. Not the
// measured cost and deliberately not derived from it: this is the safety net,
// and a net whose size follows the thing it is catching is no net. See
// capMinutes() for why this number. Was 20 until 2026-10-02, when a walk had
// crept to 14.6s (the median of the last ten sweeps) and the net was down to 37
// per cent over a good sweep; 24 puts it back above half again. Raised to 26
// on 2026-10-06, when the median had reached 16.2s and 24 was 48 per cent over
// it: 26 is 60 per cent over, and a probe that never drives is still stopped
// about a seventh of the way into the set.
export const BUDGET_SECONDS_PER_WALK = 26;

// ...and from 2026-11-10 that is the FLOOR, not the whole answer. Walks kept
// slowing (a median of 20.8s by then, single sweeps at 23 to 27s) and the fixed
// number had to be raised by hand three times; the third time nobody did, the
// net was 25 per cent over a good sweep, the 2026-11-08 sweep ran at 26.9s a
// walk (above the net), and the drill that says so sat behind the red step
// above it in CI. So the budget is BUDGET_HEADROOM times the measured median,
// never under the floor and never over BUDGET_CEILING_SECONDS.
//
// It follows the median of the last ten sweeps that FINISHED, and a run the
// cap stopped is not one of them (sweepRuns drops timedOut), so a wedged probe
// cannot widen the net that catches it: it would take ten slow but finished
// sweeps in a row. The ceiling keeps the catch early: 40s a walk stops a probe
// that never drives (180s a walk) under a quarter of the way into the set.
// A median past 25s pins the budget at the ceiling and the drill goes red,
// which is then a real finding: walks have slowed past what this was sized for.
export const BUDGET_HEADROOM = 1.6;
export const BUDGET_CEILING_SECONDS = 40;
export function budgetSecondsFor(perWalk = 0) {
  return Math.min(BUDGET_CEILING_SECONDS, Math.max(BUDGET_SECONDS_PER_WALK, Math.ceil(perWalk * BUDGET_HEADROOM)));
}

// A run reporting less than this per walk did not really run: the probe failed
// to build, or every walk bailed in the first second. Real walks have never
// come in under 9s. Keeping these out matters because one of them is already in
// the history (2026-09-19T19:01, 519 walks in 361 seconds).
const PLAUSIBLE = { min: 3, max: 60 };

// Used only when the history has nothing to go on, which is a fresh checkout.
// The median across every real sweep recorded in September 2026.
const FALLBACK_PER_WALK = 12;

export function walkCount(repo = REPO) {
  const dir = join(repo, 'Scripts', 'playtest');
  if (!existsSync(dir)) return 0;
  // The same glob Scripts/playtest-all.sh iterates: top level only, so
  // studies/ and fixtures/ are out, exactly as they are out of a sweep.
  return readdirSync(dir).filter((f) => f.endsWith('.json')).length;
}

export function sweepRuns(repo = REPO) {
  const file = join(repo, 'queue', 'history.jsonl');
  if (!existsSync(file)) return [];
  const out = [];
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (!line.includes('"sweep_pass"')) continue;
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (o.ev !== 'sweep_pass' || o.timedOut) continue;
    const ran = Number(o.walks) || 0;
    const seconds = Number(o.seconds) || 0;
    if (ran < 100 || seconds <= 0) continue;
    const perWalk = (seconds - (Number(o.couldNotRun) || 0) * REFUSAL_SECONDS) / ran;
    if (perWalk < PLAUSIBLE.min || perWalk > PLAUSIBLE.max) continue;
    out.push({ t: o.t, ran, refused: Number(o.couldNotRun) || 0, seconds, perWalk, total: Number(o.total) || 0 });
  }
  return out;
}

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  if (!s.length) return 0;
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

// The median and not the mean: one sweep that ran while the machine was busy
// came in at 16.3s a walk against a usual 11.4, and a mean lets a single outlier
// like that move the number everything else is written against.
export function perWalkSeconds(repo = REPO) {
  const runs = sweepRuns(repo).slice(-10);
  if (!runs.length) return { seconds: FALLBACK_PER_WALK, runs: 0, measured: false };
  return { seconds: median(runs.map((r) => r.perWalk)), runs: runs.length, measured: true };
}

// What share of the set runs with the Mac's screen locked, measured rather than
// guessed: the walks that never look a control up by name do run, and the last
// recorded partial sweep says how many that was.
export function lockSafeShare(repo = REPO) {
  const partial = sweepRuns(repo).filter((r) => r.refused > 0 && r.total > 0).slice(-1)[0];
  if (!partial) return 0.5;
  return partial.ran / partial.total;
}

const round = (n, to) => Math.round(n / to) * to;

export function sweepSize(repo = REPO) {
  const walks = walkCount(repo);
  const per = perWalkSeconds(repo);
  const fullSeconds = walks * per.seconds;
  // A locked run is not simply a fraction of a full one: the walks it refuses
  // still cost their refusal, and the loop's live note quotes this number.
  const share = lockSafeShare(repo);
  const partialSeconds = walks * share * per.seconds + walks * (1 - share) * REFUSAL_SECONDS;
  const capSeconds = capSecondsFor(walks, per.seconds);
  return {
    walks,
    perWalkSeconds: +per.seconds.toFixed(2),
    perWalkFrom: per.measured ? `the median of the last ${per.runs} recorded sweeps` : 'the September 2026 median (no sweep recorded yet)',
    fullMinutes: Math.round(fullSeconds / 60),
    partialMinutes: Math.round(partialSeconds / 60),
    lockSafeShare: +share.toFixed(2),
    budgetSecondsPerWalk: budgetSecondsFor(per.seconds),
    capSeconds,
    capMinutes: Math.round(capSeconds / 60),
    // The sweep against the 600s ceiling on a task runner's background work,
    // which is the whole reason a runner may not start one.
    ceilingMultiple: Math.round(fullSeconds / 600),
    // What the prose says. Rounded, because these sentences are read by people
    // and "about 530" is a truer thing to write than a number that is wrong the
    // next morning.
    saidWalks: round(walks, 10),
    saidMinutes: round(fullSeconds / 60, 5),
  };
}

// The wall-clock stop, in seconds, for a set of this size.
//
// The arithmetic, with today's numbers (532 walks, 11.4s each, measured above):
//
//   a good full sweep   532 x 11.4s  = 101 minutes
//   the budget here     532 x 20s    = 177 minutes
//   headroom                          76 per cent
//   a wedged probe      532 x 180s   = 26 hours, caught 59 walks in
//
// 20s a walk is 75 per cent above the usual 11.4 and 23 per cent above the
// slowest real sweep ever recorded (16.3s a walk, 2026-09-18 03:26), so a slow
// machine does not trip it, and it is nine times under the 180s each walk is
// allowed on its own, so a probe that launches and never drives is still
// stopped in the first tenth of the run rather than holding the loop overnight.
//
// This used to be a flat two hours, set when a sweep was 52 minutes. By
// 2026-09-19 the set had grown to 532 walks and a full sweep to 101 minutes, so
// the net had closed to 17 minutes of slack and the first unlocked full sweep
// would have been cut off part way through and recorded as a run that did not
// finish. Deriving it means the same thing cannot happen at 800 walks.
export function capSecondsFor(walks, perWalk = 0) {
  return Math.max(120 * 60, Math.ceil(walks * budgetSecondsFor(perWalk)));
}

// How long to hold the Mac awake for a run of this size. It has to outlast the
// cap, not the sweep: caffeinate's -t expiring part way through lets the screen
// idle into a lock, and from that moment every remaining walk that looks a
// control up by name is refused. It was a flat two hours, which a 101-minute
// sweep was already within twenty minutes of.
export function awakeSecondsFor(walks, perWalk = 0) {
  return capSecondsFor(walks, perWalk) + 600;
}

// ---------------------------------------------------------------- quoting ----
// The one sentence every place says, so that they cannot disagree with each
// other even in principle, and so one regex can find and fix all of them.
export const SIZE_RE = /about \d+ walks and about \d+ minutes/g;
export const MULT_RE = /\b(?:[a-z]+|\d+) times the 600s ceiling\b/g;

export const sizePhrase = (s) => `about ${s.saidWalks} walks and about ${s.saidMinutes} minutes`;

const WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
  'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty'];
export const multPhrase = (s) => `${WORDS[s.ceilingMultiple] || s.ceilingMultiple} times the 600s ceiling`;

// The number a multiple sentence says, whether written as a word or digits.
export function multValue(phrase) {
  const said = phrase.split(' ')[0];
  if (/^\d+$/.test(said)) return Number(said);
  const i = WORDS.indexOf(said);
  return i < 0 ? null : i;
}

// Every file that tells a person how big the sweep is. A file listed here and
// missing the sentence FAILS the check: deleting the sentence would otherwise
// be a silent way to switch the check off for that file.
//
// Nothing under Scripts/ quotes it any more (2026-11-10). Scripts/ is code to
// the walk schedule (sweep-schedule.mjs WALK_PATHS), so every resync commit
// that touched Scripts/playtest-all.sh counted as code landing and asked for a
// walk check; that script now asks this file for the phrase when it prints it.
export const QUOTERS = [
  'CLAUDE.md',
  'docs/design/playtest-harness.md',
  'docs/design/tutorials.md',
  'queue/README.md',
  'queue/sweep/README.md',
  'queue/bin/go-loop.sh',
  'queue/bin/queue-lib.mjs',
  'queue/bin/runner-prompt.md',
  'queue/bin/sweep.sh',
];

// How far the written number may drift from the truth before it is wrong.
//
// Not zero. Walks arrive at about five a day, and a check that goes red every
// morning is a check people learn to ignore; "about 530" is not a lie at 537.
// It is wrong when a reader would draw a different conclusion from it, so the
// band is wide enough to cover a fortnight of growth and no wider.
export const TOLERANCE = { walksPercent: 10, minutesPercent: 15 };

// Where the loop brings the quotes back into line: HALF the CI band. The loop
// runs --sync after every task, before it pushes, so what is committed never
// sits more than this far off; a runner's push then has the other half of the
// band to itself before CI goes red. At 1140 walks that is 57 walks in one
// task, against about five a day. The minutes move only when a sweep lands in
// queue/history.jsonl, and the loop commits that record and syncs in the same
// push. The drill proves both (sweep-size-drill.mjs, "the margin").
//
// Until 2026-11-10 the loop resynced only once CI was ALREADY red, so the push
// that crossed the band failed by construction.
export const RESYNC = { walksPercent: TOLERANCE.walksPercent / 2, minutesPercent: TOLERANCE.minutesPercent / 2 };

const off = (said, real) => (real ? Math.abs(said - real) / real * 100 : 0);

// The text of a quoting file as the working tree has it, or as a commit has it
// (null when the file is not there). The loop's check reads HEAD: from
// 2026-11-06 the tree held an in-band rewrite the loop had failed to commit,
// so a check of the tree passed while main stayed red for four days.
const fromTree = (repo) => (rel) => {
  const file = join(repo, rel);
  return existsSync(file) ? readFileSync(file, 'utf8') : null;
};
export const fromCommit = (repo, rev = 'HEAD') => (rel) => {
  try {
    return execFileSync('git', ['show', `${rev}:${rel}`], { cwd: repo, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch { return null; }
};

export function checkQuotes(repo = REPO, { read = fromTree(repo), tolerance = TOLERANCE } = {}) {
  const size = sweepSize(repo);
  const want = sizePhrase(size);
  const wantMult = multPhrase(size);
  const problems = [];
  for (const rel of QUOTERS) {
    const text = read(rel);
    if (text === null) { problems.push({ file: rel, line: 0, why: 'the file is gone, so nothing there says how big the sweep is' }); continue; }
    const lines = text.split('\n');
    let found = 0;
    lines.forEach((text, i) => {
      for (const m of text.matchAll(SIZE_RE)) {
        found++;
        const [, w, mins] = m[0].match(/about (\d+) walks and about (\d+) minutes/);
        const walksOff = off(Number(w), size.walks);
        const minsOff = off(Number(mins), size.fullMinutes);
        if (walksOff > tolerance.walksPercent || minsOff > tolerance.minutesPercent) {
          problems.push({
            file: rel, line: i + 1, said: m[0], want,
            why: `it says ${m[0]}; the set is ${size.walks} walks and a full sweep is about ${size.fullMinutes} minutes`,
          });
        }
      }
      for (const m of text.matchAll(MULT_RE)) {
        // Held to the same band as the minutes it is worked out from. It was
        // an exact match until 2026-10-13, and a whole number of 600s ceilings
        // ticks over every few hours of walk growth: 21 became 22 four hours
        // after the docs were last brought into line, and CI stayed red from
        // then on, which also meant the tests behind this step never ran.
        const saidMult = multValue(m[0]);
        if (saidMult === null || off(saidMult, size.ceilingMultiple) > tolerance.minutesPercent) {
          problems.push({ file: rel, line: i + 1, said: m[0], want: wantMult, why: `it says "${m[0]}"; a full sweep is ${wantMult}` });
        }
      }
    });
    if (!found) problems.push({ file: rel, line: 0, want, why: `nothing in it says how big the sweep is. It is listed here because it tells someone that; put "${want}" back or take the file off QUOTERS in queue/bin/sweep-size.mjs` });
  }
  return { size, problems };
}

export function writeQuotes(repo = REPO) {
  const size = sweepSize(repo);
  const want = sizePhrase(size);
  const wantMult = multPhrase(size);
  const changed = [];
  for (const rel of QUOTERS) {
    const file = join(repo, rel);
    if (!existsSync(file)) continue;
    const before = readFileSync(file, 'utf8');
    const after = before.replace(SIZE_RE, want).replace(MULT_RE, wantMult);
    if (after !== before) { writeFileSync(file, after); changed.push(rel); }
  }
  return { size, changed };
}

// The quote sentences blanked out, so two versions of a file can be compared
// for everything EXCEPT the number.
const unquoted = (text) => text.replace(SIZE_RE, '<size>').replace(MULT_RE, '<mult>');

// What the loop runs after every task (go-loop.sh keep_sweep_size_true).
//
// Reads what is COMMITTED, and when it has drifted past RESYNC (or is missing)
// rewrites the quoting files and commits them, by argv, so no shell gets to
// split or not split the list. The loop used to do the commit itself as
// `git commit -- $files` in zsh, which does not word-split: git got one
// pathspec of eleven lines and refused it ("error: pathspec 'CLAUDE.md...",
// queue/loop.log), twice, and left the rewrite sitting in the tree.
//
// A quoting file whose uncommitted edits are more than a quote is somebody's
// work and is left alone; one whose only change IS a quote (the stranded
// rewrite above) is the loop's own and is taken.
export function syncQuotes(repo = REPO, { commit = true } = {}) {
  const head = fromCommit(repo);
  const tree = fromTree(repo);
  const { size, problems } = checkQuotes(repo, { read: head, tolerance: RESYNC });
  const want = sizePhrase(size);
  if (!problems.length) return { size, due: false, changed: [], held: [], committed: false };
  const held = [];
  const changed = [];
  for (const rel of QUOTERS) {
    const now = tree(rel);
    if (now === null) continue;
    const before = head(rel);
    if (before !== null && now !== before && unquoted(now) !== unquoted(before)) { held.push(rel); continue; }
    const after = now.replace(SIZE_RE, want).replace(MULT_RE, multPhrase(size));
    if (after !== now) writeFileSync(join(repo, rel), after);
    if (before === null || after !== before) changed.push(rel);
  }
  let committed = false;
  let error = '';
  if (commit && changed.length) {
    try {
      execFileSync('git', ['commit', '-q', '-m', `The sweep's size is quoted as it really is: ${want}`, '--', ...changed],
        { cwd: repo, stdio: ['ignore', 'pipe', 'pipe'] });
      committed = true;
    } catch (e) { error = String((e.stderr && e.stderr.toString()) || e.message).trim(); }
  }
  return { size, due: true, changed, held, committed, error, problems };
}

// ------------------------------------------------------------------- cli ----
if (process.argv[1] && process.argv[1].endsWith('sweep-size.mjs')) {
  const arg = process.argv[2] || '';
  const size = sweepSize();
  if (arg === '--json') {
    console.log(JSON.stringify(size, null, 2));
  } else if (arg === '--walks') {
    console.log(size.walks);
  } else if (arg === '--minutes') {
    console.log(size.fullMinutes);
  } else if (arg === '--partial-minutes') {
    console.log(size.partialMinutes);
  } else if (arg === '--cap-seconds') {
    console.log(size.capSeconds);
  } else if (arg === '--awake-seconds') {
    console.log(awakeSecondsFor(size.walks, size.perWalkSeconds));
  } else if (arg === '--phrase') {
    console.log(sizePhrase(size));
  } else if (arg === '--check') {
    const { problems } = checkQuotes();
    if (!problems.length) {
      console.log(`==> Every place that quotes the sweep's size agrees: ${sizePhrase(size)}.`);
      process.exit(0);
    }
    console.error(`!! ${problems.length} place(s) quote the walk sweep's size wrongly. The truth, from`);
    console.error(`   Scripts/playtest/*.json and queue/history.jsonl: ${sizePhrase(size)}.`);
    for (const p of problems) console.error(`   ${p.file}${p.line ? `:${p.line}` : ''}  ${p.why}`);
    console.error(`   Fix all of them with: queue/bin/sweep-size.mjs --write`);
    process.exit(1);
  } else if (arg === '--sync') {
    const r = syncQuotes();
    if (!r.due) {
      console.log(`==> What is committed quotes the sweep's size within half the CI band: ${sizePhrase(size)}.`);
    } else {
      if (r.committed) console.log(`==> Committed ${r.changed.length} file(s) quoting "${sizePhrase(size)}": ${r.changed.join(', ')}`);
      if (r.error) console.error(`!! Could not commit the sweep's size: ${r.error}`);
      if (r.held.length) console.error(`!! Left alone, they carry somebody's uncommitted edits: ${r.held.join(', ')}. CI goes red once these drift past the band.`);
    }
    process.exit(r.error || (r.due && !r.committed && r.held.length) ? 1 : 0);
  } else if (arg === '--write') {
    const { changed } = writeQuotes();
    console.log(changed.length
      ? `==> Rewrote ${changed.length} file(s) to "${sizePhrase(size)}": ${changed.join(', ')}`
      : `==> Nothing to rewrite; every place already says "${sizePhrase(size)}".`);
  } else {
    const runs = sweepRuns().slice(-10);
    console.log(`The walk sweep, as it actually is today`);
    console.log(``);
    console.log(`  walks in the set     ${size.walks}   (ls Scripts/playtest/*.json)`);
    console.log(`  seconds a walk       ${size.perWalkSeconds}   (${size.perWalkFrom})`);
    console.log(`  a full sweep         ${size.fullMinutes} minutes   = ${size.walks} x ${size.perWalkSeconds}s`);
    console.log(`  with the screen locked  ${size.partialMinutes} minutes   (${Math.round(size.lockSafeShare * 100)}% of the set runs)`);
    console.log(`  against a runner's 600s ceiling   ${multPhrase(size)}`);
    console.log(``);
    console.log(`  the wall-clock stop  ${size.capMinutes} minutes   = ${size.walks} x ${size.budgetSecondsPerWalk}s budget (${BUDGET_HEADROOM} x a walk, ${BUDGET_SECONDS_PER_WALK} to ${BUDGET_CEILING_SECONDS}s)`);
    console.log(`  headroom over a good sweep   ${Math.round((size.capSeconds / (size.walks * size.perWalkSeconds) - 1) * 100)}%`);
    console.log(`  a wedged probe (180s a walk) is stopped after ${Math.round(size.capSeconds / 180)} walks`);
    console.log(``);
    console.log(`  what the docs say    "${sizePhrase(size)}"`);
    console.log(``);
    console.log(`  the sweeps it was measured from:`);
    for (const r of runs) console.log(`    ${r.t.slice(0, 16)}  ${r.ran} walks + ${r.refused} refused in ${r.seconds}s  ->  ${r.perWalk.toFixed(1)}s a walk`);
  }
}
