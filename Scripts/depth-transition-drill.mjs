#!/usr/bin/env node
// The reel that showed the 3D transitions slamming over the picture and
// spinning through black (task 3d-transitions-ease-in-and-out-of-the-picture-in,
// queue/audits/2026-11-26-sizzle-intake/README.md), rebuilt in the probe through
// the MCP bridge exactly as an agent builds it, then photographed and exported.
//
//   Scripts/depth-transition-drill.mjs [out-dir]
//
// A title page, then six recordings (the reference edit's footage), each three
// seconds, with every 3D transition on a cut at its usual length (0.8 s): push
// in depth, cube, swing, flip, doorway, revolve. The clip the swing arrives on
// is framed and tilted the way the intake framed it (1400x905 at 260,140,
// corners 24, shadow, swing -14, tip 6).
//
// Writes, in out-dir (default /tmp/photonz-depth-drill):
//   <kind>.png       a contact sheet of the move, 12 frames across it
//   reel.mp4         the whole edit exported at 1080p
//   cuts.json        where each cut is, for measuring the export
//
// UNFRAMED=1 leaves every clip full frame. NO_EXPORT=1 skips the export.
// KINDS=cube,flip,... puts those kinds on the cuts in that order (the swing
// must be among them unless UNFRAMED). TITLE_STYLE names the title page style.
//
// Needs the probe (Scripts/probe-app.sh); the bridge starts it in the
// background. Quit it after with Scripts/probe-app.sh --quit.
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import os from "node:os";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = process.argv[2] ?? "/tmp/photonz-depth-drill";
mkdirSync(out, { recursive: true });

const footage = path.join(os.homedir(), "Library/Caches/Photonz Reference Edit/footage v1");
const recordings = [1, 2, 3, 4, 1, 2].map((n) => path.join(footage, `Reference Recording ${n}.mov`));
for (const file of new Set(recordings)) {
  if (!existsSync(file)) {
    console.error(`missing ${file}: run Scripts/perf/reference-edit.sh 6 once to fetch the footage`);
    process.exit(2);
  }
}

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

function rpc(method, params, patience = 120_000) {
  const id = nextID++;
  bridge.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${method} ${params?.name ?? ""} timed out`)), patience);
    waiting.set(id, (message) => { clearTimeout(timer); resolve(message); });
  });
}

async function must(name, args = {}, patience) {
  const answer = await rpc("tools/call", { name, arguments: args }, patience);
  const content = answer.result?.content ?? [];
  const text = content.find((part) => part.type === "text")?.text ?? "";
  if (answer.error || answer.result?.isError) {
    throw new Error(`${name} ${JSON.stringify(args)}: ${answer.error?.message ?? text}`);
  }
  const image = content.find((part) => part.type === "image")?.data;
  let json;
  try { json = JSON.parse(text); } catch { json = undefined; }
  return { json, text, image };
}

const kinds = (process.env.KINDS ?? "pushInDepth,cube,swing,flip,doorway,revolve").split(",");

try {
  await rpc("initialize", { protocolVersion: "2025-03-26", capabilities: {},
                            clientInfo: { name: "depth-transition-drill", version: "1" } });
  bridge.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

  const made = await must("new_video", { width: 1920, height: 1080,
                                         clips: recordings.map((file) => ({ path: file })) }, 300_000);
  const document = made.json?.video?.id ?? made.json?.document ?? made.json?.id;
  if (!document) throw new Error(`new_video answered ${made.text}`);
  console.log(`document ${document}`);

  // The clips on V1 in time order, by layer id.
  const clipsOf = (doc) => (doc.tracks?.[0]?.clips ?? []).filter((clip) => clip.kind === "clip")
    .sort((a, b) => a.inSeconds - b.inSeconds).map((clip) => ({ id: clip.layer, inSeconds: clip.inSeconds }));
  let read = (await must("read_document", { document })).json;
  let clips = clipsOf(read);
  if (clips.length !== recordings.length) throw new Error(`expected ${recordings.length} clips, read ${clips.length}`);
  // Three seconds of each, from 5 s in, so every cut has spare either side.
  for (const clip of clips) {
    await must("trim", { document, clip: clip.id, fromSeconds: 5, toSeconds: 8, ripple: true });
  }
  read = (await must("read_document", { document })).json;
  clips = clipsOf(read);
  await must("add_title", { document, kind: "titlePage", text: "Ghoztty",
                            ...(process.env.TITLE_STYLE ? { style: process.env.TITLE_STYLE } : {}),
                            subtitle: "The terminal that sees everything", clip: clips[0].id });
  read = (await must("read_document", { document })).json;
  const cuts = (read.cuts ?? []).map((cut) => cut.atSeconds).sort((a, b) => a - b);
  if (cuts.length < kinds.length) throw new Error(`only ${cuts.length} cuts: ${JSON.stringify(read.cuts)}`);
  const placed = [];
  for (const [index, kind] of kinds.entries()) {
    const seconds = cuts[index];
    await must("set_transition", { document, seconds, kind, lengthSeconds: 0.8 });
    placed.push({ kind, seconds });
  }
  // Frame the clip the swing arrives on, as the intake did (UNFRAMED=1 leaves
  // every clip full frame, to measure each kind between two plain shots).
  read = (await must("read_document", { document })).json;
  clips = clipsOf(read);
  const swingAt = placed.find((entry) => entry.kind === "swing")?.seconds ?? -1;
  const framed = clips.find((clip) => Math.abs(clip.inSeconds - swingAt) < 0.05);
  if (!framed && !process.env.UNFRAMED) throw new Error(`no clip starts at the swing (${swingAt}s)`);
  if (!process.env.UNFRAMED) await must("set_layer", { document, layer: framed.id, x: 260, y: 140, width: 1400, height: 905,
                            cornerRadius: 24, shadow: { radius: 40, y: 20, opacity: 0.5 }, swing: -14, tip: 6 });
  read = (await must("read_document", { document })).json;
  writeFileSync(path.join(out, "read.json"), JSON.stringify(read, null, 2));
  writeFileSync(path.join(out, "cuts.json"), JSON.stringify({ document, placed, framed: framed?.id }, null, 2));

  for (const { kind, seconds } of placed) {
    const sheet = await must("contact_sheet", { document, fromSeconds: seconds - 0.5, toSeconds: seconds + 0.5,
                                                count: 12, columns: 4, cellWidth: 320 }, 300_000);
    if (sheet.image) writeFileSync(path.join(out, `${kind}.png`), Buffer.from(sheet.image, "base64"));
    console.log(`${kind} at ${seconds}s: ${kind}.png`);
  }
  if (!process.env.NO_EXPORT) {
    const file = path.join(out, "reel.mp4");
    await must("export", { document, format: "mp4", path: file, size: "1080p", quality: "standard" }, 600_000);
    console.log(`exported ${file}`);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  bridge.stdin.end();
  bridge.kill();
}
