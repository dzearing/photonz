#!/usr/bin/env node
// The scored test set for what Ask and the Photonz skill make
// (Scripts/ask-eval/README.md). Run it through Scripts/ask-eval.sh.
//
//   run --engine ask|skill --tag "<what changed>" [--set climb|held-out] [--cases a,b]
//       [--resume <run>] [--minutes N] [--no-build] [--judge-runs 9] [--on <switch>,<switch>]
//       [--repeat N]                      run every case N times, round by round (held-out-motion: 2)
//       [--models <id>,<id>]              the probe has only these built-in models, and no picture model
//       [--mac 16]                        Ask plans as a Mac of this size would: its window and what it holds
//   compare [<run>] [--with <run>[,<run>]|best]  a run against the best so far (or readings read as one), case by case
//   report [--engine ask]                   the latest climb and held-out totals side by side
//   lines <run> [--with <run>]              a run's judge lines in total (drawings, all cases), held-out runs too
//   time <run> [<run> ...]                  per group: cases, how many ran out of time or stopped, median seconds and steps, held-out runs too
//   history                                 every finished run, newest last
//   calibrate                               the judge against the user's own verdicts
//   feedback                                take the thumbs down saved in the apps into the held-out set
//   sheet <run>                             (re)draw a run's contact sheet
//   rescore <run>                           re-run the rules and judge on saved results
import { appendFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import os from "node:os";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { score as ruleScore } from "./rules.mjs";
import { judgePicture, nameBlind, JUDGE_MODEL, JUDGE_LOOKS, RUBRIC_ID, run } from "./judge.mjs";
import { repo, runAsk, runSkill, quitProbe, SKILL_MODEL } from "./engines.mjs";
import { combine } from "./scoring.mjs";
import { tally, describe } from "./lookups.mjs";
import { iconSheet } from "./icon-sheet.mjs";
import { roundsFor, slots, baseID, readingTotal, groupTotals, spread, chance, pooledSpread, pooledReading } from "./reading.mjs";

const here = path.join(repo, "Scripts/ask-eval");
const runsDir = path.join(repo, ".ask-eval/runs");
/// Held-out runs live apart, and nothing here prints one of their cases.
const heldOutRunsDir = path.join(repo, ".ask-eval/held-out-runs");
// held-out-motion (2026-11-14): animated requests of everyday things written
// before the general motion techniques were tuned, sealed like held-out and run
// on its own, so a pass on motion is judged on a set nobody climbed.
const SETS = { climb: "cases", "held-out": "held-out", "held-out-motion": "held-out-motion" };
const isSealed = (set) => (set ?? "climb") !== "climb";
const runDirOf = (id, set) => path.join(isSealed(set) ? heldOutRunsDir : runsDir, id);
const findRunDir = (id) => [runsDir, heldOutRunsDir].map((d) => path.join(d, id)).find((d) => existsSync(path.join(d, "run.json")));
const historyFile = path.join(repo, "queue/evals/ask-eval-history.jsonl");

const argv = process.argv.slice(2);
const command = argv[0];
const option = (name, fallback) => { const at = argv.indexOf(`--${name}`); return at >= 0 ? argv[at + 1] : fallback; };
const flag = (name) => argv.includes(`--${name}`);
const positional = argv.slice(1).find((a, i, all) => !a.startsWith("--") && !(i > 0 && all[i - 1].startsWith("--") && !["--no-build"].includes(all[i - 1])));

/// The climb set (cases/) is the one a runner works on and reads case by case.
/// The held-out set (held-out/) is read only in total (README, "The
/// held-out set").
export function loadCases(set = "climb") {
  if (!SETS[set]) throw new Error(`--set ${Object.keys(SETS).join(", --set ")}, not ${set}`);
  const dir = path.join(here, SETS[set]);
  return readdirSync(dir).filter((f) => f.endsWith(".json")).sort().map((f) => ({ id: f.replace(/\.json$/, ""), ...JSON.parse(readFileSync(path.join(dir, f), "utf8")) }));
}

/// A reading's runs, round by round (`reading.mjs`); one round unless it says more.
const slotsOf = (meta) => slots(meta.caseIDs, meta.rounds ?? 1);
/// How far a reading could move by chance, as a line: "± 1.4 (two rounds)".
const plusMinus = (h) => h.spread ? ` ± ${h.spread.standardError}` : "";
const roundsWord = (n) => (n ?? 1) === 1 ? "one round" : `${n} rounds`;

async function scoreCase(testCase, dir, got, judgeRuns) {
  if (!got.read || !got.picture) return { rules: null, judge: null, named: null, score: 0 };
  const rules = ruleScore(got.read, testCase, got.engine);
  // An icon is judged on a sheet of it at the sizes it is used, beside references;
  // it is still named blind from the picture alone.
  const icon = testCase.group === "icon";
  const animated = testCase.group === "animated";
  const judged = icon && rules.score !== 0 ? await iconSheet(testCase, dir, got.picture) : got.picture;
  const [judge, named] = await Promise.all([
    rules.score === 0 ? null : judgePicture({ picture: judged, request: testCase.request, context: testCase.context, runs: judgeRuns, crafted: !!testCase.crafted, video: testCase.group === "video", photo: !!testCase.photo, icon, animated, story: !!testCase.story }),
    ["drawing", "photo", "icon"].includes(testCase.group) && rules.score !== 0 ? nameBlind({ picture: got.picture, names: testCase.names ?? [], runs: judgeRuns }) : null,
  ]);
  // A drawing that spells out what it is gets named from its words, not its
  // shapes (the user's dog had "Dog" over it), so that naming does not count.
  if (named) {
    const words = JSON.stringify(got.read.layers).match(/"string":"[^"]*"/g)?.join(" ") ?? "";
    if ((testCase.names ?? []).some((n) => new RegExp(`\\b${n}`, "i").test(words))) {
      Object.assign(named, { score: 0, right: 0, note: "the drawing spells out its own name, so naming it proves nothing" });
    }
  }
  return { rules, judge, named, score: combine(testCase, rules, judge, named) };
}

function commit() { try { return execFileSync("git", ["rev-parse", "--short", "HEAD"], { cwd: repo }).toString().trim(); } catch { return null; } }

function label(result) {
  const parts = [`rules ${result.rules?.score ?? "-"}`, `judge ${result.judge?.score ?? "-"}`];
  if (result.named) parts.push(`named ${result.named.right}/${result.named.of}`);
  if (result.seconds) parts.push(`${Math.round(result.seconds)}s`);
  return `${result.id}  ${result.score}\n${parts.join(" · ")}`;
}

async function drawSheet(runDir, meta) {
  const args = [path.join(runDir, "contact-sheet.png"), `${meta.engine} · ${meta.tag} · ${meta.id} · total ${meta.total ?? "-"}`];
  for (const [id, r] of Object.entries(meta.cases)) args.push(path.join(runDir, id, "result.png"), label({ id, ...r }));
  const made = await run("swift", [path.join(here, "contact-sheet.swift"), ...args], { cwd: repo, timeoutMS: 180_000 });
  if (made.code !== 0) console.error(`!! contact sheet: ${made.stderr.trim().split("\n").pop()}`);
  return path.join(runDir, "contact-sheet.png");
}

function saveMeta(runDir, meta) {
  meta.total = readingTotal(meta.cases);
  meta.groups = groupTotals(meta.cases);
  meta.spread = spread(meta.cases);
  meta.wallSeconds = Math.round(Object.values(meta.cases).reduce((s, r) => s + (r.caseSeconds ?? 0), 0));
  meta.lookups = tally(meta.cases);
  meta.model = modelStats(meta.cases);
  meta.lines = judgeLines(meta.cases);
  writeFileSync(path.join(runDir, "run.json"), JSON.stringify(meta, null, 2));
}

/// The engine's own figures across a run: seconds per request (median),
/// tool calls and how many came back broken, requests Ollama itself refused,
/// and the most memory the model held. Totals, so a held-out run has them too.
function modelStats(cases) {
  const ran = Object.values(cases).filter((r) => !r.unrun && r.engine);
  const seconds = ran.map((r) => r.engine.seconds).filter((s) => typeof s === "number").sort((a, b) => a - b);
  const median = seconds.length ? (seconds.length % 2 ? seconds[(seconds.length - 1) / 2] : (seconds[seconds.length / 2 - 1] + seconds[seconds.length / 2]) / 2) : null;
  const sum = (key) => ran.reduce((s, r) => s + (r.engine[key] ?? 0), 0);
  const memory = ran.map((r) => r.engine.modelGigabytes).filter((g) => typeof g === "number");
  return {
    medianSeconds: median === null ? null : Math.round(median * 10) / 10,
    calls: sum("calls"), brokenCalls: sum("brokenCalls"),
    refused: ran.filter((r) => r.engine.phase === "stopped" && /error|pars|unexpected|does not support/i.test(r.engine.says ?? "")).length,
    gigabytes: memory.length ? Math.max(...memory) : null,
  };
}

/// The judge's lines (clean, designed, didWhatWasAsked, crafted, ...) as
/// means over a run's drawing cases and over all its cases, with the median
/// seconds a drawing request took. Totals, so a held-out run has them too: two
/// ways of drawing are compared on didWhatWasAsked without reading a case.
export function judgeLines(cases) {
  const ran = Object.values(cases).filter((r) => !r.unrun);
  const means = (list) => {
    const out = {};
    for (const key of ["clean", "typography", "aligned", "flow", "designed", "didWhatWasAsked", "crafted", "photographic", "readsAsIcon", "loops"]) {
      const values = list.map((r) => r.judge?.lines?.[key]).filter((v) => typeof v === "number");
      if (values.length) out[key] = Math.round(values.reduce((a, b) => a + b, 0) / values.length * 10) / 10;
    }
    return out;
  };
  const drawings = ran.filter((r) => r.group === "drawing");
  const seconds = drawings.map((r) => r.seconds).filter((v) => typeof v === "number").sort((a, b) => a - b);
  return {
    drawing: means(drawings), icon: means(ran.filter((r) => r.group === "icon")),
    animated: means(ran.filter((r) => r.group === "animated")), all: means(ran),
    drawingSeconds: seconds.length ? seconds[Math.floor((seconds.length - 1) / 2)] : null,
  };
}

function historyLine(meta) {
  const line = {
    run: meta.id, engine: meta.engine, set: meta.set ?? "climb", tag: meta.tag, commit: meta.commit, started: meta.started, finished: new Date().toISOString(),
    ...(Object.keys(meta.switched ?? {}).length ? { switched: meta.switched } : {}),
    ...(meta.models?.length ? { models: meta.models } : {}), ...(meta.mac ? { mac: meta.mac } : {}),
    wallSeconds: meta.wallSeconds, rubric: RUBRIC_ID, looks: meta.looks ?? null, judgeModel: JUDGE_MODEL, engineModel: meta.engineModel,
    total: meta.total, rounds: meta.rounds ?? 1, ...(meta.spread ? { spread: meta.spread } : {}),
    groups: meta.groups, lookups: meta.lookups, model: meta.model, caseCount: new Set(Object.keys(meta.cases).map(baseID)).size,
    lines: meta.lines ?? judgeLines(meta.cases), time: timeByGroup(meta.cases),
  };
  // A held-out run is recorded in total only, so no case can be climbed on.
  if (isSealed(meta.set)) return line;
  // A case run in more than one round is one entry: its mean, and each round's score.
  const cases = {};
  for (const [key, r] of Object.entries(meta.cases)) {
    const one = {
      score: r.score, rules: r.rules?.score ?? null, judge: r.judge?.score ?? null, named: r.named ? `${r.named.right}/${r.named.of}` : undefined,
      seconds: r.seconds, unrun: r.unrun, sources: r.sources,
    };
    const id = baseID(key);
    if (!cases[id]) { cases[id] = one; continue; }
    const rounds = cases[id].rounds ?? [cases[id].score];
    rounds.push(r.score);
    cases[id] = { ...cases[id], score: Math.round(rounds.reduce((s, v) => s + v, 0) / rounds.length * 10) / 10, rounds };
  }
  return { ...line, cases };
}

async function commandRun() {
  const engine = option("engine");
  if (!["ask", "skill"].includes(engine)) throw new Error("--engine ask or --engine skill");
  const resume = option("resume");
  const set = resume ? JSON.parse(readFileSync(path.join(findRunDir(resume) ?? runDirOf(resume, "climb"), "run.json"), "utf8")).set ?? "climb" : option("set", "climb");
  const sealed = isSealed(set);
  if (set === "held-out" && !resume) importFeedback({ quiet: true });
  const all = loadCases(set);
  const wanted = option("cases")?.split(",");
  if (sealed && wanted) throw new Error("the held-out set runs whole: it is read in total, never case by case");
  const cases = wanted ? all.filter((c) => wanted.includes(c.id)) : all;
  if (wanted && cases.length !== wanted.length) throw new Error(`no such case: ${wanted.filter((w) => !all.some((c) => c.id === w)).join(", ")}`);
  const judgeRuns = Number(option("judge-runs", JUDGE_LOOKS));
  const askedRounds = option("repeat") === undefined ? undefined : Number(option("repeat"));
  const minutes = Number(option("minutes", 0));
  const startedAt = Date.now();

  let meta;
  let runDir;
  if (resume) {
    runDir = findRunDir(resume);
    meta = JSON.parse(readFileSync(path.join(runDir, "run.json"), "utf8"));
    if (meta.engine !== engine) throw new Error(`${resume} is a ${meta.engine} run`);
    // `--resume <run> --repeat N` with more rounds than it had carries a reading on:
    // the new rounds are run and the reading is recorded again with them.
    if (askedRounds !== undefined && roundsFor(set, askedRounds) > (meta.rounds ?? 1)) {
      meta.rounds = roundsFor(set, askedRounds);
      meta.recorded = false;
    }
  } else {
    const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..*/, "").replace("T", "-");
    meta = { id: `${stamp}-${engine}${sealed ? `-${set}` : ""}`, engine, set, tag: option("tag") ?? "untagged", commit: commit(), started: new Date().toISOString(),
             caseIDs: cases.map((c) => c.id), rounds: roundsFor(set, askedRounds), engineModel: engine === "skill" ? SKILL_MODEL : null, cases: {}, looks: judgeRuns,
             // Switches the run turns on that are off at Next defaults (--on a,b): a try measured
             // before it is anybody's default. Recorded so the run never reads as the default app.
             switched: Object.fromEntries((option("on") ?? "").split(",").filter(Boolean).map((name) => [name, true])),
             // The built-in models the probe is lent (--models a,b), when a run measures one.
             models: (option("models") ?? "").split(",").filter(Boolean),
             // The Mac size Ask plans as (--mac 16): a 16 GB Mac reads a 32k window, not this Mac's 64k.
             mac: option("mac") ? Number(option("mac")) : null };
    runDir = runDirOf(meta.id, set);
    mkdirSync(runDir, { recursive: true });
  }
  console.log(`==> ${meta.id}: ${engine}, ${set} set, "${meta.tag}", ${meta.caseIDs.length} cases in ${roundsWord(meta.rounds)}, judged by ${JUDGE_MODEL} (rubric ${RUBRIC_ID}), ${judgeRuns} looks each`);
  if (Object.keys(meta.switched ?? {}).length) console.log(`    switched on, off at Next defaults: ${Object.keys(meta.switched).join(", ")}`);
  if (meta.models?.length) console.log(`    only these models downloaded, no picture model: ${meta.models.join(", ")}`);
  if (meta.mac) console.log(`    Ask plans as a ${meta.mac} GB Mac would`);
  if (sealed) console.log("    held out: each case is scored and kept, but only the total is printed or recorded");
  let done = Object.values(meta.cases).filter((r) => !r.unrun).length;
  let build = !flag("no-build");
  const byID = Object.fromEntries(all.map((c) => [c.id, c]));
  const runs = slotsOf(meta);
  for (const { key, id } of runs) {
    const testCase = byID[id];
    if (!testCase || (meta.cases[key] && !meta.cases[key].unrun)) continue;
    if (minutes && (Date.now() - startedAt) / 60000 > minutes) {
      console.log(`==> Stopped starting cases after ${minutes} minutes. Carry on with: Scripts/ask-eval.sh run --engine ${engine} --resume ${meta.id}`);
      saveMeta(runDir, meta);
      return;
    }
    const dir = path.join(runDir, key);
    mkdirSync(dir, { recursive: true });
    const caseStarted = Date.now();
    process.stdout.write(sealed ? `--> held-out run ${done + 1} of ${runs.length} ... ` : `--> ${key}: "${testCase.request.slice(0, 60)}" ... `);
    let got;
    try {
      got = engine === "ask" ? await runAsk(testCase, dir, { build, switched: meta.switched, models: meta.models, mac: meta.mac }) : await runSkill(testCase, dir, { build, switched: meta.switched });
    } catch (error) {
      got = { error: error.message };
      await quitProbe();
    }
    build = false;
    if (got.engine?.model && !meta.engineModel) meta.engineModel = got.engine.model;
    if (got.unrun) {
      console.log(`not run: ${got.unrun}`);
      meta.cases[key] = { group: testCase.group, score: 0, unrun: got.unrun, engine: got.engine };
      saveMeta(runDir, meta);
      if (/locked/.test(got.unrun)) { console.log("==> The screen is locked: Ask is found by name, so nothing can run. Resume when it is unlocked."); return; }
      continue;
    }
    const scored = await scoreCase(testCase, dir, got, judgeRuns);
    const result = {
      group: testCase.group, score: scored.score, rules: scored.rules, judge: scored.judge, named: scored.named,
      seconds: got.engine?.seconds ? Math.round(got.engine.seconds * 10) / 10 : null,
      caseSeconds: Math.round((Date.now() - caseStarted) / 100) / 10,
      engine: got.engine, error: got.error, sources: got.engine?.sources ?? [],
    };
    meta.cases[key] = result;
    writeFileSync(path.join(dir, "score.json"), JSON.stringify(result, null, 2));
    saveMeta(runDir, meta);
    done += 1;
    if (sealed) { console.log("scored"); continue; }
    console.log(`${result.score}  (rules ${result.rules?.score ?? "-"}, judge ${result.judge?.score ?? "-"}${result.named ? `, named ${result.named.right}/${result.named.of} as ${result.named.said.join(" / ")}${result.named.note ? " (spelled out, not counted)" : ""}` : ""}, ${result.seconds ?? "-"}s${got.error ? `, ${got.error}` : ""})`);
  }
  saveMeta(runDir, meta);
  const finished = runs.every(({ key }) => meta.cases[key] && !meta.cases[key].unrun);
  const sheet = sealed ? null : await drawSheet(runDir, meta);
  // A case not run counts 0 in the total, so a run with any left reads as unfinished, never as its score
  // (2026-11-02: three cases deferred for a person at the Mac read as Qwen3.5 9B's 19.8; finished, it was 21.2).
  const unrun = runs.filter(({ key }) => !meta.cases[key] || meta.cases[key].unrun).length;
  if (unrun) console.log(`==> ${meta.id}: UNFINISHED, ${unrun} of ${runs.length} runs not made yet; the total below counts them as 0 and is not this run's score`);
  console.log(`==> ${meta.id}: total ${meta.total}${plusMinus(meta)} over ${meta.caseIDs.length} cases in ${roundsWord(meta.rounds)} (${Object.entries(meta.groups).map(([g, v]) => `${g} ${v}`).join(", ")}), ${Math.round(meta.wallSeconds / 60)} min of cases`);
  if (meta.spread) console.log(`    by chance alone this reading moves about ${meta.spread.standardError} either way (one run of a case moves ${meta.spread.perRun}); two readings differ for real past ${Math.round(meta.spread.standardError * Math.SQRT2 * 2 * 10) / 10}`);
  console.log(`    ${describe(meta.lookups)}`);
  if (meta.model) console.log(`    ${meta.engineModel ?? engine}: ${meta.model.medianSeconds ?? "-"}s a request (median), ${meta.model.brokenCalls} of ${meta.model.calls} tool calls broken, ${meta.model.refused} refused by Ollama, ${meta.model.gigabytes ?? "-"} GB held`);
  if (sheet) console.log(`    contact sheet ${sheet}`);
  else console.log("    no contact sheet: a person who wants to see the held-out pictures runs `Scripts/ask-eval.sh sheet <run>` themselves");
  if (finished && !meta.recorded) {
    mkdirSync(path.dirname(historyFile), { recursive: true });
    // A reading carried on into more rounds replaces its own line.
    const line = JSON.stringify(historyLine(meta));
    if (history().some((h) => h.run === meta.id)) writeFileSync(historyFile, history().map((h) => (h.run === meta.id ? line : JSON.stringify(h))).join("\n") + "\n");
    else appendFileSync(historyFile, line + "\n");
    meta.recorded = true;
    writeFileSync(path.join(runDir, "run.json"), JSON.stringify(meta, null, 2));
    console.log(`    recorded in ${path.relative(repo, historyFile)}`);
    compare(historyLine(meta));
  } else if (!finished) {
    console.log(`    not finished, so not recorded yet: Scripts/ask-eval.sh run --engine ${engine} --resume ${meta.id}`);
  }
}

function history() {
  if (!existsSync(historyFile)) return [];
  return readFileSync(historyFile, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

/// A run against another (the best before it of the same engine and rubric
/// when none is named), case by case, with the time each took.
function compare(current, other) {
  const setOf = (h) => h.set ?? "climb";
  const past = history().filter((h) => h.engine === current.engine && h.rubric === current.rubric && h.run !== current.run
    && setOf(h) === setOf(current) && h.caseCount === current.caseCount);
  const base = other ?? past.sort((a, b) => b.total - a.total)[0];
  if (!base) { console.log("    nothing to compare with yet: this is the first run of this engine on this set and rubric"); return; }
  if (isSealed(setOf(current)) || isSealed(setOf(base))) {
    console.log(`\n${`${setOf(current)} total`.padEnd(24)}${`${current.total}${plusMinus(current)}`.padStart(12)}${`${base.total}${plusMinus(base)}`.padStart(12)}   ${(current.total - base.total).toFixed(1).padStart(6)}`);
    const pooled = pooledSpread(history(), { set: setOf(current), rubric: current.rubric });
    const odds = chance(current, base, pooled);
    console.log(odds ? `    ${odds.real ? "a REAL difference" : "INSIDE CHANCE"}: ${odds.difference} against a standard error of ${odds.standardError} (real past ${Math.round(odds.standardError * 20) / 10}${pooled ? `; one run of a case moves ${pooled.perRun}, pooled over ${pooled.readings} reading${pooled.readings === 1 ? "" : "s"}` : ""})`
      : "    neither reading ran a case twice, so nothing says how much of the difference is chance (README, \"How steady a reading is\")");
    console.log(`    ${describe(current.lookups)}\n    against "${base.tag}": ${describe(base.lookups)}`);
    return;
  }
  console.log(`\n${"case".padEnd(24)}${current.run.padStart(24)}${base.run.padStart(24)}   change   seconds`);
  for (const id of Object.keys({ ...current.cases, ...base.cases })) {
    const a = current.cases[id], b = base.cases[id];
    const change = a && b ? (a.score - b.score).toFixed(1) : "";
    const secs = a && b && a.seconds && b.seconds ? `${a.seconds} vs ${b.seconds}` : "";
    console.log(`${id.padEnd(24)}${String(a?.score ?? "-").padStart(24)}${String(b?.score ?? "-").padStart(24)}   ${change.padStart(6)}   ${secs}`);
  }
  const same = current.engine === base.engine;
  const verdict = !same ? `${current.engine} against ${base.engine}` : current.total > base.total ? "BETTER: keep it" : current.total < base.total ? "WORSE: throw it away" : "the same";
  const secs = (h) => Object.values(h.cases).reduce((s, c) => s + (c.seconds ?? 0), 0);
  console.log(`${"total".padEnd(24)}${String(current.total).padStart(24)}${String(base.total).padStart(24)}   ${(current.total - base.total).toFixed(1).padStart(6)}   ${Math.round(secs(current))} vs ${Math.round(secs(base))}`);
  console.log(`==> ${verdict} (against "${base.tag}")`);
}

function findRun(id) {
  const all = history();
  return id ? all.find((h) => h.run === id || h.run.endsWith(id)) : all.at(-1);
}

async function calibrate() {
  // The user's own verdicts (2026-10-20): the three pictures they called a mess
  // must score low, the clean sheet made by hand to the mock's look high.
  const cases = Object.fromEntries([...loadCases(), ...loadCases("held-out")].map((c) => [c.id, c]));
  const items = [
    { picture: "user-dog.png", case: "dog", want: "low" },
    { picture: "user-smiley-icon.png", case: "smiley-icon", want: "low" },
    { picture: "user-component-sheet-mess.png", case: "component-table", want: "low" },
    { picture: "clean-component-sheet.png", case: "component-table", want: "high" },
    // 2026-10-20: "the sun over mountains test produces such bad results.
    // mountains aren't triangles" - flat clip art scores 3 or lower on crafted.
    { picture: "user-sun-over-mountains.png", case: "illustration-sun-over-mountains", want: "low", crafted: 3 },
    // 2026-10-20: "it only seems to know how to draw 1 cat" and "It stuffed a
    // cat on top of some keys. horrible." Clean stock cats that ignore what
    // was asked: didWhatWasAsked 2 or lower, and the case under 40 even with
    // perfect rules, however clean the drawing is.
    { picture: "user-cat-curled-up-sleeping.png", case: "user-cat-curled-up-sleeping", want: "ignored", asked: 2 },
    { picture: "user-cat-playing-piano.png", case: "user-cartoon-cat-playing-piano", want: "ignored", asked: 2 },
    // 2026-10-20: "when you say 'annotate the ux with measurements around the
    // major ui elements', it is way too noisey" - twelve measurements, the
    // switch measured four times, readouts stacked: 3 or lower on clean.
    { picture: "user-settings-measurements-noisy.png", case: "settings-measurements", want: "low", clean: 3 },
  ];
  const wanted = { low: "4 or under", high: "7 or over", ignored: "asked 2 or under, case under 40" };
  let agrees = true;
  const results = [];
  for (const item of items) {
    const picture = path.join(here, "calibration", item.picture);
    const testCase = cases[item.case];
    const [judge, named] = await Promise.all([
      judgePicture({ picture, request: testCase.request, context: testCase.context, crafted: !!testCase.crafted }),
      testCase.group === "drawing" ? nameBlind({ picture, names: testCase.names }) : null,
    ]);
    // The best the case could score: every rule met.
    const atBest = combine(testCase, { score: 10 }, judge, named);
    const ok = (item.want === "low" ? judge.score <= 4 : item.want === "high" ? judge.score >= 7
      : (judge.lines.didWhatWasAsked ?? 10) <= item.asked && atBest < 40)
      && (item.crafted === undefined || (judge.lines.crafted ?? 10) <= item.crafted)
      && (item.clean === undefined || (judge.lines.clean ?? 10) <= item.clean);
    agrees &&= ok;
    results.push({ ...item, judge: judge.score, lines: judge.lines, named: named?.said, atBest, ok });
    console.log(`${ok ? "ok  " : "MISS"} ${item.picture.padEnd(34)} judge ${judge.score}, case at best ${atBest} (want ${wanted[item.want]})  ${Object.entries(judge.lines).map(([k, v]) => `${k} ${v}`).join(", ")}${named ? `  named: ${named.said.join(" / ")}` : ""}`);
    console.log(`     ${judge.why[0] ?? ""}`);
  }
  writeFileSync(path.join(here, "calibration/last-calibration.json"), JSON.stringify({ rubric: RUBRIC_ID, judgeModel: JUDGE_MODEL, at: new Date().toISOString(), agrees, results }, null, 2) + "\n");
  console.log(agrees ? "==> The judge agrees with the user." : "==> The judge does NOT agree with the user: fix rubric.md before anything uses it.");
  process.exitCode = agrees ? 0 : 1;
}

async function rescore(id) {
  const runDir = findRunDir(id);
  if (!runDir) throw new Error(`no run ${id}`);
  const meta = JSON.parse(readFileSync(path.join(runDir, "run.json"), "utf8"));
  const sealed = isSealed(meta.set);
  const cases = Object.fromEntries(loadCases(meta.set ?? "climb").map((c) => [c.id, c]));
  const only = option("cases")?.split(",");
  for (const [caseID, r] of Object.entries(meta.cases)) {
    if (r.unrun || (only && !only.includes(caseID))) continue;
    const dir = path.join(runDir, caseID);
    const read = JSON.parse(readFileSync(path.join(dir, "read.json"), "utf8"));
    const scored = await scoreCase(cases[baseID(caseID)], dir, { read, picture: path.join(dir, "result.png") }, JUDGE_LOOKS);
    Object.assign(r, { score: scored.score, rules: scored.rules, judge: scored.judge, named: scored.named });
    writeFileSync(path.join(dir, "score.json"), JSON.stringify(r, null, 2));
    if (!sealed) console.log(`${caseID.padEnd(24)} ${r.score}`);
  }
  saveMeta(runDir, meta);
  if (!sealed) await drawSheet(runDir, meta);
  // A recorded run's line is replaced, and says it was rescored.
  if (meta.recorded) {
    const line = { ...historyLine(meta), rescored: new Date().toISOString() };
    line.finished = history().find((h) => h.run === meta.id)?.finished ?? line.finished;
    writeFileSync(historyFile, history().map((h) => JSON.stringify(h.run === meta.id ? line : h)).join("\n") + "\n");
  }
  console.log(`==> total ${meta.total} (rescored on rubric ${RUBRIC_ID})`);
  console.log(`    ${describe(meta.lookups)}`);
}

/// Where the apps keep the cases a person's thumbs saved
/// (`AskFeedbackFolder` in the app): every Photonz bundle on this Mac.
function feedbackFolders() {
  const support = path.join(os.homedir(), "Library/Application Support");
  if (!existsSync(support)) return [];
  return readdirSync(support).filter((b) => /^com\.dzearing\.photonz/.test(b))
    .map((b) => path.join(support, b, "Ask feedback")).filter((d) => existsSync(d))
    .flatMap((d) => readdirSync(d).map((f) => path.join(d, f)))
    .filter((d) => existsSync(path.join(d, "case.json")) && existsSync(path.join(d, "before.photonz")));
}

/// A thumbs down becomes a held-out case: the request word for word, started
/// from the document as it was before Ask touched it. Thumbs up are counted,
/// not added (they say the result was fine, not what to test). Only the probe's
/// own votes are left out: those are walks, not people.
function importFeedback({ quiet = false } = {}) {
  const into = path.join(here, "held-out");
  const kept = path.join(into, "from-use");
  let added = 0, ups = 0, already = 0;
  for (const folder of feedbackFolders()) {
    if (folder.includes("com.dzearing.photonz.probe")) continue;
    const saved = JSON.parse(readFileSync(path.join(folder, "case.json"), "utf8"));
    if (saved.verdict !== "down") { ups += 1; continue; }
    const name = path.basename(folder);
    const file = path.join(into, `use-${name}.json`);
    if (existsSync(file)) { already += 1; continue; }
    mkdirSync(path.join(kept, name), { recursive: true });
    cpSync(path.join(folder, "before.photonz"), path.join(kept, name, "before.photonz"), { recursive: true });
    if (existsSync(path.join(folder, "after.png"))) cpSync(path.join(folder, "after.png"), path.join(kept, name, "what-it-made.png"));
    const drawing = /\b(draw|drawing|illustrat|sketch|paint|icon|picture of|cartoon)/i.test(saved.request);
    writeFileSync(file, JSON.stringify({
      request: saved.request,
      group: drawing ? "drawing" : "layout",
      from: `a thumbs down in ${saved.app}, ${saved.at} (Ask had made: ${saved.sentence}${saved.sources?.length ? `, from ${saved.sources.join(", ")}` : ""})`,
      start: { open: path.relative(repo, path.join(kept, name, "before.photonz")) },
      context: "the person's own document as it was before they asked",
      expect: {},
    }, null, 2) + "\n");
    added += 1;
  }
  if (!quiet || added) console.log(`==> feedback: ${added} new held-out case${added === 1 ? "" : "s"} from thumbs down, ${already} already in, ${ups} thumbs up counted (not cases)`);
  return added;
}

/// A run's judge lines in total (`judgeLines`), held-out runs included, and
/// another run's beside it: `lines <run> [--with <run>]`.
function lines() {
  const show = (id) => {
    const dir = findRunDir(id);
    if (!dir) throw new Error(`no run ${id}`);
    const meta = JSON.parse(readFileSync(path.join(dir, "run.json"), "utf8"));
    const got = judgeLines(meta.cases);
    const fmt = (m) => Object.entries(m).map(([k, v]) => `${k} ${v}`).join(", ");
    console.log(`${id}  total ${meta.total}  "${meta.tag}"\n    drawings: ${fmt(got.drawing)}; ${got.drawingSeconds ?? "-"}s a drawing request (median)\n    all:      ${fmt(got.all)}`);
  };
  show(positional);
  if (option("with")) show(option("with"));
}

/// Per group, how many of a run's cases were cut off by their time limit and
/// the median seconds a plan took. A case still planning at its limit has made
/// nothing and scores 0, so a group of a few cases swings by a whole case when a
/// slow model's plans sit near the limit. A total, so it works on held-out runs.
export function timeByGroup(cases) {
  const groups = {};
  for (const c of Object.values(cases)) {
    const g = (groups[c.group ?? "other"] ??= { cases: 0, ranOut: 0, stopped: 0, overFive: 0, seconds: [], steps: [] });
    g.cases += 1;
    if (c.engine?.phase === "stopped") g.stopped += 1;
    if (c.seconds > 300) g.overFive += 1;
    g.steps.push(c.engine?.steps?.length ?? 0);
    if (/"ran\|stopped"\) did not happen within/.test(c.engine?.said ?? "")) g.ranOut += 1;
    else if (c.seconds > 0) g.seconds.push(c.seconds);
  }
  return Object.fromEntries(Object.entries(groups).map(([name, g]) => {
    const median = (list) => list.length ? Math.round([...list].sort((a, b) => a - b)[Math.floor(list.length / 2)]) : null;
    return [name, { cases: g.cases, ranOut: g.ranOut, stopped: g.stopped, overFive: g.overFive, medianSeconds: median(g.seconds), medianSteps: median(g.steps) }];
  }));
}

function time() {
  for (const id of argv.slice(1).filter((a) => !a.startsWith("--"))) {
    const dir = findRunDir(id);
    if (!dir) throw new Error(`no run ${id}`);
    const meta = JSON.parse(readFileSync(path.join(dir, "run.json"), "utf8"));
    const got = timeByGroup(meta.cases);
    console.log(`${id}  ${meta.engineModel ?? meta.engine}  total ${meta.total}`);
    for (const [name, g] of Object.entries(got)) console.log(`    ${name.padEnd(10)}${String(meta.groups?.[name] ?? "-").padStart(6)}  ${g.ranOut} of ${g.cases} ran out of time, ${g.overFive} finished past five minutes, ${g.stopped} stopped part way, ${g.medianSeconds ?? "-"}s and ${g.medianSteps ?? "-"} steps a plan (median)`);
  }
}

/// The two numbers a runner reports: the latest climb run and the latest
/// held-out run of an engine on the current rubric.
function report() {
  const engine = option("engine", "ask");
  const mine = history().filter((h) => h.engine === engine && h.rubric === RUBRIC_ID);
  const climb = mine.filter((h) => (h.set ?? "climb") === "climb").at(-1);
  const held = mine.filter((h) => h.set === "held-out").at(-1);
  const motion = mine.filter((h) => h.set === "held-out-motion").at(-1);
  const line = (name, h) => h ? `${name.padEnd(9)} ${String(h.total).padStart(5)}${plusMinus(h)}  (${h.caseCount ?? Object.keys(h.cases ?? {}).length} cases, ${roundsWord(h.rounds)}, ${h.run}, "${h.tag}")\n          ${describe(h.lookups)}` : `${name.padEnd(9)}     -  (no run on rubric ${RUBRIC_ID} yet)`;
  console.log(`${engine} on rubric ${RUBRIC_ID}:\n${line("climb", climb)}\n${line("held-out", held)}${motion ? `\n${line("motion", motion)}` : ""}`);
}

try {
  if (command === "run") await commandRun();
  else if (command === "compare") {
    const current = findRun(positional);
    if (!current) throw new Error("no finished run to compare");
    const w = option("with");
    // --with a,b reads several readings of the same code as one baseline (`pooledReading`).
    const base = w && w !== "best" ? (w.includes(",") ? pooledReading(w.split(",").map((id) => findRun(id) ?? (() => { throw new Error(`no finished run ${id}`); })())) : findRun(w)) : undefined;
    compare(current, base);
  } else if (command === "history") {
    for (const h of history()) console.log(`${h.run}  ${h.engine.padEnd(5)}  ${(h.set ?? "climb").padEnd(8)}  total ${String(h.total).padStart(5)}${plusMinus(h)}  ${Object.entries(h.groups).map(([g, v]) => `${g} ${v}`).join(", ")}  ${Math.round(h.wallSeconds / 60)} min  "${h.tag}"`);
  } else if (command === "calibrate") await calibrate();
  else if (command === "feedback") importFeedback();
  else if (command === "report") report();
  else if (command === "lines") lines();
  else if (command === "time") time();
  else if (command === "sheet") {
    const runDir = findRunDir(positional);
    console.log(await drawSheet(runDir, JSON.parse(readFileSync(path.join(runDir, "run.json"), "utf8"))));
  } else if (command === "rescore") await rescore(positional);
  else {
    console.log(readFileSync(new URL(import.meta.url), "utf8").split("\n").slice(1, 12).map((l) => l.replace(/^\/\/ ?/, "")).join("\n"));
    process.exitCode = command ? 1 : 0;
  }
} catch (error) {
  console.error(`!! ${error.message}`);
  process.exitCode = 1;
}
