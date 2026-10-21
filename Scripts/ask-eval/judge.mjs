// The judge: a strong model that can see, and did not make the picture, scores
// it against the fixed rubric (rubric.md) and names a drawing blind
// (naming.md). The same model and prompt every run, three runs, the median.
// Dev tooling only: nothing here ships in the app.
import { spawn } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createHash } from "node:crypto";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
export const JUDGE_MODEL = process.env.ASK_EVAL_JUDGE_MODEL ?? "claude-opus-5-5";
export const RUBRIC = readFileSync(path.join(here, "rubric.md"), "utf8");
const NAMING = readFileSync(path.join(here, "naming.md"), "utf8");
/// The extra line an illustration is judged on (a case with "crafted": true),
/// added to the rubric for those cases only, so every other case is asked
/// exactly what it was asked before.
export const CRAFTED = readFileSync(path.join(here, "rubric-crafted.md"), "utf8").trim();
/// Which rubric scored a run: a run scored by another rubric is not compared.
export const RUBRIC_ID = createHash("sha256").update(RUBRIC + NAMING + CRAFTED + JUDGE_MODEL).digest("hex").slice(0, 8);
export const LINES = ["clean", "typography", "aligned", "designed", "didWhatWasAsked", "crafted"];

/// The rubric for one case: with the crafted line for an illustration.
export function rubricFor({ crafted }) {
  if (!crafted) return RUBRIC;
  return RUBRIC.replace("\nRead the picture at", `${CRAFTED}\n\nRead the picture at`)
    .replace('"didWhatWasAsked": n,', '"didWhatWasAsked": n, "crafted": n,');
}

/// Runs a command with a time limit, killing its whole process group when it
/// runs over, so nothing is left behind.
export function run(command, args, { cwd, timeoutMS, env, onLine } = {}) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd, env: env ?? process.env, detached: true, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "", stderr = "", partial = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      if (!onLine) return;
      partial += chunk;
      let at;
      while ((at = partial.indexOf("\n")) >= 0) { onLine(partial.slice(0, at)); partial = partial.slice(at + 1); }
    });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      try { process.kill(-child.pid, "SIGTERM"); } catch {}
      setTimeout(() => { try { process.kill(-child.pid, "SIGKILL"); } catch {} }, 3000);
    }, timeoutMS ?? 120_000);
    child.on("close", (code) => { clearTimeout(timer); resolve({ code, stdout, stderr, timedOut }); });
  });
}

/// One look by the model at one picture, answered as one line of JSON.
async function ask(picture, prompt) {
  const scratch = mkdtempSync(path.join(os.tmpdir(), "ask-eval-judge-"));
  try {
    const copy = path.join(scratch, "picture.png");
    copyFileSync(picture, copy);
    const text = prompt.replaceAll("{{picture}}", copy);
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const answer = await run("claude", [
        "-p", "--model", JUDGE_MODEL, "--tools", "Read", "--allowedTools", "Read",
        "--setting-sources", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
        "--no-session-persistence", "--output-format", "json", text,
      ], { cwd: scratch, timeoutMS: 150_000 });
      try {
        const result = JSON.parse(answer.stdout).result ?? "";
        const json = result.match(/\{[\s\S]*\}/);
        if (json) return JSON.parse(json[0]);
      } catch {}
    }
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

/// The rubric, `runs` times at once: each line's median, and their mean.
export async function judgePicture({ picture, request, context, runs = 3, crafted = false }) {
  const prompt = rubricFor({ crafted }).replaceAll("{{request}}", request)
    .replaceAll("{{context}}", context ? `It was made on ${context}; judge what was added to it, not the picture underneath.` : "");
  const answers = (await Promise.all(Array.from({ length: runs }, () => ask(picture, prompt)))).filter(Boolean);
  if (!answers.length) return { score: null, lines: {}, why: "the judge gave no answer", answers };
  const lines = {};
  for (const line of LINES) {
    if (line === "crafted" && !crafted) continue;
    const values = answers.map((a) => a[line]);
    // A line every answer left null (typography on a wordless drawing) is out.
    lines[line] = values.every((v) => v === null || v === undefined) ? null : median(values.map((v) => (v === null ? undefined : Number(v))));
  }
  const counted = Object.values(lines).filter((v) => v !== null);
  const score = Math.round(counted.reduce((s, v) => s + v, 0) / counted.length * 10) / 10;
  // Every look is kept, so how much the judge wavers on a picture can be read.
  return { score, lines, why: answers.map((a) => a.why).filter(Boolean), answers: answers.length,
           looks: answers.map((a) => Object.fromEntries(LINES.map((l) => [l, a[l] ?? null]))) };
}

/// The drawing named with no hint, `runs` times: how many named it right.
export async function nameBlind({ picture, names, runs = 3 }) {
  const answers = await Promise.all(Array.from({ length: runs }, () => ask(picture, NAMING)));
  const said = answers.map((a) => String(a?.name ?? "").trim());
  const right = said.filter((s) => names.some((n) => new RegExp(`\\b${n}(s|es)?\\b`, "i").test(s)));
  return { score: Math.round(10 * right.length / runs * 10) / 10, said, right: right.length, of: runs };
}
