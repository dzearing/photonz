// How one reading of a set is taken and how steady it is (README, "How
// steady a reading is"). Pure, so `reading.test.mjs` checks it.
//
// Ask makes a different thing from the same request run to run (2026-11-15:
// one case of the climb set read 33.9 and then 76 on the same code), so one
// run of a case is one draw. A reading can run every case more than once, in
// rounds (the whole set, then the whole set again), and is the mean of each
// case's own mean. How far each case moved between its own rounds says how far
// the whole reading could move by chance: its standard error. That is a total,
// so a sealed reading prints it without showing any case.

/// The sealed motion set is read in two rounds (32 runs, about 100 minutes);
/// every other set in one, unless `--repeat N` says otherwise.
export function roundsFor(set, asked) {
  const rounds = asked ?? (set === "held-out-motion" ? 2 : 1);
  if (!Number.isInteger(rounds) || rounds < 1) throw new Error(`--repeat takes a whole number of rounds, 1 or more, not ${asked}`);
  return rounds;
}

/// Every run a reading makes, round by round: the first round keeps the case's
/// own id (so a one-round reading looks as it always did), later rounds add ~2, ~3.
export function slots(caseIDs, rounds) {
  const out = [];
  for (let round = 1; round <= rounds; round += 1) {
    for (const id of caseIDs) out.push({ key: round === 1 ? id : `${id}~${round}`, id, round });
  }
  return out;
}

export const baseID = (key) => key.replace(/~\d+$/, "");

const round1 = (v) => Math.round(v * 10) / 10;
const mean = (list) => list.reduce((s, v) => s + v, 0) / list.length;

/// Each case's runs: { id: { group, scores (unrun as 0), ran (scores of runs that ran) } }.
function byCase(cases) {
  const out = {};
  for (const [key, r] of Object.entries(cases)) {
    const c = (out[baseID(key)] ??= { group: r.group, scores: [], ran: [] });
    c.scores.push(r.score ?? 0);
    if (!r.unrun) c.ran.push(r.score ?? 0);
  }
  return out;
}

/// The reading: the mean over cases of each case's mean. A run not made yet
/// counts 0, as a case not run always has, so an unfinished reading reads low.
export function readingTotal(cases) {
  const each = Object.values(byCase(cases));
  return each.length ? round1(mean(each.map((c) => mean(c.scores)))) : null;
}

export function groupTotals(cases) {
  const groups = {};
  for (const c of Object.values(byCase(cases))) (groups[c.group] ??= []).push(mean(c.scores));
  return Object.fromEntries(Object.entries(groups).map(([g, v]) => [g, round1(mean(v))]));
}

/// How far the reading could move by chance. The spread of one run of a case
/// (`perRun`, a standard deviation in points) is pooled over every case run in
/// two rounds or more; the reading's standard error is that spread over the
/// square root of its runs, per case. Null when no case has run twice.
export function spread(cases) {
  const each = Object.values(byCase(cases)).filter((c) => c.ran.length > 0);
  const repeated = each.filter((c) => c.ran.length >= 2);
  if (!repeated.length) return null;
  const variance = mean(repeated.map((c) => {
    const m = mean(c.ran);
    return c.ran.reduce((s, v) => s + (v - m) ** 2, 0) / (c.ran.length - 1);
  }));
  const standardError = Math.sqrt(variance * each.reduce((s, c) => s + 1 / c.ran.length, 0)) / each.length;
  return { standardError: round1(standardError), perRun: round1(Math.sqrt(variance)), casesWithRounds: repeated.length };
}

/// The spread of one run of a case, pooled over every reading of the same set
/// on the same rubric that ran cases twice (each weighed by how many cases it
/// ran twice). One reading's own figure is a draw too: on 2026-11-15 two
/// readings of the same code measured 5.7 and 4.0. Null when none has one.
export function pooledSpread(readings, { set, rubric }) {
  const mine = readings.filter((h) => (h.set ?? "climb") === set && h.rubric === rubric && h.spread?.perRun !== undefined);
  if (!mine.length) return null;
  const weight = mine.reduce((s, h) => s + h.spread.casesWithRounds, 0);
  const variance = mine.reduce((s, h) => s + h.spread.perRun ** 2 * h.spread.casesWithRounds, 0) / weight;
  return { perRun: round1(Math.sqrt(variance)), readings: mine.length };
}

/// Whether two readings of the same set differ by more than chance: the
/// difference, its standard error, and `real` past twice that. With a pooled
/// spread (`pooledSpread`) both readings' errors come from it at their own
/// number of runs; without one, a reading with no spread of its own (one
/// round) borrows the other's. Null when there is nothing to go on.
export function chance(a, b, pooled = null) {
  const per = pooled?.perRun ?? a.spread?.perRun ?? b.spread?.perRun;
  if (per === undefined) return null;
  const atRuns = (r) => per / Math.sqrt((r.caseCount ?? 1) * (r.rounds ?? 1));
  const errorOf = (r) => (pooled ? atRuns(r) : r.spread?.standardError ?? atRuns(r));
  const se = Math.sqrt(errorOf(a) ** 2 + errorOf(b) ** 2);
  const difference = round1(a.total - b.total);
  return { difference, standardError: round1(se), real: Math.abs(a.total - b.total) > 2 * se };
}

/// Several finished readings of the same code on the same set, read as one:
/// the mean of their totals weighed by their rounds, and every round counted
/// (`compare <run> --with a,b`). A baseline read twice in two rounds is a
/// reading of four rounds, so a pass is measured against a steadier bar.
export function pooledReading(readings) {
  const [first] = readings;
  const same = (h) => h.engine === first.engine && (h.set ?? "climb") === (first.set ?? "climb") && h.rubric === first.rubric && h.caseCount === first.caseCount;
  if (!readings.every(same)) throw new Error("only readings of the same set, engine, rubric and cases can be read as one");
  const rounds = readings.reduce((s, h) => s + (h.rounds ?? 1), 0);
  const total = round1(readings.reduce((s, h) => s + h.total * (h.rounds ?? 1), 0) / rounds);
  return {
    run: readings.map((h) => h.run).join("+"), engine: first.engine, set: first.set, rubric: first.rubric, caseCount: first.caseCount,
    total, rounds, tag: `${readings.length} readings as one: ${readings.map((h) => h.tag).join("; ")}`, lookups: first.lookups,
  };
}
