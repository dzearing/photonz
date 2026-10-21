#!/usr/bin/env node
// The scored test set for what Ask and the Photonz skill make
// (Scripts/ask-eval/README.md). Run it through Scripts/ask-eval.sh.
//
//   run --engine ask|skill --tag "<what changed>" [--set climb|held-out] [--cases a,b]
//       [--resume <run>] [--minutes N] [--no-build] [--judge-runs 3]
//   compare [<run>] [--with <run>|best]     a run against the best so far, case by case
//   report [--engine ask]                   the latest climb and held-out totals side by side
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
import { judgePicture, nameBlind, JUDGE_MODEL, RUBRIC_ID, run } from "./judge.mjs";
import { repo, runAsk, runSkill, quitProbe, SKILL_MODEL } from "./engines.mjs";
import { combine } from "./scoring.mjs";
import { tally, describe } from "./lookups.mjs";

const here = path.join(repo, "Scripts/ask-eval");
const runsDir = path.join(repo, ".ask-eval/runs");
/// Held-out runs live apart, and nothing here prints one of their cases.
const heldOutRunsDir = path.join(repo, ".ask-eval/held-out-runs");
const SETS = { climb: "cases", "held-out": "held-out" };
const runDirOf = (id, set) => path.join(set === "held-out" ? heldOutRunsDir : runsDir, id);
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
  if (!SETS[set]) throw new Error(`--set climb or --set held-out, not ${set}`);
  const dir = path.join(here, SETS[set]);
  return readdirSync(dir).filter((f) => f.endsWith(".json")).sort().map((f) => ({ id: f.replace(/\.json$/, ""), ...JSON.parse(readFileSync(path.join(dir, f), "utf8")) }));
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
    rules.score === 0 ? null : judgePicture({ picture: got.picture, request: testCase.request, context: testCase.context, runs: judgeRuns, crafted: !!testCase.crafted }),
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
  meta.lookups = tally(meta.cases);
  writeFileSync(path.join(runDir, "run.json"), JSON.stringify(meta, null, 2));
}

function historyLine(meta) {
  const line = {
    run: meta.id, engine: meta.engine, set: meta.set ?? "climb", tag: meta.tag, commit: meta.commit, started: meta.started, finished: new Date().toISOString(),
    wallSeconds: meta.wallSeconds, rubric: RUBRIC_ID, judgeModel: JUDGE_MODEL, engineModel: meta.engineModel,
    total: meta.total, groups: meta.groups, lookups: meta.lookups, caseCount: Object.keys(meta.cases).length,
  };
  // A held-out run is recorded in total only, so no case can be climbed on.
  if (meta.set === "held-out") return line;
  return {
    ...line,
    cases: Object.fromEntries(Object.entries(meta.cases).map(([id, r]) => [id, {
      score: r.score, rules: r.rules?.score ?? null, judge: r.judge?.score ?? null, named: r.named ? `${r.named.right}/${r.named.of}` : undefined,
      seconds: r.seconds, unrun: r.unrun, sources: r.sources,
    }])),
  };
}

async function commandRun() {
  const engine = option("engine");
  if (!["ask", "skill"].includes(engine)) throw new Error("--engine ask or --engine skill");
  const resume = option("resume");
  const set = resume ? JSON.parse(readFileSync(path.join(findRunDir(resume) ?? runDirOf(resume, "climb"), "run.json"), "utf8")).set ?? "climb" : option("set", "climb");
  const sealed = set === "held-out";
  if (sealed && !resume) importFeedback({ quiet: true });
  const all = loadCases(set);
  const wanted = option("cases")?.split(",");
  if (sealed && wanted) throw new Error("the held-out set runs whole: it is read in total, never case by case");
  const cases = wanted ? all.filter((c) => wanted.includes(c.id)) : all;
  if (wanted && cases.length !== wanted.length) throw new Error(`no such case: ${wanted.filter((w) => !all.some((c) => c.id === w)).join(", ")}`);
  const judgeRuns = Number(option("judge-runs", 3));
  const minutes = Number(option("minutes", 0));
  const startedAt = Date.now();

  let meta;
  let runDir;
  if (resume) {
    runDir = findRunDir(resume);
    meta = JSON.parse(readFileSync(path.join(runDir, "run.json"), "utf8"));
    if (meta.engine !== engine) throw new Error(`${resume} is a ${meta.engine} run`);
  } else {
    const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..*/, "").replace("T", "-");
    meta = { id: `${stamp}-${engine}${sealed ? "-held-out" : ""}`, engine, set, tag: option("tag") ?? "untagged", commit: commit(), started: new Date().toISOString(),
             caseIDs: cases.map((c) => c.id), engineModel: engine === "skill" ? SKILL_MODEL : null, cases: {} };
    runDir = runDirOf(meta.id, set);
    mkdirSync(runDir, { recursive: true });
  }
  console.log(`==> ${meta.id}: ${engine}, ${set} set, "${meta.tag}", ${meta.caseIDs.length} cases, judged by ${JUDGE_MODEL} (rubric ${RUBRIC_ID}), ${judgeRuns} looks each`);
  if (sealed) console.log("    held out: each case is scored and kept, but only the total is printed or recorded");
  let done = Object.values(meta.cases).filter((r) => !r.unrun).length;
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
    process.stdout.write(sealed ? `--> held-out case ${done + 1} of ${meta.caseIDs.length} ... ` : `--> ${testCase.id}: "${testCase.request.slice(0, 60)}" ... `);
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
      engine: got.engine, error: got.error, sources: got.engine?.sources ?? [],
    };
    meta.cases[testCase.id] = result;
    writeFileSync(path.join(dir, "score.json"), JSON.stringify(result, null, 2));
    saveMeta(runDir, meta);
    done += 1;
    if (sealed) { console.log("scored"); continue; }
    console.log(`${result.score}  (rules ${result.rules?.score ?? "-"}, judge ${result.judge?.score ?? "-"}${result.named ? `, named ${result.named.right}/${result.named.of} as ${result.named.said.join(" / ")}${result.named.note ? " (spelled out, not counted)" : ""}` : ""}, ${result.seconds ?? "-"}s${got.error ? `, ${got.error}` : ""})`);
  }
  saveMeta(runDir, meta);
  const finished = meta.caseIDs.every((id) => meta.cases[id] && !meta.cases[id].unrun);
  const sheet = sealed ? null : await drawSheet(runDir, meta);
  console.log(`==> ${meta.id}: total ${meta.total} over ${Object.keys(meta.cases).length} cases (${Object.entries(meta.groups).map(([g, v]) => `${g} ${v}`).join(", ")}), ${Math.round(meta.wallSeconds / 60)} min of cases`);
  console.log(`    ${describe(meta.lookups)}`);
  if (sheet) console.log(`    contact sheet ${sheet}`);
  else console.log("    no contact sheet: a person who wants to see the held-out pictures runs `Scripts/ask-eval.sh sheet <run>` themselves");
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
  const setOf = (h) => h.set ?? "climb";
  const past = history().filter((h) => h.engine === current.engine && h.rubric === current.rubric && h.run !== current.run
    && setOf(h) === setOf(current) && h.caseCount === current.caseCount);
  const base = other ?? past.sort((a, b) => b.total - a.total)[0];
  if (!base) { console.log("    nothing to compare with yet: this is the first run of this engine on this set and rubric"); return; }
  if (setOf(current) === "held-out" || setOf(base) === "held-out") {
    console.log(`\n${"held-out total".padEnd(24)}${String(current.total).padStart(10)}${String(base.total).padStart(10)}   ${(current.total - base.total).toFixed(1).padStart(6)}`);
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
  ];
  const wanted = { low: "4 or under", high: "7 or over", ignored: "asked 2 or under, case under 40" };
  let agrees = true;
  const results = [];
  for (const item of items) {
    const picture = path.join(here, "calibration", item.picture);
    const testCase = cases[item.case];
    const [judge, named] = await Promise.all([
      judgePicture({ picture, request: testCase.request, context: testCase.context, runs: 3, crafted: !!testCase.crafted }),
      testCase.group === "drawing" ? nameBlind({ picture, names: testCase.names, runs: 3 }) : null,
    ]);
    // The best the case could score: every rule met.
    const atBest = combine(testCase, { score: 10 }, judge, named);
    const ok = (item.want === "low" ? judge.score <= 4 : item.want === "high" ? judge.score >= 7
      : (judge.lines.didWhatWasAsked ?? 10) <= item.asked && atBest < 40)
      && (item.crafted === undefined || (judge.lines.crafted ?? 10) <= item.crafted);
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
  const sealed = meta.set === "held-out";
  const cases = Object.fromEntries(loadCases(meta.set ?? "climb").map((c) => [c.id, c]));
  const only = option("cases")?.split(",");
  for (const [caseID, r] of Object.entries(meta.cases)) {
    if (r.unrun || (only && !only.includes(caseID))) continue;
    const dir = path.join(runDir, caseID);
    const read = JSON.parse(readFileSync(path.join(dir, "read.json"), "utf8"));
    const scored = await scoreCase(cases[caseID], dir, { read, picture: path.join(dir, "result.png") }, 3);
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

/// The two numbers a runner reports: the latest climb run and the latest
/// held-out run of an engine on the current rubric.
function report() {
  const engine = option("engine", "ask");
  const mine = history().filter((h) => h.engine === engine && h.rubric === RUBRIC_ID);
  const climb = mine.filter((h) => (h.set ?? "climb") === "climb").at(-1);
  const held = mine.filter((h) => h.set === "held-out").at(-1);
  const line = (name, h) => h ? `${name.padEnd(9)} ${String(h.total).padStart(5)}  (${h.caseCount ?? Object.keys(h.cases ?? {}).length} cases, ${h.run}, "${h.tag}")\n          ${describe(h.lookups)}` : `${name.padEnd(9)}     -  (no run on rubric ${RUBRIC_ID} yet)`;
  console.log(`${engine} on rubric ${RUBRIC_ID}:\n${line("climb", climb)}\n${line("held-out", held)}`);
}

try {
  if (command === "run") await commandRun();
  else if (command === "compare") {
    const current = findRun(positional);
    if (!current) throw new Error("no finished run to compare");
    const w = option("with");
    compare(current, w && w !== "best" ? findRun(w) : undefined);
  } else if (command === "history") {
    for (const h of history()) console.log(`${h.run}  ${h.engine.padEnd(5)}  ${(h.set ?? "climb").padEnd(8)}  total ${String(h.total).padStart(5)}  ${Object.entries(h.groups).map(([g, v]) => `${g} ${v}`).join(", ")}  ${Math.round(h.wallSeconds / 60)} min  "${h.tag}"`);
  } else if (command === "calibrate") await calibrate();
  else if (command === "feedback") importFeedback();
  else if (command === "report") report();
  else if (command === "sheet") {
    const runDir = findRunDir(positional);
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
