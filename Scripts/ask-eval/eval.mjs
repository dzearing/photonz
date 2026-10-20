#!/usr/bin/env node
// The scored test set for what Ask and the Photonz skill make
// (Scripts/ask-eval/README.md). Run it through Scripts/ask-eval.sh.
//
//   run --engine ask|skill --tag "<what changed>" [--cases a,b] [--resume <run>]
//       [--minutes N] [--no-build] [--judge-runs 3]
//   compare [<run>] [--with <run>|best]     a run against the best so far, case by case
//   history                                 every finished run, newest last
//   calibrate                               the judge against the user's own verdicts
//   sheet <run>                             (re)draw a run's contact sheet
//   rescore <run>                           re-run the rules and judge on saved results
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { score as ruleScore } from "./rules.mjs";
import { judgePicture, nameBlind, JUDGE_MODEL, RUBRIC_ID, run } from "./judge.mjs";
import { repo, runAsk, runSkill, quitProbe, SKILL_MODEL } from "./engines.mjs";

const here = path.join(repo, "Scripts/ask-eval");
const runsDir = path.join(repo, ".ask-eval/runs");
const historyFile = path.join(repo, "queue/evals/ask-eval-history.jsonl");

const argv = process.argv.slice(2);
const command = argv[0];
const option = (name, fallback) => { const at = argv.indexOf(`--${name}`); return at >= 0 ? argv[at + 1] : fallback; };
const flag = (name) => argv.includes(`--${name}`);
const positional = argv.slice(1).find((a, i, all) => !a.startsWith("--") && !(i > 0 && all[i - 1].startsWith("--") && !["--no-build"].includes(all[i - 1])));

export function loadCases() {
  const dir = path.join(here, "cases");
  return readdirSync(dir).filter((f) => f.endsWith(".json")).sort().map((f) => ({ id: f.replace(/\.json$/, ""), ...JSON.parse(readFileSync(path.join(dir, f), "utf8")) }));
}

/// A case's score, 0 to 100. A drawing: 30% rules, 40% judge, 30% named blind.
/// Anything else: 40% rules, 60% judge. Nothing made is 0.
export function combine(testCase, rules, judge, named) {
  if (!rules || rules.score === 0) return 0;
  const j = judge?.score ?? 0;
  const value = testCase.group === "drawing" ? 3 * rules.score + 4 * j + 3 * (named?.score ?? 0) : 4 * rules.score + 6 * j;
  return Math.round(value * 10) / 10;
}

const groupsOf = (results) => {
  const groups = {};
  for (const r of Object.values(results)) (groups[r.group] ??= []).push(r.score);
  return Object.fromEntries(Object.entries(groups).map(([g, v]) => [g, Math.round(v.reduce((s, x) => s + x, 0) / v.length * 10) / 10]));
};
const mean = (values) => (values.length ? Math.round(values.reduce((s, v) => s + v, 0) / values.length * 10) / 10 : null);

async function scoreCase(testCase, dir, got, judgeRuns) {
  if (!got.read || !got.picture) return { rules: null, judge: null, named: null, score: 0 };
  const rules = ruleScore(got.read, testCase);
  const [judge, named] = await Promise.all([
    rules.score === 0 ? null : judgePicture({ picture: got.picture, request: testCase.request, context: testCase.context, runs: judgeRuns }),
    testCase.group === "drawing" && rules.score !== 0 ? nameBlind({ picture: got.picture, names: testCase.names ?? [], runs: judgeRuns }) : null,
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
  const scores = Object.values(meta.cases).map((r) => r.score);
  meta.total = mean(scores);
  meta.groups = groupsOf(meta.cases);
  meta.wallSeconds = Math.round(Object.values(meta.cases).reduce((s, r) => s + (r.caseSeconds ?? 0), 0));
  writeFileSync(path.join(runDir, "run.json"), JSON.stringify(meta, null, 2));
}

function historyLine(meta) {
  return {
    run: meta.id, engine: meta.engine, tag: meta.tag, commit: meta.commit, started: meta.started, finished: new Date().toISOString(),
    wallSeconds: meta.wallSeconds, rubric: RUBRIC_ID, judgeModel: JUDGE_MODEL, engineModel: meta.engineModel,
    total: meta.total, groups: meta.groups,
    cases: Object.fromEntries(Object.entries(meta.cases).map(([id, r]) => [id, {
      score: r.score, rules: r.rules?.score ?? null, judge: r.judge?.score ?? null, named: r.named ? `${r.named.right}/${r.named.of}` : undefined,
      seconds: r.seconds, unrun: r.unrun,
    }])),
  };
}

async function commandRun() {
  const engine = option("engine");
  if (!["ask", "skill"].includes(engine)) throw new Error("--engine ask or --engine skill");
  const all = loadCases();
  const wanted = option("cases")?.split(",");
  const cases = wanted ? all.filter((c) => wanted.includes(c.id)) : all;
  if (wanted && cases.length !== wanted.length) throw new Error(`no such case: ${wanted.filter((w) => !all.some((c) => c.id === w)).join(", ")}`);
  const judgeRuns = Number(option("judge-runs", 3));
  const minutes = Number(option("minutes", 0));
  const startedAt = Date.now();

  let meta;
  let runDir;
  const resume = option("resume");
  if (resume) {
    runDir = path.join(runsDir, resume);
    meta = JSON.parse(readFileSync(path.join(runDir, "run.json"), "utf8"));
    if (meta.engine !== engine) throw new Error(`${resume} is a ${meta.engine} run`);
  } else {
    const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..*/, "").replace("T", "-");
    meta = { id: `${stamp}-${engine}`, engine, tag: option("tag") ?? "untagged", commit: commit(), started: new Date().toISOString(),
             caseIDs: cases.map((c) => c.id), engineModel: engine === "skill" ? SKILL_MODEL : null, cases: {} };
    runDir = path.join(runsDir, meta.id);
    mkdirSync(runDir, { recursive: true });
  }
  console.log(`==> ${meta.id}: ${engine}, "${meta.tag}", ${meta.caseIDs.length} cases, judged by ${JUDGE_MODEL} (rubric ${RUBRIC_ID}), ${judgeRuns} looks each`);
  let build = !flag("no-build");
  for (const testCase of all.filter((c) => meta.caseIDs.includes(c.id))) {
    if (meta.cases[testCase.id] && !meta.cases[testCase.id].unrun) continue;
    if (minutes && (Date.now() - startedAt) / 60000 > minutes) {
      console.log(`==> Stopped starting cases after ${minutes} minutes. Carry on with: Scripts/ask-eval.sh run --engine ${engine} --resume ${meta.id}`);
      saveMeta(runDir, meta);
      return;
    }
    const dir = path.join(runDir, testCase.id);
    mkdirSync(dir, { recursive: true });
    const caseStarted = Date.now();
    process.stdout.write(`--> ${testCase.id}: "${testCase.request.slice(0, 60)}" ... `);
    let got;
    try {
      got = engine === "ask" ? await runAsk(testCase, dir, { build }) : await runSkill(testCase, dir, { build });
    } catch (error) {
      got = { error: error.message };
      await quitProbe();
    }
    build = false;
    if (got.engine?.model && !meta.engineModel) meta.engineModel = got.engine.model;
    if (got.unrun) {
      console.log(`not run: ${got.unrun}`);
      meta.cases[testCase.id] = { group: testCase.group, score: 0, unrun: got.unrun, engine: got.engine };
      saveMeta(runDir, meta);
      if (/locked/.test(got.unrun)) { console.log("==> The screen is locked: Ask is found by name, so nothing can run. Resume when it is unlocked."); return; }
      continue;
    }
    const scored = await scoreCase(testCase, dir, got, judgeRuns);
    const result = {
      group: testCase.group, score: scored.score, rules: scored.rules, judge: scored.judge, named: scored.named,
      seconds: got.engine?.seconds ? Math.round(got.engine.seconds * 10) / 10 : null,
      caseSeconds: Math.round((Date.now() - caseStarted) / 100) / 10,
      engine: got.engine, error: got.error,
    };
    meta.cases[testCase.id] = result;
    writeFileSync(path.join(dir, "score.json"), JSON.stringify(result, null, 2));
    saveMeta(runDir, meta);
    console.log(`${result.score}  (rules ${result.rules?.score ?? "-"}, judge ${result.judge?.score ?? "-"}${result.named ? `, named ${result.named.right}/${result.named.of} as ${result.named.said.join(" / ")}${result.named.note ? " (spelled out, not counted)" : ""}` : ""}, ${result.seconds ?? "-"}s${got.error ? `, ${got.error}` : ""})`);
  }
  saveMeta(runDir, meta);
  const finished = meta.caseIDs.every((id) => meta.cases[id] && !meta.cases[id].unrun);
  const sheet = await drawSheet(runDir, meta);
  console.log(`==> ${meta.id}: total ${meta.total} over ${Object.keys(meta.cases).length} cases (${Object.entries(meta.groups).map(([g, v]) => `${g} ${v}`).join(", ")}), ${Math.round(meta.wallSeconds / 60)} min of cases`);
  console.log(`    contact sheet ${sheet}`);
  if (finished && !meta.recorded) {
    mkdirSync(path.dirname(historyFile), { recursive: true });
    appendFileSync(historyFile, JSON.stringify(historyLine(meta)) + "\n");
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
  const past = history().filter((h) => h.engine === current.engine && h.rubric === current.rubric && h.run !== current.run);
  const base = other ?? past.sort((a, b) => b.total - a.total)[0];
  if (!base) { console.log("    nothing to compare with yet: this is the first run of this engine on this rubric"); return; }
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
  const cases = Object.fromEntries(loadCases().map((c) => [c.id, c]));
  const items = [
    { picture: "user-dog.png", case: "dog", want: "low" },
    { picture: "user-smiley-icon.png", case: "smiley-icon", want: "low" },
    { picture: "user-component-sheet-mess.png", case: "component-table", want: "low" },
    { picture: "clean-component-sheet.png", case: "component-table", want: "high" },
  ];
  let agrees = true;
  const results = [];
  for (const item of items) {
    const picture = path.join(here, "calibration", item.picture);
    const testCase = cases[item.case];
    const [judge, named] = await Promise.all([
      judgePicture({ picture, request: testCase.request, context: testCase.context, runs: 3 }),
      testCase.group === "drawing" ? nameBlind({ picture, names: testCase.names, runs: 3 }) : null,
    ]);
    const ok = item.want === "low" ? judge.score <= 4 : judge.score >= 7;
    agrees &&= ok;
    results.push({ ...item, judge: judge.score, lines: judge.lines, named: named?.said, ok });
    console.log(`${ok ? "ok  " : "MISS"} ${item.picture.padEnd(34)} judge ${judge.score} (want ${item.want === "low" ? "4 or under" : "7 or over"})  ${Object.entries(judge.lines).map(([k, v]) => `${k} ${v}`).join(", ")}${named ? `  named: ${named.said.join(" / ")}` : ""}`);
    console.log(`     ${judge.why[0] ?? ""}`);
  }
  writeFileSync(path.join(here, "calibration/last-calibration.json"), JSON.stringify({ rubric: RUBRIC_ID, judgeModel: JUDGE_MODEL, at: new Date().toISOString(), agrees, results }, null, 2) + "\n");
  console.log(agrees ? "==> The judge agrees with the user." : "==> The judge does NOT agree with the user: fix rubric.md before anything uses it.");
  process.exitCode = agrees ? 0 : 1;
}

async function rescore(id) {
  const runDir = path.join(runsDir, id);
  const meta = JSON.parse(readFileSync(path.join(runDir, "run.json"), "utf8"));
  const cases = Object.fromEntries(loadCases().map((c) => [c.id, c]));
  const only = option("cases")?.split(",");
  for (const [caseID, r] of Object.entries(meta.cases)) {
    if (r.unrun || (only && !only.includes(caseID))) continue;
    const dir = path.join(runDir, caseID);
    const read = JSON.parse(readFileSync(path.join(dir, "read.json"), "utf8"));
    const scored = await scoreCase(cases[caseID], dir, { read, picture: path.join(dir, "result.png") }, 3);
    Object.assign(r, { score: scored.score, rules: scored.rules, judge: scored.judge, named: scored.named });
    console.log(`${caseID.padEnd(24)} ${r.score}`);
  }
  saveMeta(runDir, meta);
  await drawSheet(runDir, meta);
  // A recorded run's line is replaced, and says it was rescored.
  if (meta.recorded) {
    const line = { ...historyLine(meta), rescored: new Date().toISOString() };
    line.finished = history().find((h) => h.run === meta.id)?.finished ?? line.finished;
    writeFileSync(historyFile, history().map((h) => JSON.stringify(h.run === meta.id ? line : h)).join("\n") + "\n");
  }
  console.log(`==> total ${meta.total} (rescored on rubric ${RUBRIC_ID})`);
}

try {
  if (command === "run") await commandRun();
  else if (command === "compare") {
    const current = findRun(positional);
    if (!current) throw new Error("no finished run to compare");
    const w = option("with");
    compare(current, w && w !== "best" ? findRun(w) : undefined);
  } else if (command === "history") {
    for (const h of history()) console.log(`${h.run}  ${h.engine.padEnd(5)}  total ${String(h.total).padStart(5)}  ${Object.entries(h.groups).map(([g, v]) => `${g} ${v}`).join(", ")}  ${Math.round(h.wallSeconds / 60)} min  "${h.tag}"`);
  } else if (command === "calibrate") await calibrate();
  else if (command === "sheet") {
    const runDir = path.join(runsDir, positional);
    console.log(await drawSheet(runDir, JSON.parse(readFileSync(path.join(runDir, "run.json"), "utf8"))));
  } else if (command === "rescore") await rescore(positional);
  else {
    console.log(readFileSync(new URL(import.meta.url), "utf8").split("\n").slice(1, 11).map((l) => l.replace(/^\/\/ ?/, "")).join("\n"));
    process.exitCode = command ? 1 : 0;
  }
} catch (error) {
  console.error(`!! ${error.message}`);
  process.exitCode = 1;
}
