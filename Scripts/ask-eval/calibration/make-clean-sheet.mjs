#!/usr/bin/env node
// Builds, by hand through the same tools an agent has, the clean component
// sheet the judge is calibrated against: a title, a header per state, a
// labelled row per control, every cell on one grid with one type scale, laid
// out like a page of the design-kit mocks (docs/design/mocks/pages/comp-buttons.html).
// Writes clean-component-sheet.png and clean-component-sheet.read.json beside
// this file, then quits the probe.
//
//   node Scripts/ask-eval/calibration/make-clean-sheet.mjs
import { writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { connect } from "../mcp.mjs";
import { quitProbe } from "../engines.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const bridge = connect();
await bridge.start();
const must = async (name, args) => (await bridge.tool(name, { document, ...args })).json;
let document;
document = (await bridge.tool("new_picture", { width: 1440, height: 1024 })).json.id;

const ink = "#1D1D1F", secondary = "#6E6E73", blue = "#007AFF";
const text = (words, x, y, size, weight, color, extra = {}) =>
  must("add_text", { text: words, x, y, fontSize: size, weight, color, shadow: false, ...extra });
/// Words centred in a box: set at the box's width, then moved to its middle.
async function centred(words, box, size, weight, color) {
  const added = await text(words, box.x, box.y, size, weight, color, { width: box.width, alignment: "center" });
  const read = await must("read_document", { layer: added.layer });
  const frame = read.layers[0].frame;
  await must("set_layer", { layer: added.layer, y: box.y + (box.height - frame.height) / 2 });
  return added.layer;
}
const rect = (frame, fill, extra = {}) => must("add_shape", { shape: "rectangle", frame, fill, strokeWidth: 0, ...extra });
const group = async (layers, name) => {
  await must("run_command", { command: "group", arguments: { layers } });
  const read = await must("read_document", {});
  const made = read.layers.find((l) => l.kind === "group" && !l.name.startsWith("cell:"));
  await must("run_command", { command: "rename_layer", arguments: { layers: [made.id], name: `cell: ${name}` } });
  return made.id;
};

await text("Base components", 96, 72, 34, "bold", ink);
await text("Each control in its four states", 96, 122, 17, "regular", secondary);
const states = ["Default", "Hover", "Pressed", "Disabled"];
const left = 336, column = 256, cellWidth = 208, top = 232, rowHeight = 112;
for (const [i, state] of states.entries()) {
  await text(state, left + i * column, 184, 13, "semibold", secondary);
}
await must("add_shape", { shape: "line", from: { x: 96, y: 212 }, to: { x: 1344, y: 212 }, stroke: "#D2D2D7", strokeWidth: 1 });

const rows = [
  {
    name: "Button",
    cell: async (x, y, s) => {
      const fills = ["#007AFF", "#1A88FF", "#0062CC", "#B3D4FF"];
      const box = { x, y: y + 22, width: 132, height: 40 };
      const bg = await rect(box, fills[s], { cornerRadius: 20 });
      const label = await centred("Continue", box, 15, "semibold", "#FFFFFF");
      return [bg.layer, label];
    },
  },
  {
    name: "Secondary",
    cell: async (x, y, s) => {
      const fills = ["#E8E8ED", "#DCDCE1", "#CDCDD3", "#F2F2F5"];
      const box = { x, y: y + 22, width: 132, height: 40 };
      const bg = await rect(box, fills[s], { cornerRadius: 20 });
      const label = await centred("Cancel", box, 15, "semibold", s === 3 ? "#A1A1A6" : blue);
      return [bg.layer, label];
    },
  },
  {
    name: "Text field",
    cell: async (x, y, s) => {
      const strokes = ["#C7C7CC", "#A1A1A6", blue, "#E5E5EA"];
      const box = { x, y: y + 22, width: cellWidth, height: 40 };
      const bg = await rect(box, s === 3 ? "#F5F5F7" : "#FFFFFF", { cornerRadius: 10, stroke: strokes[s], strokeWidth: s === 2 ? 2 : 1 });
      const words = await text(s === 2 ? "name@example.com" : "Email", x + 14, y + 22, 15, "regular", s === 2 ? ink : s === 3 ? "#C7C7CC" : "#8E8E93");
      const read = await must("read_document", { layer: words.layer });
      await must("set_layer", { layer: words.layer, y: box.y + (box.height - read.layers[0].frame.height) / 2 });
      return [bg.layer, words.layer];
    },
  },
  {
    name: "Switch",
    cell: async (x, y, s) => {
      const tracks = ["#34C759", "#2FB350", "#28A745", "#B7EBC4"];
      const track = await rect({ x, y: y + 26, width: 52, height: 32 }, tracks[s], { cornerRadius: 16 });
      const knobWidth = s === 2 ? 34 : 28;
      const knob = await must("add_shape", { shape: s === 2 ? "rectangle" : "ellipse", frame: { x: x + 52 - 2 - knobWidth, y: y + 28, width: knobWidth, height: 28 },
        fill: "#FFFFFF", strokeWidth: 0, ...(s === 2 ? { cornerRadius: 14 } : {}) });
      return [track.layer, knob.layer];
    },
  },
  {
    name: "Checkbox",
    cell: async (x, y, s) => {
      const fills = [blue, "#1A88FF", "#0062CC", "#B3D4FF"];
      const box = await rect({ x, y: y + 31, width: 22, height: 22 }, fills[s], { cornerRadius: 6 });
      const tick = await must("add_path", { points: [{ x: x + 6, y: y + 42 }, { x: x + 10, y: y + 46 }, { x: x + 17, y: y + 37 }],
        stroke: "#FFFFFF", strokeWidth: 2.5 });
      const words = await text("Remember me", x + 32, y + 31, 15, "regular", s === 3 ? "#A1A1A6" : ink);
      const read = await must("read_document", { layer: words.layer });
      await must("set_layer", { layer: words.layer, y: y + 42 - read.layers[0].frame.height / 2 });
      return [box.layer, tick.layer, words.layer];
    },
  },
];
for (const [r, row] of rows.entries()) {
  const y = top + r * rowHeight;
  const label = await text(row.name, 96, y, 15, "medium", ink);
  const read = await must("read_document", { layer: label.layer });
  await must("set_layer", { layer: label.layer, y: y + 42 - read.layers[0].frame.height / 2 });
  for (const s of states.keys()) {
    const layers = await row.cell(left + s * column, y, s);
    await group(layers, `${row.name} ${states[s]}`);
  }
  if (r < rows.length - 1) {
    await must("add_shape", { shape: "line", from: { x: 96, y: y + rowHeight - 14 }, to: { x: 1344, y: y + rowHeight - 14 }, stroke: "#EDEDF0", strokeWidth: 1 });
  }
}

const read = await must("read_document", {});
writeFileSync(path.join(here, "clean-component-sheet.read.json"), JSON.stringify(read, null, 2) + "\n");
const picture = await bridge.tool("render_picture", { document, maxSize: 1600 }, 120_000);
writeFileSync(path.join(here, "clean-component-sheet.png"), Buffer.from(picture.image, "base64"));
bridge.close();
await quitProbe();
console.log(`==> ${read.layerCount} layers; wrote clean-component-sheet.png and its read`);
