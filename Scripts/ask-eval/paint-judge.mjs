#!/usr/bin/env node
// The brush epic's painting bar (queue/tasks/p1-high/a-brush-tool-paints-
// with-realistic-charcoal-chal.json, item 9): two model judges, the larger
// and the mid-size, each look at a painting three times and score whether it
// looks painted and whether it reads as what was asked. Each judge's score is
// the median of its three looks; the bar is met when BOTH judges reach it.
//
//   node Scripts/ask-eval/paint-judge.mjs <picture.png> "<what it should show>" [--painted 8] [--reads 7]
//
// The judges only read the picture: they never see how it was made.
import { spawn } from "node:child_process";
import { copyFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const JUDGES = [
  { name: "judge A", model: process.env.PAINT_JUDGE_A ?? "claude-opus-5-5" },
  { name: "judge B", model: process.env.PAINT_JUDGE_B ?? "claude-sonnet-5-5" },
];
const LOOKS = 3;

export const PROMPT = `Read the picture at {{picture}}. It is meant to be a painting of: {{subject}}.
Score it on two things from 1 to 10, as a strict art teacher would.
- looksPainted: does it look like a real painting made with a brush in a physical medium? 10: it could be a photo of a real painted canvas or paper. 5: brushy, but plainly made by a computer. 1: a digital filter, vector clip art, or a texture laid over flat shapes.
- readsAsSubject: does it plainly show what it is meant to? 10: anyone would name it at a glance, with a clear subject. 1: unrecognisable.
Answer with only JSON: {"looksPainted": n, "readsAsSubject": n, "why": "one sentence"}`;

function run(args, cwd) {
  return new Promise((resolve) => {
    const child = spawn("claude", args, { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    child.stdout.on("data", (d) => { out += d; });
    const timer = setTimeout(() => child.kill("SIGKILL"), 150_000);
    child.on("close", () => { clearTimeout(timer); resolve(out); });
  });
}

async function look(model, picture, subject) {
  const scratch = mkdtempSync(path.join(tmpdir(), "paint-judge-"));
  try {
    const copy = path.join(scratch, "picture.png");
    copyFileSync(picture, copy);
    const text = PROMPT.replaceAll("{{picture}}", copy).replaceAll("{{subject}}", subject);
    const out = await run(["-p", "--model", model, "--tools", "Read", "--allowedTools", "Read",
      "--setting-sources", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
      "--no-session-persistence", "--output-format", "json", text], scratch);
    const result = JSON.parse(out).result ?? "";
    const json = result.match(/\{[\s\S]*\}/);
    return json ? JSON.parse(json[0]) : null;
  } catch {
    return null;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

const median = (values) => {
  const sorted = values.filter((v) => typeof v === "number").sort((a, b) => a - b);
  if (!sorted.length) return null;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

const [picture, subject = "a landscape", ...rest] = process.argv.slice(2);
if (!picture) {
  console.error('usage: paint-judge.mjs <picture.png> "<what it should show>" [--painted 8] [--reads 7]');
  process.exit(2);
}
const flag = (name, fallback) => {
  const at = rest.indexOf(name);
  return at >= 0 ? Number(rest[at + 1]) : fallback;
};
const bar = { painted: flag("--painted", 8), reads: flag("--reads", 7) };
const results = await Promise.all(JUDGES.map(async (judge) => {
  const looks = (await Promise.all(Array.from({ length: LOOKS }, () => look(judge.model, picture, subject)))).filter(Boolean);
  return { ...judge, looks, painted: median(looks.map((l) => l.looksPainted)), reads: median(looks.map((l) => l.readsAsSubject)) };
}));
let met = true;
for (const r of results) {
  console.log(`${r.name} (${r.model}): looks painted ${r.painted}/10, reads as ${subject} ${r.reads}/10 over ${r.looks.length} looks`);
  for (const l of r.looks) console.log(`    ${l.looksPainted}, ${l.readsAsSubject}: ${l.why}`);
  if (!(r.painted >= bar.painted && r.reads >= bar.reads)) met = false;
}
console.log(met ? `MET: both judges at least ${bar.painted} painted and ${bar.reads} reads` : `NOT MET: the bar is ${bar.painted} painted and ${bar.reads} reads from both judges`);
