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
//
// --check runs in CI (.github/workflows/ci.yml), which is what stops the next
// hundred walks making the docs wrong in silence again.
//
// Drill: queue/bin/sweep-size-drill.mjs
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// A walk a locked screen turned away prints its line in about this long: it is
// refused before the app is even asked to do anything. Measured across the
// 2026-09-19 sweeps, where 270 refusals came to 242 seconds.
const REFUSAL_SECONDS = 0.9;

// The seconds a sweep is ALLOWED per walk before it is stopped. Not the
// measured cost and deliberately not derived from it: this is the safety net,
// and a net whose size follows the thing it is catching is no net. See
// capMinutes() for why this number.
export const BUDGET_SECONDS_PER_WALK = 20;

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
  const capSeconds = capSecondsFor(walks);
  return {
    walks,
    perWalkSeconds: +per.seconds.toFixed(2),
    perWalkFrom: per.measured ? `the median of the last ${per.runs} recorded sweeps` : 'the September 2026 median (no sweep recorded yet)',
    fullMinutes: Math.round(fullSeconds / 60),
    partialMinutes: Math.round(partialSeconds / 60),
    lockSafeShare: +share.toFixed(2),
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
export function capSecondsFor(walks) {
  return Math.max(120 * 60, Math.ceil(walks * BUDGET_SECONDS_PER_WALK));
}

// How long to hold the Mac awake for a run of this size. It has to outlast the
// cap, not the sweep: caffeinate's -t expiring part way through lets the screen
// idle into a lock, and from that moment every remaining walk that looks a
// control up by name is refused. It was a flat two hours, which a 101-minute
// sweep was already within twenty minutes of.
export function awakeSecondsFor(walks) {
  return capSecondsFor(walks) + 600;
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

// Every file that tells a person how big the sweep is. A file listed here and
// missing the sentence FAILS the check: deleting the sentence would otherwise
// be a silent way to switch the check off for that file.
export const QUOTERS = [
  'CLAUDE.md',
  'docs/design/playtest-harness.md',
  'docs/design/tutorials.md',
  'Scripts/playtest-all.sh',
  'Scripts/playtest/studies/README.md',
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

const off = (said, real) => (real ? Math.abs(said - real) / real * 100 : 0);

export function checkQuotes(repo = REPO) {
  const size = sweepSize(repo);
  const want = sizePhrase(size);
  const wantMult = multPhrase(size);
  const problems = [];
  for (const rel of QUOTERS) {
    const file = join(repo, rel);
    if (!existsSync(file)) { problems.push({ file: rel, line: 0, why: 'the file is gone, so nothing there says how big the sweep is' }); continue; }
    const lines = readFileSync(file, 'utf8').split('\n');
    let found = 0;
    lines.forEach((text, i) => {
      for (const m of text.matchAll(SIZE_RE)) {
        found++;
        const [, w, mins] = m[0].match(/about (\d+) walks and about (\d+) minutes/);
        const walksOff = off(Number(w), size.walks);
        const minsOff = off(Number(mins), size.fullMinutes);
        if (walksOff > TOLERANCE.walksPercent || minsOff > TOLERANCE.minutesPercent) {
          problems.push({
            file: rel, line: i + 1, said: m[0], want,
            why: `it says ${m[0]}; the set is ${size.walks} walks and a full sweep is about ${size.fullMinutes} minutes`,
          });
        }
      }
      for (const m of text.matchAll(MULT_RE)) {
        if (m[0] !== wantMult) {
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
    console.log(awakeSecondsFor(size.walks));
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
    console.log(`  the wall-clock stop  ${size.capMinutes} minutes   = ${size.walks} x ${BUDGET_SECONDS_PER_WALK}s budget`);
    console.log(`  headroom over a good sweep   ${Math.round((size.capSeconds / (size.walks * size.perWalkSeconds) - 1) * 100)}%`);
    console.log(`  a wedged probe (180s a walk) is stopped after ${Math.round(size.capSeconds / 180)} walks`);
    console.log(``);
    console.log(`  what the docs say    "${sizePhrase(size)}"`);
    console.log(``);
    console.log(`  the sweeps it was measured from:`);
    for (const r of runs) console.log(`    ${r.t.slice(0, 16)}  ${r.ran} walks + ${r.refused} refused in ${r.seconds}s  ->  ${r.perWalk.toFixed(1)}s a walk`);
  }
}
