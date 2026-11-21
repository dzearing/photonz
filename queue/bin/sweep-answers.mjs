#!/usr/bin/env node
// When each walk last had an answer from a whole-set run, kept apart from the
// record of the last run.
//
// queue/sweep/latest.json is the last whole-set run, and a new run that starts
// from walk one replaces it. So once a run is stopped, the walks it never
// reached have no answer in it, however recently the run before answered them,
// and nothing could say how long the set had gone unanswered. From 2026-11-04
// to 11-20 the whole set did not finish once (six runs, each stopped when the
// user came back), and the only way to see it was to read history.jsonl by
// hand. The user asked for one sentence that says it.
//
// queue/sweep/answers.json:
//   { "updated": ISO, "walks": { "<walk>": { "t": ISO, "ok": true|false } } }
// `t` is when the part of the run that answered the walk began. Only whole-set
// runs write it (sweep-record.mjs), parts and blind runs included, because an
// answer is an answer however the run ended. A rotating check does not: the
// set's promise is about whole-set runs, and the rotating check says its own
// numbers apart.
//
//   node queue/bin/sweep-answers.mjs              the sentence sweep.sh status prints
//   node queue/bin/sweep-answers.mjs --json       the same, for the dashboard
//   node queue/bin/sweep-answers.mjs --backfill   seed it from the run logs still on disk
//
// Drill: queue/bin/sweep-resume-drill.mjs
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const HOUR = 3600 * 1000;

// Fold one run's answers in. Never moves a walk's answer back in time, so a
// run replayed out of order cannot make the set look less recently answered.
export function noteAnswers(ledger, { ranWalks = [], failed = [], at = null } = {}) {
  const out = {
    updated: ledger && ledger.updated ? ledger.updated : null,
    // The first run the ledger has heard of: a walk with no answer in it has
    // gone at least this long without one.
    since: ledger && ledger.since ? ledger.since : null,
    walks: { ...((ledger && ledger.walks) || {}) },
  };
  const t = Date.parse(at);
  if (!Number.isFinite(t)) return out;
  if (!out.since || t < Date.parse(out.since)) out.since = new Date(t).toISOString();
  const bad = new Set(failed || []);
  for (const w of ranWalks || []) {
    const was = out.walks[w];
    if (was && Date.parse(was.t) > t) continue;
    out.walks[w] = { t: new Date(t).toISOString(), ok: !bad.has(w) };
  }
  out.updated = new Date().toISOString();
  return out;
}

// How long the set has gone without an answer, against the set as it is now.
export function answerAges(ledger, set = [], now = Date.now()) {
  const walks = (ledger && ledger.walks) || {};
  const never = [];
  let oldest = null;
  let oldestWalk = null;
  for (const w of set) {
    const t = walks[w] ? Date.parse(walks[w].t) : NaN;
    if (!Number.isFinite(t)) { never.push(w); continue; }
    if (oldest === null || t < oldest) { oldest = t; oldestWalk = w; }
  }
  const since = ledger && ledger.since ? ledger.since : null;
  return {
    of: set.length,
    unanswered: never.length,
    unansweredWalks: never,
    // Walks with no answer on record at all have gone at least as long as the
    // ledger has been kept.
    oldestAt: oldest === null ? null : new Date(oldest).toISOString(),
    oldestWalk,
    oldestHours: oldest === null ? null : (now - oldest) / HOUR,
    since,
  };
}

const days = (h) => (h >= 48 ? `${Math.floor(h / 24)} days` : h >= 24 ? '1 day' : `${Math.max(1, Math.round(h))} hours`);

// The sentence. Says the worst of it: how long the walk answered longest ago
// has gone, and how many have no answer on record at all.
export function answerSentence(a, windowHours = 72) {
  if (!a || !a.of) return 'No walks in the set.';
  if (a.oldestAt === null) {
    return `None of the ${a.of} walks has an answer from a whole-set run on record${a.since ? ` since ${a.since.slice(0, 10)}` : ''}.`;
  }
  const old = a.oldestHours;
  const within = `every walk in the set has had an answer from a whole-set run in the last ${days(old)}`;
  if (!a.unanswered) {
    return old <= windowHours
      ? `Inside the ${windowHours} hour window: ${within}.`
      : `OUTSIDE the ${windowHours} hour window: ${within.replace('every walk', 'the walk answered longest ago')}; `
        + `${a.oldestWalk} was last answered ${a.oldestAt.slice(0, 16).replace('T', ' ')}Z.`;
  }
  return `OUTSIDE the ${windowHours} hour window: ${a.unanswered} of ${a.of} walks have no answer from a whole-set run on record`
    + `${a.since ? ` since ${a.since.slice(0, 10)}` : ''}, and of the rest the oldest answer is ${days(old)} old.`;
}

// ---- reading the disk ---------------------------------------------------------
const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const readJSON = (f) => { try { return JSON.parse(readFileSync(f, 'utf8')); } catch { return null; } };

export function ledgerFile(sweepDir) { return join(sweepDir, 'answers.json'); }

export function readLedger(sweepDir) {
  return readJSON(ledgerFile(sweepDir)) || { updated: null, walks: {} };
}

// Write one recorded run (or one part of it) into the ledger beside latest.json.
export function recordAnswers(sweepDir, run) {
  const next = noteAnswers(readLedger(sweepDir), run);
  writeFileSync(ledgerFile(sweepDir), JSON.stringify(next, null, 2) + '\n');
  return next;
}

const isMain = process.argv[1] && process.argv[1].endsWith('sweep-answers.mjs');
if (isMain) {
  const argv = process.argv.slice(2);
  const dir = join(process.env.PHOTONZ_QUEUE_DIR || join(REPO, 'queue'), 'sweep');
  const { walkNames, DEFAULTS } = await import('./sweep-schedule.mjs');
  const windowHours = Number(process.env.PHOTONZ_SWEEP_FLOOR_HOURS || DEFAULTS.floorHours);

  if (argv.includes('--backfill')) {
    // The whole-set run logs still on disk (sweep.sh keeps the last ten logs of
    // any kind), oldest first. A log is named for the local time its run began.
    const { parseSweepLog } = await import('./sweep-parse.mjs');
    const logs = existsSync(dir) ? readdirSync(dir).filter((f) => /^\d{4}-\d{2}-\d{2}-\d{6}\.log$/.test(f)).sort() : [];
    let ledger = readLedger(dir);
    for (const f of logs) {
      const m = basename(f, '.log').match(/^(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})$/);
      const at = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).toISOString();
      const r = parseSweepLog(readFileSync(join(dir, f), 'utf8'), { interrupted: true });
      ledger = noteAnswers(ledger, { ranWalks: r.ranWalks, failed: r.failed, at });
      console.log(`  ${f}: ${r.ranWalks.length} walks answered, from ${at}`);
    }
    writeFileSync(ledgerFile(dir), JSON.stringify(ledger, null, 2) + '\n');
    console.log(`==> ${Object.keys(ledger.walks).length} walks in ${ledgerFile(dir)}`);
    process.exit(0);
  }

  const a = answerAges(readLedger(dir), walkNames(), Date.now());
  if (argv.includes('--json')) {
    const { unansweredWalks, ...rest } = a;
    console.log(JSON.stringify({ ...rest, windowHours, sentence: answerSentence(a, windowHours) }));
  } else {
    console.log(answerSentence(a, windowHours));
  }
}
