#!/usr/bin/env node
// Every video tool an agent calls lands as ONE undo step
// (docs/design/agent-mcp.md, slice 4).
//
// Drives the probe through the MCP bridge exactly as an agent does: a new
// video from two short recordings, then a clip added, a cut, a ripple trim, a
// clip moved, a transition, a title page in front of a clip, the recommended
// zooms, and an MP4 written. Each edit is checked the way
// agent-commands-drill.mjs checks a command: the document changed, one undo
// puts it back exactly, and redo puts the edit back.
//
//   Scripts/agent-video-drill.mjs
//
// The recordings are the two newest short ones in History that kept their
// clicks (a .photonzpointer beside them), COPIED into a scratch folder with
// their clicks, so nothing in History is touched. Needs the probe
// (Scripts/build-app.sh --probe); the bridge starts it in the background.
import { spawn } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const scratch = "/tmp/photonz-agent-video-drill";
rmSync(scratch, { recursive: true, force: true });
mkdirSync(scratch, { recursive: true });

const bridge = spawn(path.join(repo, "Scripts/photonz-mcp.sh"), [], {
  env: { ...process.env, PHOTONZ_APP: "probe" },
  stdio: ["pipe", "pipe", "inherit"],
});
let buffered = "";
const waiting = new Map();
let nextID = 1;
bridge.stdout.on("data", (chunk) => {
  buffered += chunk;
  let newline;
  while ((newline = buffered.indexOf("\n")) >= 0) {
    const line = buffered.slice(0, newline);
    buffered = buffered.slice(newline + 1);
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    waiting.get(message.id)?.(message);
    waiting.delete(message.id);
  }
});

function rpc(method, params, patience = 60_000) {
  const id = nextID++;
  bridge.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${method} ${params?.name ?? ""} timed out`)), patience);
    waiting.set(id, (message) => { clearTimeout(timer); resolve(message); });
  });
}

async function tool(name, args = {}, patience) {
  const answer = await rpc("tools/call", { name, arguments: args }, patience);
  if (answer.error) return { error: answer.error.message };
  const text = answer.result?.content?.find((part) => part.type === "text")?.text ?? "";
  let json;
  try { json = JSON.parse(text); } catch { json = undefined; }
  return { refused: answer.result?.isError === true, text, json };
}

async function must(name, args, patience) {
  const answer = await tool(name, args, patience);
  if (answer.error || answer.refused) throw new Error(`${name} ${JSON.stringify(args)}: ${answer.error ?? answer.text}`);
  return answer.json ?? answer.text;
}

async function read(document) {
  const read = await must("read_document", { document });
  delete read.canUndo; delete read.canRedo; delete read.playheadSeconds;
  return read;
}

const results = [];

/** Runs `name`, checks the document changed, undoes once, checks it is as it was, and redoes. */
async function oneStep(document, name, args, changed = () => true) {
  try {
    const before = JSON.stringify(await read(document));
    const answer = await must(name, { document, ...args }, 600_000);
    const afterRead = await read(document);
    const after = JSON.stringify(afterRead);
    if (after === before) return results.push({ name, ok: false, why: "the document did not change" }), answer;
    const looked = changed(afterRead, answer);
    if (looked !== true) return results.push({ name, ok: false, why: looked }), answer;
    await must("undo", { document });
    const undone = JSON.stringify(await read(document));
    if (undone !== before) return results.push({ name, ok: false, why: "one undo did not put it back" }), answer;
    await must("redo", { document });
    const redone = JSON.stringify(await read(document));
    if (redone !== after) return results.push({ name, ok: false, why: "redo did not put the edit back" }), answer;
    results.push({ name, ok: true, why: "one undo step" });
    return answer;
  } catch (error) {
    results.push({ name, ok: false, why: String(error.message ?? error) });
    return undefined;
  }
}

// In time order: read_document lists a track's clips top of the stack first.
const clipsOf = (doc) => (doc.tracks ?? []).filter((track) => track.kind === "video").flatMap((track) => track.clips)
  .sort((a, b) => a.inSeconds - b.inSeconds);

// Two short recordings that kept their clicks, copied with them.
const history = path.join(homedir(), "Pictures/Screenshots");
const recordings = readdirSync(history)
  .filter((name) => name.endsWith(".mp4") && existsSync(path.join(history, name.replace(/\.mp4$/, ".photonzpointer"))))
  .map((name) => ({ name, at: statSync(path.join(history, name)).mtimeMs, bytes: statSync(path.join(history, name)).size }))
  .filter((file) => file.bytes < 30_000_000)
  .sort((a, b) => b.at - a.at)
  .slice(0, 2);
if (recordings.length < 2) {
  console.log("!! This drill needs two short recordings with clicks in History (~/Pictures/Screenshots).");
  process.exit(2);
}
const files = recordings.map(({ name }, index) => {
  const file = path.join(scratch, `clip-${index + 1}.mp4`);
  copyFileSync(path.join(history, name), file);
  copyFileSync(path.join(history, name.replace(/\.mp4$/, ".photonzpointer")), file.replace(/\.mp4$/, ".photonzpointer"));
  return file;
});

try {
  // new_video: the clips land as one step on top of the empty video.
  const made = await must("new_video", { clips: files.map((file) => ({ path: file })) }, 120_000);
  const document = made.video.id;
  const first = await read(document);
  const clips = made.clips;
  const sized = made.video.width > 1920;
  results.push({ name: "new_video", ok: clips.length === 2 && sized && clips[1].inSeconds === clips[0].outSeconds,
                 why: `${clips.length} clips end to end, frame ${made.video.width} x ${made.video.height}` });
  await must("undo", { document });
  const emptied = clipsOf(await read(document)).length;
  await must("redo", { document });
  results.push({ name: "new_video undo", ok: emptied === 0 && clipsOf(await read(document)).length === 2,
                 why: `one undo left ${emptied} clips, redo put them back` });

  await oneStep(document, "add_clip", { path: files[0] },
    (doc) => clipsOf(doc).length === 3 && clipsOf(doc)[2].inSeconds === clipsOf(doc)[1].outSeconds
      || `clips: ${JSON.stringify(clipsOf(doc).map((c) => [c.inSeconds, c.outSeconds]))}`);

  let doc = await read(document);
  const [a, b, c] = clipsOf(doc);
  const mid = Math.round(((a.inSeconds + a.outSeconds) / 2) * 1000) / 1000;
  await oneStep(document, "cut", { seconds: mid, clip: a.layer },
    (after) => clipsOf(after)[0].pieces === 2 || "the clip was not in two pieces");

  await oneStep(document, "trim", { clip: b.layer, fromSeconds: 0.5, toSeconds: 2.5, ripple: true },
    (after) => {
      const [, trimmed, next] = clipsOf(after);
      return (Math.abs(trimmed.outSeconds - trimmed.inSeconds - 2) < 0.05 && Math.abs(next.inSeconds - trimmed.outSeconds) < 0.01)
        || `trimmed ${trimmed.inSeconds}-${trimmed.outSeconds}, next at ${next.inSeconds}`;
    });

  doc = await read(document);
  const last = clipsOf(doc)[2];
  await oneStep(document, "move_clip", { clip: last.layer, seconds: last.inSeconds + 1 },
    (after) => Math.abs(clipsOf(after)[2].inSeconds - last.inSeconds - 1) < 0.01 || "it did not move a second");
  const overlap = await tool("move_clip", { document, clip: last.layer, seconds: 0 });
  results.push({ name: "move_clip over a clip", ok: overlap.refused === true && /land over/.test(overlap.text), why: overlap.text });
  await must("undo", { document });

  doc = await read(document);
  const between = doc.cuts.find((cut) => cut.from !== cut.to);
  await oneStep(document, "set_transition", { seconds: between.atSeconds, kind: "dipToBlack", lengthSeconds: 0.4 },
    (after) => after.cuts.find((cut) => Math.abs(cut.atSeconds - between.atSeconds) < 0.06)?.transition?.kind === "dipToBlack"
      || "no dip to black on the cut");
  const dissolve = await tool("set_transition", { document, seconds: between.atSeconds, kind: "dissolve" });
  results.push({ name: "set_transition refused", ok: !dissolve.refused || /can take/.test(dissolve.text),
                 why: dissolve.refused ? dissolve.text : "a dissolve fitted" });
  if (!dissolve.refused) await must("undo", { document });

  const titles = await must("list_titles", { document });
  doc = await read(document);
  const firstClip = clipsOf(doc)[0];
  await oneStep(document, "add_title", { clip: firstClip.layer, text: "Case 1", subtitle: "Signing in" },
    (after, answer) => {
      const words = (answer?.parts ?? []).map((part) => part.text);
      const moved = clipsOf(after).find((clip) => clip.layer === firstClip.layer);
      return (words.includes("Case 1") && words.includes("Signing in") && moved.inSeconds > firstClip.inSeconds)
        || `words ${JSON.stringify(words)}, clip at ${moved?.inSeconds}`;
    });
  results.push({ name: "list_titles", ok: titles.titlePage?.length > 0, why: `${titles.titlePage?.length} page styles` });

  const recommended = await must("recommended_zooms", { document });
  const offered = recommended.reduce((sum, clip) => sum + clip.recommended.length, 0);
  results.push({ name: "recommended_zooms", ok: offered > 0, why: `${offered} zooms over ${recommended.length} recordings` });
  await oneStep(document, "apply_zooms", {},
    (after) => clipsOf(after).some((clip) => clip.zooms > 0) || "no clip carries a zoom");

  const movie = path.join(scratch, "drill.mp4");
  const wrote = await must("export", { document, format: "mp4", path: movie, size: "720p", quality: "standard" }, 600_000);
  const header = existsSync(movie) ? readFileSync(movie).subarray(4, 8).toString() : "";
  results.push({ name: "export mp4", ok: header === "ftyp" && wrote.height === 720,
                 why: `${wrote.bytes} bytes, ${wrote.width} x ${wrote.height}, ${wrote.seconds}s` });
} catch (error) {
  results.push({ name: "drill", ok: false, why: String(error.message ?? error) });
}

bridge.stdin.end();
bridge.kill();
for (const result of results) console.log(`${result.ok ? "ok    " : "FAILED"}  ${result.name.padEnd(24)} ${result.why}`);
const failed = results.filter((result) => !result.ok).length;
console.log(`\n${results.length - failed} of ${results.length} video checks passed${failed ? `; ${failed} did not` : ""}.`);
process.exit(failed ? 1 : 0);
