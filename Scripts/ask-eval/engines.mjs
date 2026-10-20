// The two engines a case runs through, each on the probe at Next defaults:
//
//   ask    the app's own Ask, driven by a walk exactly as a person types it
//   skill  a fresh headless agent session with only the Photonz skill and the
//          Photonz MCP server, the way the agent-skill audit ran (2026-10-19)
//
// Either way the result is read back over the MCP bridge (read_document and
// render_picture), so what is scored is the document the app holds.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { connect } from "./mcp.mjs";
import { run } from "./judge.mjs";

export const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
export const SKILL_MODEL = process.env.ASK_EVAL_SKILL_MODEL ?? "claude-opus-5-5";

/// The steps that put the case's starting document in front.
function startSteps(testCase) {
  if (testCase.start.open) {
    return [{ do: "open", file: path.resolve(repo, testCase.start.open), width: 1280, height: 840 }, { do: "wait", seconds: 1 }];
  }
  const [width, height] = testCase.start.blank;
  return [{ do: "blank", canvasWidth: width, canvasHeight: height, width: 1280, height: 840 }, { do: "wait", seconds: 1 }];
}

/// Runs a walk and leaves the probe up. Exit 3 is a locked screen, 6 a person
/// at the Mac for a walk that needs it to itself, 4 a crash.
async function walk(dir, name, steps, { clock, build }) {
  const out = path.join(dir, name);
  const script = path.join(dir, `${name}.json`);
  writeFileSync(script, JSON.stringify({
    out, seed: "ask-eval: one case of the scored test set (Scripts/ask-eval)", clock,
    setup: { forget: ["all"] }, steps,
  }, null, 2));
  const args = [script, "--keep"];
  if (!build) args.push("--no-build");
  const result = await run(path.join(repo, "Scripts/playtest.sh"), args, { cwd: repo, timeoutMS: (clock + 240) * 1000 });
  writeFileSync(path.join(dir, `${name}.out.txt`), result.stdout + result.stderr);
  let log = [];
  try { log = JSON.parse(readFileSync(path.join(out, "log.json"), "utf8")); } catch {}
  return { code: result.code, log, said: (result.stdout + result.stderr).split("\n").filter((l) => /Verdict|FAILED|COULD NOT|CRASHED|DEFERRED/.test(l)).join(" ") };
}

export async function quitProbe() {
  await run(path.join(repo, "Scripts/probe-app.sh"), ["--quit"], { cwd: repo, timeoutMS: 60_000 });
}

/// The document a run left, read and photographed. Ask works in the document
/// it was asked in; an agent may open a new one (an icon on an icon canvas),
/// so the newest document it made wins, then the one in front.
async function collect(dir, before = []) {
  const bridge = connect();
  try {
    await bridge.start();
    const docs = (await bridge.tool("list_documents")).json ?? [];
    const fresh = docs.filter((d) => !before.includes(d.id) && d.canUndo);
    const pick = fresh.at(-1) ?? docs.find((d) => d.front) ?? docs[0];
    if (!pick) return { error: "no document open" };
    const read = (await bridge.tool("read_document", { document: pick.id })).json;
    writeFileSync(path.join(dir, "read.json"), JSON.stringify(read, null, 2));
    const picture = await bridge.tool("render_picture", { document: pick.id, maxSize: 1600 }, 120_000);
    writeFileSync(path.join(dir, "result.png"), Buffer.from(picture.image, "base64"));
    return { read, picture: path.join(dir, "result.png"), document: pick.id, documents: docs.length };
  } catch (error) {
    return { error: error.message };
  } finally {
    bridge.close();
  }
}

export async function runAsk(testCase, dir, { build }) {
  const limit = testCase.timeout ?? 300;
  const steps = [
    ...startSteps(testCase),
    { do: "press", control: "Ask" }, { do: "wait", seconds: 0.5 },
    { do: "type", text: testCase.request }, { do: "wait", seconds: 0.3 },
    { do: "press", control: "Ask Send" },
    { do: "waitFor", condition: "askPhase", value: "ran|stopped", timeout: limit },
    { do: "wait", seconds: 0.8 },
    { do: "describe", stage: "ended", note: "where the request ended" },
  ];
  const started = Date.now();
  const walked = await walk(dir, "ask-walk", steps, { clock: limit + 60, build });
  const ended = walked.log.filter((e) => e.state?.ask).at(-1)?.state.ask;
  const engine = {
    walk: walked.code, said: walked.said,
    phase: ended?.phase ?? null,
    seconds: ended?.planSeconds ?? null,
    wallSeconds: (Date.now() - started) / 1000,
    model: ended?.trace?.find((t) => / model /.test(t))?.match(/model ([^\s,]+)/)?.[1] ?? null,
    steps: ended?.steps ?? [], skipped: ended?.skipped ?? [], says: ended?.says ?? "",
  };
  if (walked.code === 3 || walked.code === 6) return { engine, unrun: walked.code === 3 ? "screen locked" : "deferred: person at the Mac" };
  const got = await collect(dir);
  await quitProbe();
  return { engine, ...got };
}

export async function runSkill(testCase, dir, { build }) {
  const limit = testCase.skillTimeout ?? 360;
  const walked = await walk(dir, "start-walk", startSteps(testCase), { clock: 120, build });
  if (walked.code !== 0) {
    await quitProbe();
    return { engine: { walk: walked.code, said: walked.said }, unrun: walked.code === 3 ? "screen locked" : walked.code === 6 ? "deferred: person at the Mac" : `the start walk failed (${walked.code})` };
  }
  let before = [];
  const bridge = connect();
  try { await bridge.start(); before = ((await bridge.tool("list_documents")).json ?? []).map((d) => d.id); } catch {} finally { bridge.close(); }

  const scratch = path.join(dir, "session");
  mkdirSync(scratch, { recursive: true });
  const mcp = path.join(scratch, "mcp.json");
  writeFileSync(mcp, JSON.stringify({ mcpServers: { photonz: { command: path.join(repo, "Scripts/photonz-mcp.sh"), env: { PHOTONZ_APP: "probe" } } } }));
  const where = testCase.start.open ? (testCase.context ?? "a picture") : `a blank ${testCase.start.blank[0]} x ${testCase.start.blank[1]} picture`;
  const prompt = `${testCase.request}\n\n(Photonz is open with ${where} in front.)`;
  const lines = [];
  const started = Date.now();
  const session = await run("claude", [
    "-p", "--model", SKILL_MODEL, "--plugin-dir", path.join(repo, "plugin"),
    "--strict-mcp-config", "--mcp-config", mcp,
    "--allowedTools", "mcp__photonz__*", "Skill", "ToolSearch",
    "--disallowedTools", "Write", "Edit", "NotebookEdit", "Bash", "WebFetch", "WebSearch",
    "--setting-sources", "", "--no-session-persistence",
    "--output-format", "stream-json", "--verbose", prompt,
  ], { cwd: scratch, timeoutMS: limit * 1000, onLine: (line) => lines.push(line) });
  writeFileSync(path.join(dir, "transcript.jsonl"), lines.join("\n") + "\n");
  let result = {};
  for (const line of lines) { try { const e = JSON.parse(line); if (e.type === "result") result = e; } catch {} }
  const calls = [];
  for (const line of lines) {
    try { for (const part of JSON.parse(line).message?.content ?? []) if (part.type === "tool_use") calls.push(part.name.replace(/^mcp__[^_]+__/, "")); } catch {}
  }
  const engine = {
    seconds: (Date.now() - started) / 1000, timedOut: session.timedOut, model: SKILL_MODEL,
    turns: result.num_turns ?? null, costUSD: result.total_cost_usd ?? null,
    said: String(result.result ?? "").slice(0, 400), calls: calls.length, skillLoaded: calls.includes("Skill"),
  };
  const got = await collect(dir, before);
  await quitProbe();
  return { engine, ...got };
}

export function transcriptExists(dir) { return existsSync(path.join(dir, "transcript.jsonl")); }
