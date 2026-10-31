#!/usr/bin/env node
// The agent paints with the brushes through MCP, one undo step per stroke
// (docs/design/brushes.md, decision 8).
//
// Drives the probe through the MCP bridge exactly as an agent does: a new
// picture, list_brushes, set_brush, then strokes in several media, a pen
// stroke with pressure and a smudge. Each stroke is checked: the paint layer
// holds one more stroke, one undo takes exactly that stroke back, and redo
// puts it back. The brush in hand is checked to be what set_brush armed, and
// a stroke's own brush to leave it alone.
//
//   Scripts/agent-paint-drill.mjs
//
// Writes a picture of the result to /tmp/photonz-agent-paint-drill/painted.png.
// Needs the probe (Scripts/build-app.sh --probe); the bridge starts it in the
// background. Quit it after (Scripts/probe-app.sh --quit).
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { connect } from "./ask-eval/mcp.mjs";

const scratch = "/tmp/photonz-agent-paint-drill";
rmSync(scratch, { recursive: true, force: true });
mkdirSync(scratch, { recursive: true });

const mcp = connect({ app: "probe" });
let failures = 0;
function check(ok, words) {
  console.log(`${ok ? "ok  " : "FAIL"} ${words}`);
  if (!ok) failures += 1;
}

async function paintLayer(document) {
  const read = (await mcp.tool("read_document", { document })).json;
  return read.layers.find((layer) => layer.kind === "paint");
}

try {
  await mcp.start();
  const listed = (await mcp.tool("list_brushes")).json;
  check(listed.brushes.length === 8, `list_brushes lists ${listed.brushes.length} brushes`);
  check(listed.brushes.every((b) => b.settings.some((s) => s.id === "size")), "every brush has a Size");
  const picture = (await mcp.tool("new_picture", { width: 640, height: 420 })).json;
  const document = picture.id ?? picture.document;
  check(Boolean(document), `new picture ${document}`);

  const armed = (await mcp.tool("set_brush", { document, medium: "oil", color: "#2F5D8A", settings: { size: 40, load: 80 } })).json;
  check(armed.medium === "oil" && armed.settings.size === 40 && armed.color === "#2F5D8A",
        `set_brush armed ${armed.medium} at ${armed.settings.size} pt in ${armed.color}`);

  const strokes = [
    { label: "oil sky with the brush in hand", args: { points: [{ x: 20, y: 60 }, { x: 320, y: 40 }, { x: 620, y: 70 }] } },
    { label: "watercolour hills, its own brush", args: { points: [{ x: 10, y: 300 }, { x: 200, y: 220 }, { x: 420, y: 280 }, { x: 630, y: 230 }],
      medium: "watercolour", color: "#3E7D3A", settings: { size: 80, wetness: 70 } } },
    { label: "pencil with a pen's pressure", args: { points: [{ x: 80, y: 380, pressure: 0.2 }, { x: 300, y: 360, pressure: 0.9 }, { x: 560, y: 390, pressure: 0.4 }],
      medium: "pencil", color: "#222222", settings: { hardness: "6B" } } },
    { label: "charcoal smudge across the hills", args: { points: [{ x: 150, y: 250 }, { x: 260, y: 270 }], medium: "charcoal", mode: "smudge", settings: { size: 30 } } },
  ];
  let count = 0;
  for (const stroke of strokes) {
    const painted = (await mcp.tool("paint_stroke", { document, ...stroke.args })).json;
    count += 1;
    const layer = await paintLayer(document);
    check(layer?.paint?.strokes === count, `${stroke.label}: the Paint layer holds ${layer?.paint?.strokes} strokes (${painted.medium})`);
    await mcp.tool("undo", { document });
    const back = await paintLayer(document);
    check((back?.paint?.strokes ?? 0) === count - 1, `${stroke.label}: one undo leaves ${back?.paint?.strokes ?? 0}`);
    await mcp.tool("redo", { document });
    const again = await paintLayer(document);
    check(again?.paint?.strokes === count, `${stroke.label}: redo puts it back (${again?.paint?.strokes})`);
  }
  const still = (await mcp.tool("list_brushes", { document })).json.armed;
  check(still.medium === "oil" && still.settings.size === 40, `a stroke's own brush left the one in hand alone (${still.medium} ${still.settings.size} pt)`);

  let refused = "";
  try { await mcp.tool("paint_stroke", { document, points: [{ x: 1, y: 1 }, { x: 5, y: 5 }], medium: "oil", settings: { wetness: 50 } }); }
  catch (error) { refused = error.message; }
  check(refused.includes("load, smear"), `a setting oil does not have is refused: ${refused}`);

  const shot = await mcp.tool("render_picture", { document });
  if (shot.image) writeFileSync(`${scratch}/painted.png`, Buffer.from(shot.image, "base64"));
  check(Boolean(shot.image), `rendered ${scratch}/painted.png`);
} catch (error) {
  console.log(`FAIL ${error.message}`);
  failures += 1;
} finally {
  mcp.close();
}
console.log(failures ? `${failures} failed` : "every check passed");
process.exit(failures ? 1 : 0);
