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
import { sourcesFromTranscript } from "./lookups.mjs";

export const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
export const SKILL_MODEL = process.env.ASK_EVAL_SKILL_MODEL ?? "claude-opus-5-5";

/// The steps that put the case's starting document in front. A video case
/// starts on the sample recording, eight seconds of a file copy
/// (`openSampleRecording`), with the pointer and two clicks a recorder would
/// have kept when it asks for `clicks`, and laid `copies` more times end to
/// end when it asks for those (`prepare` lays them, over the bridge; Ask's
/// walk waits until they are down).
function startSteps(testCase, { waitForCopies = false } = {}) {
  const { sample, clicks, copies } = testCase.start;
  if (sample) {
    if (sample !== "recording") throw new Error(`no sample ${sample}: the one sample is "recording"`);
    const steps = [{ do: "action", action: "openSampleRecording" }, { do: "wait", seconds: 2 }, { do: "action", action: "videoPause" }];
    if (clicks) steps.push({ do: "action", action: "zoomScriptPointerPath" });
    if (copies && waitForCopies) steps.push({ do: "waitFor", condition: "clipsOfOneRecording", value: 1 + copies, timeout: 120 });
    return [...steps, { do: "wait", seconds: 1 }];
  }
  if (testCase.start.open) {
    return [{ do: "open", file: path.resolve(repo, testCase.start.open), width: 1280, height: 840 }, { do: "wait", seconds: 1 }];
  }
  const [width, height] = testCase.start.blank;
  return [{ do: "blank", canvasWidth: width, canvasHeight: height, width: 1280, height: 840 }, { do: "wait", seconds: 1 }];
}

/// Runs a walk and leaves the probe up. Exit 3 is a locked screen, 6 a person
/// at the Mac for a walk that needs it to itself, 4 a crash.
/// A case's own `setup` (a made-up History for a request about the person's
/// recordings) goes into the walk's; a video opens with its tracks showing.
async function walk(dir, name, steps, { clock, build, testCase }) {
  const out = path.join(dir, name);
  const script = path.join(dir, `${name}.json`);
  const setup = { forget: ["all"], ...(testCase.start.sample ? { timelineOpen: true } : {}), ...(testCase.setup ?? {}) };
  writeFileSync(script, JSON.stringify({
    out, seed: "ask-eval: one case of the scored test set (Scripts/ask-eval)", clock,
    setup, steps,
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
/// so the newest document it made wins, then the one in front. A video is
/// photographed as it plays (`playback`).
async function collect(dir, before = []) {
  const bridge = connect();
  try {
    await bridge.start();
    const docs = (await bridge.tool("list_documents")).json ?? [];
    const fresh = docs.filter((d) => !before.includes(d.id) && d.canUndo);
    const pick = fresh.at(-1) ?? docs.find((d) => d.front) ?? docs[0];
    if (!pick) return { error: "no document open" };
    const read = (await bridge.tool("read_document", { document: pick.id })).json;
    if (read.kind === "video") {
      Object.assign(read, { playback: await playback(bridge, pick.id, read, dir) });
    } else {
      const picture = await bridge.tool("render_picture", { document: pick.id, maxSize: 1600 }, 120_000);
      writeFileSync(path.join(dir, "result.png"), Buffer.from(picture.image, "base64"));
    }
    writeFileSync(path.join(dir, "read.json"), JSON.stringify(read, null, 2));
    return { read, picture: path.join(dir, "result.png"), document: pick.id, documents: docs.length };
  } catch (error) {
    return { error: error.message };
  } finally {
    bridge.close();
  }
}

const clock = (s) => `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, "0")}`;

/// A video as it plays, drawn the way export draws it (video_frame): a small
/// frame every quarter second, each marked blank or not (frame-stats.swift),
/// for the rules; and for the judge, result.png, a contact sheet of frames
/// spread across the whole video and at the start, middle and end of every
/// transition, each labelled with its time.
async function playback(bridge, document, read, dir) {
  const length = read.durationSeconds ?? 0;
  const frames = path.join(dir, "frames");
  mkdirSync(frames, { recursive: true });
  const grab = async (seconds, maxSize, name) => {
    const frame = await bridge.tool("video_frame", { document, seconds: Math.round(seconds * 1000) / 1000, maxSize }, 60_000);
    const file = path.join(frames, name);
    writeFileSync(file, Buffer.from(frame.image, "base64"));
    return file;
  };
  const step = Math.max(0.25, length / 160);
  const moments = [];
  for (let t = 0; t < length - 0.01; t += step) moments.push(Math.round(t * 1000) / 1000);
  const small = [];
  for (const t of moments) small.push(await grab(t, 96, `play-${t.toFixed(3)}.png`));
  const stats = small.length ? await run("swift", [path.join(repo, "Scripts/ask-eval/frame-stats.swift"), ...small], { cwd: repo, timeoutMS: 120_000 }) : { code: 0, stdout: "[]" };
  if (stats.code !== 0) throw new Error(`frame-stats: ${stats.stderr.trim().split("\n").pop()}`);
  const marked = JSON.parse(stats.stdout);

  const shown = new Set();
  const spread = Math.max(0.5, length / 24);
  for (let t = 0; t < length - 0.01; t += spread) shown.add(Math.round(t * 10) / 10);
  for (const cut of read.cuts ?? []) {
    if (!cut.transition) continue;
    const half = (cut.transition.seconds ?? 0.5) / 2;
    for (const t of [cut.atSeconds - half, cut.atSeconds, cut.atSeconds + half]) if (t >= 0 && t < length) shown.add(Math.round(t * 100) / 100);
  }
  const sheet = [...shown].sort((a, b) => a - b).filter((t, i, all) => i === 0 || t - all[i - 1] > 0.04);
  // The cuts and their transitions, as the timeline shows them to a person:
  // a dissolve across a cut inside one unbroken recording joins a moment to
  // itself, so no frame can show it.
  const cuts = (read.cuts ?? []).map((c) => `${clock(c.atSeconds)}${c.transition ? ` ${c.transition.kind} ${c.transition.seconds}s` : " plain"}`);
  const args = [path.join(dir, "result.png"), `${read.title ?? "video"} · ${clock(length)} · cuts: ${cuts.join(", ") || "none"}`];
  for (const t of sheet) args.push(await grab(t, 400, `sheet-${t.toFixed(2)}.png`), clock(t));
  const made = await run("swift", [path.join(repo, "Scripts/ask-eval/contact-sheet.swift"), ...args], { cwd: repo, timeoutMS: 180_000 });
  if (made.code !== 0) throw new Error(`contact sheet: ${made.stderr.trim().split("\n").pop()}`);
  return { step, frames: moments.map((seconds, i) => ({ seconds, blank: marked[i]?.blank === true, drawn: marked[i]?.drawn ?? null })), sheet };
}

/// Lays the sample recording `copies` more times end to end after the first,
/// over the bridge, as Add Media at Playhead would: what a case about titles
/// between three clips starts on. Waits for the recording to open first,
/// since Ask's walk is opening it at the same moment.
async function prepare(testCase) {
  const copies = testCase.start.copies ?? 0;
  if (!copies) return null;
  const bridge = connect();
  try {
    const until = Date.now() + 150_000;
    let video;
    while (!video && Date.now() < until) {
      try {
        if (!bridge.started) { await bridge.start(); bridge.started = true; }
        video = ((await bridge.tool("list_documents")).json ?? []).find((d) => d.kind === "video" && d.file);
      } catch {}
      if (!video) await new Promise((r) => setTimeout(r, 1000));
    }
    if (!video) return "the sample recording never opened";
    for (let i = 0; i < copies; i += 1) await bridge.tool("add_clip", { document: video.id, path: video.file });
    return null;
  } catch (error) {
    return `laying the copies down failed: ${error.message}`;
  } finally {
    bridge.close();
  }
}

/// One go of Ask on the case; a go whose Send never started Ask is tried
/// once more, and then left unrun rather than scored as nothing made.
export async function runAsk(testCase, dir, { build }) {
  const first = await runAskOnce(testCase, dir, { build });
  if (first.unrun || first.engine.phase !== "idle") return first;
  await quitProbe();
  const second = await runAskOnce(testCase, dir, { build: false });
  if (second.unrun || second.engine.phase !== "idle") return second;
  await quitProbe();
  return { engine: second.engine, unrun: "Ask never started: the walk's Send did not take, twice" };
}

async function runAskOnce(testCase, dir, { build }) {
  const limit = testCase.timeout ?? 300;
  const steps = [
    ...startSteps(testCase, { waitForCopies: true }),
    { do: "press", control: "Ask" }, { do: "wait", seconds: 0.5 },
    { do: "type", text: testCase.request }, { do: "wait", seconds: 0.3 },
    { do: "press", control: "Ask Send" },
    // Ask starts at once: a Send that did not take is found in seconds, not
    // after the whole limit (two held-out cases sat 300 s idle, 2026-10-20).
    { do: "waitFor", condition: "askPhase", value: "planning|running|ran|stopped", timeout: 15 },
    { do: "waitFor", condition: "askPhase", value: "ran|stopped", timeout: limit },
    { do: "wait", seconds: 0.8 },
    { do: "describe", stage: "ended", note: "where the request ended" },
  ];
  const started = Date.now();
  const [walked, unprepared] = await Promise.all([walk(dir, "ask-walk", steps, { clock: limit + 180, build, testCase }), prepare(testCase)]);
  const ended = walked.log.filter((e) => e.state?.ask).at(-1)?.state.ask;
  const engine = {
    walk: walked.code, said: walked.said,
    phase: ended?.phase ?? null,
    seconds: ended?.planSeconds ?? null,
    wallSeconds: (Date.now() - started) / 1000,
    model: ended?.trace?.find((t) => / model /.test(t))?.match(/model ([^\s,]+)/)?.[1] ?? null,
    steps: ended?.steps ?? [], skipped: ended?.skipped ?? [], says: ended?.says ?? "",
    // Where each drawing came from: stored, template or drawn for the request.
    sources: ended?.sources ?? [],
  };
  if (walked.code === 3 || walked.code === 6) return { engine, unrun: walked.code === 3 ? "screen locked" : "deferred: person at the Mac" };
  if (unprepared) { await quitProbe(); return { engine, unrun: unprepared }; }
  if (engine.phase === "idle") return { engine };
  const got = await collect(dir);
  await quitProbe();
  return { engine, ...got };
}

export async function runSkill(testCase, dir, { build }) {
  const limit = testCase.skillTimeout ?? 360;
  const walked = await walk(dir, "start-walk", startSteps(testCase), { clock: 120, build, testCase });
  if (walked.code !== 0) {
    await quitProbe();
    return { engine: { walk: walked.code, said: walked.said }, unrun: walked.code === 3 ? "screen locked" : walked.code === 6 ? "deferred: person at the Mac" : `the start walk failed (${walked.code})` };
  }
  const unprepared = await prepare(testCase);
  if (unprepared) { await quitProbe(); return { engine: { walk: walked.code }, unrun: unprepared }; }
  let before = [];
  const bridge = connect();
  try { await bridge.start(); before = ((await bridge.tool("list_documents")).json ?? []).map((d) => d.id); } catch {} finally { bridge.close(); }

  const scratch = path.join(dir, "session");
  mkdirSync(scratch, { recursive: true });
  const mcp = path.join(scratch, "mcp.json");
  writeFileSync(mcp, JSON.stringify({ mcpServers: { photonz: { command: path.join(repo, "Scripts/photonz-mcp.sh"), env: { PHOTONZ_APP: "probe" } } } }));
  const where = testCase.start.open || testCase.start.sample ? (testCase.context ?? "a picture") : `a blank ${testCase.start.blank[0]} x ${testCase.start.blank[1]} picture`;
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
    sources: sourcesFromTranscript(lines),
  };
  const got = await collect(dir, before);
  await quitProbe();
  return { engine, ...got };
}

export function transcriptExists(dir) { return existsSync(path.join(dir, "transcript.jsonl")); }
