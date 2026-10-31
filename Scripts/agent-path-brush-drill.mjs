#!/usr/bin/env node
// The agent paints a path's line with a brush through MCP, and the path stays
// editable (docs/design/brushes.md, decision 9).
//
// Drives the probe through the MCP bridge exactly as an agent does: a new
// picture, two paths drawn with add_path (one brushed as it is drawn), the
// two grouped, the group's brush swapped with set_layer so every line in it
// follows, one undo taking that swap back, and plain giving the plain line
// back. read_document is the witness each time. It also times render_picture
// on the same picture with the lines plain and brushed, so the cost of a
// brushed line in the shipping build is a number rather than a guess.
//
//   Scripts/agent-path-brush-drill.mjs
//
// Writes pictures to /tmp/photonz-agent-path-brush-drill/. Needs the probe
// (Scripts/probe-app.sh); the bridge starts it in the background. Quit it
// after (Scripts/probe-app.sh --quit).
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { connect } from "./ask-eval/mcp.mjs";

const scratch = "/tmp/photonz-agent-path-brush-drill";
rmSync(scratch, { recursive: true, force: true });
mkdirSync(scratch, { recursive: true });

const mcp = connect({ app: "probe" });
let failures = 0;
function check(ok, words) {
  console.log(`${ok ? "ok  " : "FAIL"} ${words}`);
  if (!ok) failures += 1;
}

function paths(read) {
  const found = [];
  const walk = (layers) => {
    for (const layer of layers ?? []) {
      if (layer.kind === "path") found.push(layer);
      walk(layer.children);
    }
  };
  walk(read.layers);
  return found;
}

async function brushes(document) {
  return paths((await mcp.tool("read_document", { document })).json).map((p) => p.path.brush ?? "plain");
}

async function timedRender(document, label, width) {
  // A new thickness each time, so the line is drawn again rather than read
  // from what the renderer kept.
  for (const layer of paths((await mcp.tool("read_document", { document })).json)) {
    await mcp.tool("set_layer", { document, layer: layer.id, strokeWidth: width });
  }
  const started = performance.now();
  const shot = await mcp.tool("render_picture", { document });
  const ms = performance.now() - started;
  if (shot.image) writeFileSync(`${scratch}/${label}.png`, Buffer.from(shot.image, "base64"));
  return ms;
}

try {
  await mcp.start();
  const picture = (await mcp.tool("new_picture", { width: 1200, height: 800 })).json;
  const document = picture.id ?? picture.document;
  check(Boolean(document), `new picture ${document}`);

  const s = [{ x: 120, y: 420 }, { x: 520, y: 160, smooth: true }, { x: 1080, y: 420 }];
  const first = (await mcp.tool("add_path", { document, points: s, stroke: "#20242C", strokeWidth: 16, brush: "charcoal", name: "Hill" })).json;
  const second = (await mcp.tool("add_path", { document, points: [{ x: 120, y: 640 }, { x: 600, y: 560 }, { x: 1080, y: 640 }],
    stroke: "#2F5D8A", strokeWidth: 10, name: "Shore" })).json;
  check((await brushes(document)).join() === "plain,charcoal", `add_path brushed one line and left the other plain (${await brushes(document)})`);

  const plainMS = await timedRender(document, "plain-first", 15);
  await mcp.tool("set_layer", { document, layer: second.id ?? second.layer, brush: "charcoal" });

  const ids = paths((await mcp.tool("read_document", { document })).json).map((p) => p.id);
  await mcp.tool("run_command", { document, command: "group", arguments: { layers: ids } });
  const read = (await mcp.tool("read_document", { document })).json;
  const group = read.layers.find((layer) => layer.kind === "group");
  check(Boolean(group), `the two paths are grouped (${group?.name})`);

  const timings = {};
  for (const medium of ["charcoal", "pencil", "marker", "oil", "watercolour"]) {
    await mcp.tool("set_layer", { document, layer: group.id, brush: medium });
    timings[medium] = Math.round(await timedRender(document, `brushed-${medium}`, 16));
  }
  const swapped = await brushes(document);
  check(swapped.every((b) => b === "watercolour"), `set_layer on the group swapped every line (${swapped})`);
  // Two swaps with nothing between them, then one undo.
  await mcp.tool("set_layer", { document, layer: group.id, brush: "crayon" });
  await mcp.tool("set_layer", { document, layer: group.id, brush: "chalk" });
  await mcp.tool("undo", { document });
  const undone = await brushes(document);
  check(undone.every((b) => b === "crayon"), `one undo took the last swap back, every line at once (${undone})`);
  await mcp.tool("redo", { document });
  const redone = await brushes(document);
  check(redone.every((b) => b === "chalk"), `redo put it back (${redone})`);

  await mcp.tool("set_layer", { document, layer: group.id, brush: { medium: "marker", settings: { tip: "Chisel", flow: 40, size: 24 } } });
  const marker = paths((await mcp.tool("read_document", { document })).json);
  check(marker.every((p) => p.path.brush === "marker" && p.path.strokeWidth === 24), `a brush's size is the line's thickness (${marker.map((p) => p.path.strokeWidth)})`);

  let refused = "";
  try { await mcp.tool("set_layer", { document, layer: group.id, brush: { medium: "marker", settings: { wetness: 50 } } }); }
  catch (error) { refused = error.message; }
  check(refused.includes("wetness"), `a setting the marker does not have is refused: ${refused}`);

  await mcp.tool("set_layer", { document, layer: group.id, brush: "plain" });
  check((await brushes(document)).every((b) => b === "plain"), `plain gives every line its plain stroke back (${await brushes(document)})`);
  const plainAgainMS = await timedRender(document, "plain-again", 17);

  console.log(`render_picture, 1200x800: plain ${Math.round(plainMS)} ms then ${Math.round(plainAgainMS)} ms; brushed ${JSON.stringify(timings)} ms`);
} catch (error) {
  console.log(`FAIL ${error.message}`);
  failures += 1;
} finally {
  mcp.close();
}
console.log(failures ? `${failures} failed` : "every check passed");
process.exit(failures ? 1 : 0);
