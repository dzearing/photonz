#!/usr/bin/env node
// Every command an agent names lands as ONE undo step
// (docs/design/agent-mcp.md, the rest of the menu commands).
//
// Drives the probe through the MCP bridge exactly as an agent does: for each
// case it builds what the command needs, reads the document, runs the command
// with run_command, checks the document changed, undoes ONCE, and checks the
// document reads exactly as it did before. A command that landed as two steps
// leaves half of itself behind after one undo, and fails here.
//
//   Scripts/agent-commands-drill.mjs              every case
//   Scripts/agent-commands-drill.mjs rename freeze   cases whose name holds a word
//
// Needs the probe (Scripts/probe-app.sh). It never touches the clipboard: the
// clipboard is the person's, so cut, copy and paste are not run here.
import { spawn } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, rmSync, statSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const scratch = "/tmp/photonz-agent-commands-drill";
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

function rpc(method, params) {
  const id = nextID++;
  bridge.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${method} timed out`)), 60_000);
    waiting.set(id, (message) => { clearTimeout(timer); resolve(message); });
  });
}

/** A tool's answer: its text parsed as JSON where it is JSON, and whether it was refused. */
async function tool(name, args = {}) {
  const answer = await rpc("tools/call", { name, arguments: args });
  if (answer.error) return { error: answer.error.message };
  const text = answer.result?.content?.find((part) => part.type === "text")?.text ?? "";
  let json;
  try { json = JSON.parse(text); } catch { json = undefined; }
  return { refused: answer.result?.isError === true, text, json };
}

async function must(name, args) {
  const answer = await tool(name, args);
  if (answer.error || answer.refused) throw new Error(`${name} ${JSON.stringify(args)}: ${answer.error ?? answer.text}`);
  return answer.json ?? answer.text;
}

const run = (document, command, args = {}) => tool("run_command", { document, command, arguments: args });
const mustRun = async (document, command, args = {}) => {
  const answer = await run(document, command, args);
  if (answer.refused || answer.error) throw new Error(`${command}: ${answer.error ?? answer.text}`);
  return answer.json;
};

/** The document as read_document gives it, less what an undo does not put back. */
async function read(document) {
  const read = await must("read_document", { document });
  delete read.canUndo; delete read.canRedo; delete read.playheadSeconds;
  return JSON.stringify(read);
}

function layers(read, kind) {
  const all = [];
  const walk = (list) => { for (const layer of list ?? []) { all.push(layer); walk(layer.children); } };
  walk(read.layers);
  for (const track of read.tracks ?? []) walk(track.clips);
  return kind ? all.filter((layer) => layer.kind === kind) : all;
}

// MARK: Documents

async function picture() {
  const made = await must("new_picture", { width: 800, height: 600 });
  const document = made.document ?? made.id;
  const box = await must("add_shape", { document, shape: "rectangle", frame: { x: 60, y: 60, width: 200, height: 120 }, fill: "#3366FF" });
  const other = await must("add_shape", { document, shape: "ellipse", frame: { x: 320, y: 60, width: 120, height: 120 }, fill: "#FF6633" });
  const text = await must("add_text", { document, text: "Hello there", x: 80, y: 300, fontSize: 32 });
  const arrow = await must("add_shape", { document, shape: "arrow", from: { x: 500, y: 400 }, to: { x: 700, y: 500 } });
  const curve = await must("add_path", { document, points: [{ x: 60, y: 520 }, { x: 300, y: 440 }, { x: 560, y: 540 }] });
  return { document, box: box.layer, other: other.layer, text: text.layer, arrow: arrow.layer, curve: curve.layer };
}

async function talk() {
  const sample = [path.join(homedir(), "Library/Caches/Photonz/Tutorials/Sample Talk.mp4"),
                  path.join(homedir(), "Library/Caches/Photonz/Tutorials/videoTalk/Sample Talk.mp4")]
    .find((file) => existsSync(file));
  if (!sample) throw new Error("no Sample Talk.mp4 yet: run a captions walk once to write it");
  const file = path.join(scratch, `talk-${nextID}.mp4`);
  copyFileSync(sample, file);
  const opened = await must("open_document", { path: file });
  const document = opened.document ?? opened.id;
  const doc = JSON.parse(await read(document));
  const clip = layers(doc).find((layer) => layer.kind === "clip" || layer.kind === "recording" || layer.kind === "video")
    ?? doc.tracks?.[0]?.clips?.[0];
  return { document, clip: clip?.id, track: doc.tracks?.[0]?.id, doc };
}

/** A picture whose two shapes were grouped and made a component. */
async function component() {
  const p = await picture();
  await mustRun(p.document, "group", { layers: [p.box, p.other] });
  const group = layers(JSON.parse(await read(p.document)), "group")[0];
  await mustRun(p.document, "make_component", { layers: [group.id] });
  const copy = layers(JSON.parse(await read(p.document))).find((layer) => layer.component || layer.kind === "component");
  return { ...p, copy: copy?.id ?? group.id };
}

// MARK: The cases

/** Each case: a name, how to build what it needs, then the call it checks. */
const cases = [
  ["rename_layer", picture, (p) => ["rename_layer", { layers: [p.box], name: "Card" }]],
  ["lock_layer", picture, (p) => ["lock_layer", { layers: [p.box], on: true }]],
  ["flip_horizontal", picture, (p) => ["flip_horizontal", { layers: [p.text] }]],
  ["flip_vertical", picture, (p) => ["flip_vertical", { layers: [p.box, p.arrow] }]],
  ["add_effect", picture, (p) => ["add_effect", { layers: [p.box], kind: "shadow" }]],
  ["remove_effect", async () => {
    const p = await picture();
    await mustRun(p.document, "add_effect", { layers: [p.box], kind: "glow" });
    return p;
  }, (p) => ["remove_effect", { layers: [p.box], index: 0 }]],
  ["set_arrow_style", picture, (p) => ["set_arrow_style", { layers: [p.arrow], style: "handDrawn" }]],
  ["turn_into_path", picture, (p) => ["turn_into_path", { layers: [p.box] }]],
  ["turn_into_picture", picture, (p) => ["turn_into_picture", { layers: [p.text] }]],
  ["put_text_on_path", picture, (p) => ["put_text_on_path", { layers: [p.text, p.curve] }]],
  ["canvas_size", picture, (p) => ["canvas_size", { width: 1000, height: 700, anchor: "topLeft" }]],
  ["resize_image", picture, (p) => ["resize_image", { width: 400, height: 300 }]],
  ["new_frame", picture, (p) => ["new_frame", { width: 390, height: 844 }]],
  ["show_columns", async () => {
    const p = await picture();
    await mustRun(p.document, "new_frame", { width: 390, height: 844 });
    const frame = layers(JSON.parse(await read(p.document)), "frame")[0];
    return { ...p, frame: frame?.id };
  }, (p) => ["show_columns", { layers: [p.frame], on: true }]],
  ["in_front_of_the_rest", async () => {
    const p = await picture();
    await mustRun(p.document, "stack_selection", { layers: [p.box, p.other] });
    return p;
  }, (p) => ["in_front_of_the_rest", { layers: [p.box], on: true }]],
  ["add_variant", async () => {
    const p = await component();
    await mustRun(p.document, "edit_original", { layers: [p.copy] });
    const original = layers(JSON.parse(await read(p.document)), "component")[0];
    return { ...p, original: original?.id };
  }, (p) => ["add_variant", { layers: [p.original] }]],
  ["edit_original", component, (p) => ["edit_original", { layers: [p.copy] }], "done_editing_original"],
  ["fill_the_stack", async () => {
    const p = await picture();
    await mustRun(p.document, "stack_selection", { layers: [p.box, p.other] });
    const stack = layers(JSON.parse(await read(p.document)), "group")[0];
    await must("set_layer", { document: p.document, layer: stack.id, width: 700 });
    return p;
  }, (p) => ["fill_the_stack", { layers: [p.box], on: true }]],
  ["make_alternatives", async () => {
    const p = await component();
    await mustRun(p.document, "edit_original", { layers: [p.copy] });
    const inside = layers(JSON.parse(await read(p.document))).filter((layer) => layer.kind !== "group"
      && layer.kind !== "component" && layer.kind !== "frame");
    return { ...p, inside: inside.slice(0, 2).map((layer) => layer.id) };
  }, (p) => ["make_alternatives", { layers: p.inside }]],
  ["bring_nearer", picture, (p) => ["bring_nearer", { layers: [p.box] }]],
  ["send_further", picture, (p) => ["send_further", { layers: [p.box] }]],
  ["reshuffle_arrows", async () => {
    const p = await picture();
    await mustRun(p.document, "set_arrow_style", { layers: [p.arrow], style: "handDrawn" });
    return p;
  }, (p) => ["reshuffle_arrows", { layers: [p.arrow] }]],
  ["surface_behind", async () => {
    const p = await picture();
    await mustRun(p.document, "stack_selection", { layers: [p.box, p.other] });
    return p;
  }, (p) => ["surface_behind", { layers: [p.box], on: true }]],

  ["rename_clip", talk, (t) => ["rename_clip", { layers: [t.clip], name: "The talk" }]],
  ["rename_track", talk, (t) => ["rename_track", { track: t.track, name: "Talk" }]],
  ["freeze_frame", talk, (t) => ["freeze_frame", { seconds: 2, layers: [t.clip], milliseconds: 1500 }]],
  ["insert_title", talk, () => ["insert_title", { seconds: 1, kind: "titlePage", preset: "?" }]],
  ["animate_property", talk, (t) => ["animate_property", { seconds: 1, layers: [t.clip], property: "Opacity" }]],
  ["stop_animating", async () => {
    const t = await talk();
    await mustRun(t.document, "animate_property", { seconds: 1, layers: [t.clip], property: "Opacity" });
    return t;
  }, (t) => ["stop_animating", { layers: [t.clip], property: "Opacity" }]],
  ["set_easing", async () => {
    const t = await talk();
    await mustRun(t.document, "animate_property", { seconds: 1, layers: [t.clip], property: "Opacity" });
    await mustRun(t.document, "key_at_playhead", { seconds: 3, layers: [t.clip] });
    return t;
  }, (t) => ["set_easing", { seconds: 2, layers: [t.clip], curve: "Linear" }]],
  ["add_click", talk, (t) => ["add_click", { seconds: 2, layers: [t.clip], x: 400, y: 300 }]],
  ["set_zoom_amount", async () => {
    const t = await talk();
    await mustRun(t.document, "add_zoom", { seconds: 2 });
    return t;
  }, (t) => ["set_zoom_amount", { seconds: 2.5, layers: [t.clip], percent: 250 }]],
  ["delete_zoom", async () => {
    const t = await talk();
    await mustRun(t.document, "add_zoom", { seconds: 2 });
    return t;
  }, (t) => ["delete_zoom", { seconds: 2.5, layers: [t.clip] }]],
  ["section", async () => {
    const t = await talk();
    await mustRun(t.document, "set_in", { seconds: 1 });
    await mustRun(t.document, "set_out", { seconds: 3 });
    return t;
  }, (t) => ["section", { layers: [t.clip], operation: "muteSection" }]],
  ["delete gap", async () => {
    const t = await talk();
    // Lift takes 0:02 to 0:03 out of every track and leaves a gap on V1.
    await mustRun(t.document, "set_in", { seconds: 2 });
    await mustRun(t.document, "set_out", { seconds: 3 });
    await mustRun(t.document, "lift");
    return t;
  }, (t) => ["delete", { seconds: 2.5, track: t.track }]],
  ["import_media", talk, () => ["import_media", { path: path.join(repo, "Scripts/playtest/fixtures/Hero banner.png") }]],
  ["add_media_at_playhead", talk, () => ["add_media_at_playhead", {
    seconds: 1, path: path.join(repo, "Scripts/playtest/fixtures/Noisy voice recording 1280x800.mp4") }]],
];

// Caption words need captions, which take the speech reader a little while.
const captionCases = [
  ["edit_caption_word", { text: "Howdy" }],
  ["split_caption_word", {}],
  ["merge_caption_word", {}],
  ["delete_caption_word", {}],
  ["move_word_to_next_line", {}],
  ["join_with_next_line", {}],
];

// MARK: Running

/** Where two reads part, with a little either side. */
function firstDifference(a, b) {
  let at = 0;
  while (at < a.length && a[at] === b[at]) at++;
  return `before …${a.slice(Math.max(0, at - 60), at + 60)}… after …${b.slice(Math.max(0, at - 60), at + 60)}…`;
}

const asked = process.argv.slice(2);
const wanted = (name) => asked.length === 0 || asked.some((word) => name.includes(word));
const results = [];

/** `back` is the command that leaves what `command` opened, where it opens
 *  a place rather than making an edit (Edit Original), in place of an undo. */
async function check(name, document, command, args, back) {
  const before = await read(document);
  const ran = await run(document, command, args);
  if (ran.refused || ran.error) { results.push({ name, ok: false, why: `refused: ${ran.error ?? ran.text}` }); return; }
  if (!ran.json?.changed) { results.push({ name, ok: false, why: "ran but changed nothing" }); return; }
  await new Promise((resolve) => setTimeout(resolve, 300));
  if (back) await mustRun(document, back);
  else await must("undo", { document, steps: 1 });
  const after = await read(document);
  const how = back ?? "one undo";
  results.push(after === before
    ? { name, ok: true, why: `changed, and ${how} put it back exactly` }
    : { name, ok: false, why: `${how} did not put it back${back ? "" : ": it landed as more than one step"}`
        + ` (first difference: ${firstDifference(before, after)})` });
}

await rpc("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "drill", version: "1" } });

for (const [name, build, call, back] of cases) {
  if (!wanted(name)) continue;
  try {
    const built = await build();
    let [command, args] = call(built);
    if (command === "insert_title") {
      const refused = await run(built.document, command, args);
      const styles = refused.text.match(/styles are (.*)\./)?.[1]?.split(", ") ?? [];
      args = { ...args, preset: styles[0] };
    }
    if (command === "export_captions" || command === "export_sound") {
      const ran = await run(built.document, command, args);
      const wrote = existsSync(args.path) && statSync(args.path).size > 0;
      results.push({ name, ok: wrote && !ran.refused, why: wrote ? "wrote the file" : `no file: ${ran.text}` });
      continue;
    }
    await check(name, built.document, command, args, back);
  } catch (error) {
    results.push({ name, ok: false, why: String(error.message ?? error) });
  }
}

if (captionCases.some(([name]) => wanted(name)) || wanted("export")) {
  try {
    const t = await talk();
    await mustRun(t.document, "add_captions");
    // read_document lists the caption lines, each word with when it starts.
    const lines = (doc) => doc.captions ?? [];
    let cues = [];
    for (let tries = 0; tries < 60 && cues.length < 2; tries++) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      cues = lines(JSON.parse(await read(t.document)));
    }
    if (cues.length < 2) throw new Error(`${cues.length} caption lines were written in a minute`);
    // Inside the first word of the first line that has two words or more.
    const line = cues.find((cue) => cue.words.length >= 2) ?? cues[0];
    const at = line.words[0].atSeconds + 0.05;
    for (const [name, args] of captionCases) {
      if (!wanted(name)) continue;
      await check(name, t.document, name, { seconds: at, ...args });
    }
    if (wanted("export")) {
      const srt = path.join(scratch, "talk.srt");
      const ran = await run(t.document, "export_captions", { format: "srt", path: srt });
      const wrote = existsSync(srt) && statSync(srt).size > 0;
      results.push({ name: "export_captions", ok: wrote, why: wrote ? "wrote the subtitle file" : ran.text });
      const mix = path.join(scratch, "talk.m4a");
      const sound = await run(t.document, "export_sound", { path: mix });
      const mixed = existsSync(mix) && statSync(mix).size > 0;
      results.push({ name: "export_sound", ok: mixed, why: mixed ? "wrote the sound file" : sound.text });
    }
  } catch (error) {
    results.push({ name: "captions", ok: false, why: String(error.message ?? error) });
  }
}

bridge.stdin.end();
bridge.kill();
for (const result of results) console.log(`${result.ok ? "ok    " : "FAILED"}  ${result.name.padEnd(24)} ${result.why}`);
const failed = results.filter((result) => !result.ok).length;
console.log(`\n${results.length - failed} of ${results.length} commands landed as one undo step${failed ? `; ${failed} did not` : ""}.`);
process.exit(failed ? 1 : 0);
