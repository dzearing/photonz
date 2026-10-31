#!/usr/bin/env node
// The two-turn eval: Ask makes something, then is asked to change one part of
// it ("paint a beach at sunset", then "make the water bluer"), the way a
// person talks to it. Each case runs on the probe at Next defaults, both
// requests typed in one window, and a strong model judge that can see compares
// the picture after the first request with the picture after the second:
//
//   rightPart         the change landed on the part the words name
//   matchesWords      it does what the words say, plainly visible
//   nothingElseMoved  everything the words did not name is as it was
//
// A case passes when both requests ran and the median of three looks is at
// least 7 on every line. The bar (queue task
// ask-changes-what-it-just-made-make-the-water-blu): 10 of the 12 cases.
//
//   node Scripts/ask-eval/followup.mjs run --tag "<what changed>" [--run <id>] [--cases a,b] [--minutes N] [--no-build]
//   node Scripts/ask-eval/followup.mjs report [<run>]
//
// A run is resumed by naming it with --run: cases already scored are kept.
// Runs land in .ask-eval/followups/<run>/<case>/ (first.png, second.png,
// walk.json, score.json); every finished run's totals go into
// queue/evals/ask-followup-history.jsonl. Dev tooling only.
import { appendFileSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { run, JUDGE_MODEL } from "./judge.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const casesDir = path.join(here, "followups");
const runsDir = path.join(repo, ".ask-eval/followups");
const history = path.join(repo, "queue/evals/ask-followup-history.jsonl");
const LOOKS = 3;
const BAR = 7;

const argv = process.argv.slice(2);
const command = argv[0];
const flag = (name) => { const at = argv.indexOf(name); return at >= 0 ? argv[at + 1] : undefined; };
const has = (name) => argv.includes(name);

function cases() {
  return readdirSync(casesDir).filter((f) => f.endsWith(".json")).sort()
    .map((f) => ({ id: f.replace(/\.json$/, ""), ...JSON.parse(readFileSync(path.join(casesDir, f), "utf8")) }));
}

function askSteps(words, limit, stage) {
  return [
    { do: "key", key: "k", modifiers: ["command"] }, { do: "wait", seconds: 0.5 },
    { do: "type", text: words }, { do: "wait", seconds: 0.3 },
    { do: "key", key: "return" },
    { do: "waitFor", condition: "askPhase", value: "planning|running|ran|stopped", timeout: 15 },
    { do: "waitFor", condition: "askPhase", value: "ran|stopped", timeout: limit },
    { do: "wait", seconds: 1.5 },
    { do: "describe", stage, note: `after: ${words}` },
  ];
}

/// Both requests in one window, a picture of the document after each.
async function walkCase(testCase, dir, build) {
  const [width, height] = testCase.start.blank;
  const limit = testCase.timeout ?? 300;
  const out = path.join(dir, "walk");
  const script = path.join(dir, "walk.json");
  writeFileSync(script, JSON.stringify({
    out, seed: "ask-eval followup: one two-turn case (Scripts/ask-eval/followup.mjs)", clock: 2 * limit + 240,
    setup: { forget: ["all"], front: true },
    steps: [
      { do: "blank", canvasWidth: width, canvasHeight: height, width: 1280, height: 840 }, { do: "wait", seconds: 1 },
      ...askSteps(testCase.make, limit, "made"),
      { do: "render", name: "first" },
      ...askSteps(testCase.then, limit, "changed"),
      { do: "render", name: "second" },
    ],
  }, null, 2));
  const args = [script];
  if (!build) args.push("--no-build");
  const result = await run(path.join(repo, "Scripts/playtest.sh"), args, { cwd: repo, timeoutMS: (2 * limit + 360) * 1000 });
  writeFileSync(path.join(dir, "walk.out.txt"), result.stdout + result.stderr);
  let log = [];
  try { log = JSON.parse(readFileSync(path.join(out, "log.json"), "utf8")); } catch {}
  // A describe step logs under its stage's name.
  const at = (stage) => log.filter((e) => e.do === stage && e.state?.ask).at(-1)?.state.ask;
  const made = at("made"), changed = at("changed");
  for (const name of ["first", "second"]) {
    const png = path.join(out, `${name}.png`);
    if (existsSync(png)) copyFileSync(png, path.join(dir, `${name}.png`));
  }
  return {
    code: result.code,
    made: made && { phase: made.phase, says: made.says, steps: made.steps?.length ?? 0 },
    changed: changed && { phase: changed.phase, says: changed.says, steps: changed.steps ?? [], trace: changed.trace ?? [] },
  };
}

const PROMPT = `Two pictures from a picture editor. The first, at {{first}}, is what its helper made when asked: "{{make}}". Then the person asked: "{{then}}". The second picture, at {{second}}, is the result.
Read both pictures, then score the change from 1 to 10 on each line, strictly:
- rightPart: did the change land on what the words name ({{part}}) and nothing else? 10: exactly that. 1: nothing changed, or something else changed instead.
- matchesWords: does the change do what the words say, plainly visible at a glance (bluer is clearly bluer, bigger is clearly bigger, removed is gone)? 10: unmistakable. 1: nothing visible, or the opposite.
- nothingElseMoved: is everything the words did not name the same as in the first picture? 10: identical apart from what was named. 5: the same picture with other parts noticeably changed. 1: a different picture, remade from scratch.
Answer with only JSON: {"rightPart": n, "matchesWords": n, "nothingElseMoved": n, "why": "one sentence"}`;

async function look(testCase, first, second) {
  const scratch = mkdtempSync(path.join(os.tmpdir(), "followup-judge-"));
  try {
    const a = path.join(scratch, "first.png"), b = path.join(scratch, "second.png");
    copyFileSync(first, a);
    copyFileSync(second, b);
    const text = PROMPT.replaceAll("{{first}}", a).replaceAll("{{second}}", b).replaceAll("{{make}}", testCase.make)
      .replaceAll("{{then}}", testCase.then).replaceAll("{{part}}", testCase.part);
    const result = await run("claude", ["-p", "--model", JUDGE_MODEL, "--tools", "Read", "--allowedTools", "Read",
      "--setting-sources", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
      "--no-session-persistence", "--output-format", "json", text], { cwd: scratch, timeoutMS: 180_000 });
    const said = JSON.parse(result.stdout).result ?? "";
    const json = said.match(/\{[\s\S]*\}/);
    return json ? JSON.parse(json[0]) : null;
  } catch {
    return null;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

const median = (values) => {
  const sorted = values.filter((v) => typeof v === "number").sort((x, y) => x - y);
  if (!sorted.length) return null;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

async function judge(testCase, dir, walked) {
  const first = path.join(dir, "first.png"), second = path.join(dir, "second.png");
  const ran = walked.made?.phase === "ran" && walked.changed?.phase === "ran";
  if (!existsSync(first) || !existsSync(second) || walked.made?.phase !== "ran") {
    return { pass: false, why: `the first request did not make anything (${walked.made?.phase ?? "no state"})`, looks: [] };
  }
  const looks = (await Promise.all(Array.from({ length: LOOKS }, () => look(testCase, first, second)))).filter(Boolean);
  const lines = {
    rightPart: median(looks.map((l) => l.rightPart)),
    matchesWords: median(looks.map((l) => l.matchesWords)),
    nothingElseMoved: median(looks.map((l) => l.nothingElseMoved)),
  };
  const pass = ran && Object.values(lines).every((v) => v !== null && v >= BAR);
  const why = !ran ? `the change request ended ${walked.changed?.phase ?? "with no state"}: ${walked.changed?.says ?? ""}` : looks[0]?.why ?? "";
  return { pass, ...lines, why, looks };
}

async function commandRun() {
  const id = flag("--run") ?? `${new Date().toISOString().replace(/[-:]/g, "").replace("T", "-").slice(0, 15)}-followup`;
  const dir = path.join(runsDir, id);
  mkdirSync(dir, { recursive: true });
  const metaFile = path.join(dir, "run.json");
  const meta = existsSync(metaFile) ? JSON.parse(readFileSync(metaFile, "utf8"))
    : { run: id, tag: flag("--tag") ?? "", started: new Date().toISOString(), judgeModel: JUDGE_MODEL };
  writeFileSync(metaFile, JSON.stringify(meta, null, 2));
  const only = flag("--cases")?.split(",");
  const deadline = flag("--minutes") ? Date.now() + Number(flag("--minutes")) * 60_000 : Infinity;
  let build = !has("--no-build");
  console.log(`followup run ${id}${meta.tag ? ` (${meta.tag})` : ""}`);
  for (const testCase of cases().filter((c) => !only || only.includes(c.id))) {
    const caseDir = path.join(dir, testCase.id);
    if (existsSync(path.join(caseDir, "score.json"))) continue;
    if (Date.now() > deadline) {
      console.log(`stopped for time; carry on with: node Scripts/ask-eval/followup.mjs run --run ${id} --no-build`);
      return;
    }
    mkdirSync(caseDir, { recursive: true });
    const started = Date.now();
    const walked = await walkCase(testCase, caseDir, build);
    build = false;
    await run(path.join(repo, "Scripts/probe-app.sh"), ["--quit"], { cwd: repo, timeoutMS: 60_000 });
    if (walked.code === 3 || walked.code === 6) {
      console.log(`${testCase.id}: not run (${walked.code === 3 ? "screen locked" : "person at the Mac"})`);
      rmSync(caseDir, { recursive: true, force: true });
      return;
    }
    const score = await judge(testCase, caseDir, walked);
    const record = { case: testCase.id, group: testCase.group, make: testCase.make, then: testCase.then,
      seconds: Math.round((Date.now() - started) / 1000), walk: walked.code,
      made: walked.made, changed: { phase: walked.changed?.phase, says: walked.changed?.says,
        steps: walked.changed?.steps ?? [], trace: (walked.changed?.trace ?? []).slice(-40) }, ...score };
    writeFileSync(path.join(caseDir, "score.json"), JSON.stringify(record, null, 2));
    console.log(`${testCase.id}: ${score.pass ? "PASS" : "fail"}  part ${score.rightPart ?? "-"} words ${score.matchesWords ?? "-"} rest ${score.nothingElseMoved ?? "-"}  ${score.why}`);
  }
  report(id);
}

function report(id) {
  const runs = existsSync(runsDir) ? readdirSync(runsDir).sort() : [];
  id = id ?? runs.at(-1);
  if (!id) { console.log("no followup runs yet"); return; }
  const dir = path.join(runsDir, id);
  const all = cases();
  const scores = all.map((c) => {
    const file = path.join(dir, c.id, "score.json");
    return existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : null;
  });
  const done = scores.filter(Boolean);
  const passed = done.filter((s) => s.pass).length;
  console.log(`${id}: ${passed} of ${done.length} passed (${all.length} cases in the set)`);
  for (const s of done) console.log(`  ${s.pass ? "PASS" : "fail"}  ${s.case.padEnd(30)} part ${s.rightPart ?? "-"} words ${s.matchesWords ?? "-"} rest ${s.nothingElseMoved ?? "-"}`);
  if (done.length === all.length) {
    const metaFile = path.join(dir, "run.json");
    const meta = JSON.parse(readFileSync(metaFile, "utf8"));
    if (!meta.recorded) {
      const groups = {};
      for (const s of done) { groups[s.group] = groups[s.group] ?? [0, 0]; groups[s.group][1] += 1; if (s.pass) groups[s.group][0] += 1; }
      appendFileSync(history, JSON.stringify({ run: id, tag: meta.tag, started: meta.started, finished: new Date().toISOString(),
        judgeModel: meta.judgeModel, passed, cases: all.length, groups }) + "\n");
      meta.recorded = true;
      writeFileSync(metaFile, JSON.stringify(meta, null, 2));
      console.log(`recorded in ${path.relative(repo, history)}`);
    }
  }
}

if (command === "run") await commandRun();
else if (command === "report") report(argv[1]);
else {
  console.error("usage: followup.mjs run [--tag ...] [--run <id>] [--cases a,b] [--minutes N] [--no-build] | report [<run>]");
  process.exit(2);
}
