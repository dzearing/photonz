#!/usr/bin/env node
// Every design-system tool an agent calls lands as ONE undo step
// (docs/design/agent-mcp.md, "Design systems").
//
// Drives the probe through the MCP bridge exactly as an agent does: a new
// picture, a colour and a text style on the Styles shelf, a button built from
// a box and its label, grouped, made a padded row stack, dressed in the
// styles, made a component and placed twice. Each edit is checked the way
// agent-commands-drill.mjs checks a command: the document changed, one undo
// puts it back exactly, and redo puts the edit back. Then the brand colour is
// changed once and both copies follow it.
//
//   Scripts/agent-design-drill.mjs
//
// Writes a picture of the result to /tmp/photonz-agent-design-drill/button.png.
// Needs the probe (Scripts/build-app.sh --probe); the bridge starts it in the
// background, and its window is left open (Scripts/probe-app.sh --quit).
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const scratch = "/tmp/photonz-agent-design-drill";
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
  const content = answer.result?.content ?? [];
  const text = content.find((part) => part.type === "text")?.text ?? "";
  const image = content.find((part) => part.type === "image")?.data;
  let json;
  try { json = JSON.parse(text); } catch { json = undefined; }
  return { refused: answer.result?.isError === true, text, json, image };
}

async function must(name, args, patience) {
  const answer = await tool(name, args, patience);
  if (answer.error || answer.refused) throw new Error(`${name} ${JSON.stringify(args)}: ${answer.error ?? answer.text}`);
  return answer.json ?? answer.text;
}

async function read(document) {
  const read = await must("read_document", { document });
  delete read.canUndo; delete read.canRedo;
  return read;
}

async function styles(document) { return must("list_styles", { document }); }

const results = [];

/** Runs `name`, checks the document changed, undoes once, checks it is as it was, and redoes. */
async function oneStep(document, name, args, changed = () => true) {
  try {
    const state = async () => JSON.stringify([await read(document), await styles(document)]);
    const before = await state();
    const answer = await must(name, { document, ...args });
    const after = await state();
    if (after === before) return results.push({ name, ok: false, why: "the document did not change" }), answer;
    const looked = changed(await read(document), answer, await styles(document));
    if (looked !== true) return results.push({ name, ok: false, why: looked }), answer;
    await must("undo", { document });
    if (await state() !== before) return results.push({ name, ok: false, why: "one undo did not put it back" }), answer;
    await must("redo", { document });
    if (await state() !== after) return results.push({ name, ok: false, why: "redo did not put the edit back" }), answer;
    results.push({ name, ok: true, why: "one undo step" });
    return answer;
  } catch (error) {
    results.push({ name, ok: false, why: String(error.message ?? error) });
    return undefined;
  }
}

const find = (layers, test) => {
  for (const layer of layers) {
    if (test(layer)) return layer;
    const inside = find(layer.children ?? [], test);
    if (inside) return inside;
  }
  return undefined;
};

let document;
try {
  document = (await must("new_picture", { width: 800, height: 400 })).id;

  await oneStep(document, "add_style", { kind: "color", name: "Brand", color: "#5E6AD2" },
    (_, __, shelf) => shelf.colors.some((c) => c.name === "Brand" && c.color === "#5E6AD2") || JSON.stringify(shelf.colors));
  await oneStep(document, "add_style", { kind: "text", name: "Button Label", size: 15, weight: "semibold", color: "#FFFFFF" },
    (_, __, shelf) => shelf.text.some((t) => t.name === "Button Label" && t.size === 15) || JSON.stringify(shelf.text));

  const box = await must("add_shape", { document, shape: "rectangle", frame: { x: 100, y: 100, width: 120, height: 40 },
                                        fill: "#000000", cornerRadius: 8, name: "Background" });
  const label = await must("add_text", { document, text: "Get started", x: 110, y: 110, shadow: false, name: "Label" });

  await oneStep(document, "apply_style", { style: "brand", layers: [box.layer] },
    (_, answer) => answer.part === "fill" || `painted ${answer.part}`);
  await oneStep(document, "apply_style", { style: "Button Label", layers: [label.layer] },
    (doc) => {
      const text = find(doc.layers, (l) => l.id === label.layer)?.text;
      return (text?.size === 15 && text?.weight === "semibold" && text?.color === "#FFFFFF") || JSON.stringify(text);
    });

  // A button: the label and the box grouped, a padded row stack, and the box made its surface.
  const grouped = await must("run_command", { document, command: "group", arguments: { layers: [box.layer, label.layer] } });
  let doc = await read(document);
  const group = find(doc.layers, (l) => l.kind === "group");
  results.push({ name: "group", ok: !!group, why: group ? `group ${group.name}` : `no group: ${JSON.stringify(grouped)}` });

  await oneStep(document, "set_layout", { layer: group.id, arrange: "stack", direction: "row", padding: { top: 10, bottom: 10, left: 20, right: 20 } },
    (after) => {
      const layout = find(after.layers, (l) => l.id === group.id)?.layout;
      return (layout?.arrange === "stack" && layout?.direction === "row" && layout?.paddingSides?.join() === "10,20,10,20")
        || JSON.stringify(layout);
    });
  // The answer and the read both put the group where it is (it was grouped at 100, 100).
  await oneStep(document, "set_layout", { layer: group.id, gap: 6 },
    (after, answer) => {
      const read = find(after.layers, (l) => l.id === group.id);
      return (read?.layout?.gap === 6 && answer.frame.x === 100 && answer.frame.y === 100
              && read.frame.x === 100 && read.frame.width === answer.frame.width && read.frame.width > 0)
        || `gap ${read?.layout?.gap}, answer ${JSON.stringify(answer.frame)}, read ${JSON.stringify(read?.frame)}`;
    });

  // The box is the button's surface: painted to the group's edges, the label laid out on top.
  await oneStep(document, "run_command", { command: "surface_behind", arguments: { layers: [box.layer], on: true } },
    (after) => {
      const g = find(after.layers, (l) => l.id === group.id);
      const back = find(after.layers, (l) => l.id === box.layer)?.frame;
      return (back && back.x === 0 && back.y === 0 && Math.abs(back.width - g.frame.width) < 1
              && Math.abs(back.height - g.frame.height) < 1)
        || `surface ${JSON.stringify(back)} in ${JSON.stringify(g.frame)}`;
    });
  await must("run_command", { document, command: "rename_layer", arguments: { layers: [group.id], name: "Primary Button" } });
  await oneStep(document, "run_command", { command: "make_component", arguments: { layers: [group.id] } },
    (after) => find(after.layers, (l) => l.name === "Primary Button")?.kind === "component" || "the button is not a component");

  const listed = await must("list_components", { document });
  const mine = listed.find((c) => c.from === "document" && c.name === "Primary Button");
  results.push({ name: "list_components", ok: !!mine, why: mine ? `${mine.name} on the shelf` : JSON.stringify(listed.filter((c) => c.from === "document")) });
  await oneStep(document, "place_component", { component: "Primary Button", x: 400, y: 120 });
  await oneStep(document, "place_component", { component: "Primary Button", x: 600, y: 120 });

  // Words over a piece of one copy land on that copy alone, as typing over it does.
  doc = await read(document);
  const copies = doc.layers.filter((l) => l.name === "Primary Button" && l.kind === "component");
  const labelIn = (layer) => find(layer?.children ?? [], (l) => l.kind === "text");
  const second = copies[0];
  const piece = labelIn(second);
  if (piece) {
    await oneStep(document, "set_layer", { layer: piece.id, text: "Sign in" },
      (after) => {
        const words = after.layers.filter((l) => l.name === "Primary Button").map((l) => labelIn(l)?.text?.string);
        return (words.filter((w) => w === "Sign in").length === 1 && words.filter((w) => w === "Get started").length === words.length - 1)
          || `labels ${JSON.stringify(words)}`;
      });
    const painted = await tool("set_layer", { document, layer: piece.id, fill: "#FF0000" });
    results.push({ name: "set_layer copy refusal", ok: painted.refused && painted.text.includes("edit_original"), why: painted.text });
  } else {
    results.push({ name: "set_layer in a copy", ok: false, why: "no label inside the placed copy" });
  }

  // A style is a name things follow: change it once and every copy follows.
  const shelf = await styles(document);
  results.push({ name: "list_styles", ok: shelf.colors.some((c) => c.name === "Brand") && shelf.text.some((t) => t.name === "Button Label"),
                 why: `${shelf.colors.length} colours, ${shelf.text.length} text styles` });

  const refusal = await tool("apply_style", { document, style: "Nope", layers: [box.layer] });
  results.push({ name: "apply_style refusal", ok: refusal.refused && refusal.text.includes("no style called Nope"), why: refusal.text });
  const notGroup = await tool("set_layout", { document, layer: box.layer, gap: 4 });
  results.push({ name: "set_layout refusal", ok: notGroup.refused && notGroup.text.includes("not a group"), why: notGroup.text });

  const picture = await tool("render_picture", { document });
  if (picture.image) writeFileSync(path.join(scratch, "button.png"), Buffer.from(picture.image, "base64"));
  results.push({ name: "render_picture", ok: !!picture.image, why: picture.image ? `${scratch}/button.png` : picture.text });
} catch (error) {
  results.push({ name: "drill", ok: false, why: String(error.message ?? error) });
}

bridge.stdin.end();
bridge.kill();
for (const result of results) console.log(`${result.ok ? "ok    " : "FAILED"}  ${result.name.padEnd(24)} ${result.why}`);
const failed = results.filter((result) => !result.ok).length;
console.log(`\n${results.length - failed} of ${results.length} design checks passed${failed ? `; ${failed} did not` : ""}.`);
process.exit(failed ? 1 : 0);
