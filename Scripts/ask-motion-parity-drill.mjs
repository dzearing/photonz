#!/usr/bin/env node
// Does an animated SVG play the way Photonz's own timeline does? A keyed icon is
// made over MCP with no model, the timeline's frames are drawn at a few moments
// (video_frame), the exported file is played in WebKit at the same moments
// (Scripts/ask-eval/svg-frames.swift), and the two sets of pictures go side by
// side. Task ask-animates-what-it-makes-an-animated-svg-icon.
//
//   Scripts/ask-motion-parity-drill.mjs
//
// Writes frames to /tmp/photonz-motion-parity. Needs the probe; quit it after.
import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { connect } from "./ask-eval/mcp.mjs";

const scratch = "/tmp/photonz-motion-parity";
rmSync(scratch, { recursive: true, force: true });
mkdirSync(scratch, { recursive: true });
const svg = `<svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
<g id="swing"><rect id="bar" x="5" y="5" width="14" height="2" rx="1"/><path id="mark" d="M12 7 L12 12"/></g>
<path id="line" d="M6 18 L12 21 L18 16"/><circle id="dot" cx="19" cy="9" r="1.5" fill="#1D1D1F" stroke="none"/></svg>`;
const mcp = connect({ app: "probe" });
try {
  await mcp.start();
  const made = (await mcp.tool("new_picture", { width: 512, height: 512 })).json;
  const document = made.id ?? made.document;
  await mcp.tool("add_drawing", { document, subject: "parity", icon: true, svg, forMotion: true });
  const read = async () => (await mcp.tool("read_document", { document })).json;
  const find = (layers, name) => {
    for (const layer of layers ?? []) {
      if (layer.name?.toLowerCase() === name) return layer;
      const inside = find(layer.children, name);
      if (inside) return inside;
    }
    return null;
  };
  let now = await read();
  const id = (name) => find(now.layers, name)?.id;
  await mcp.tool("set_timing", { document, seconds: 2, loop: true });
  await mcp.tool("set_keys", { document, layer: id("swing"), property: "rotation", pivot: { x: 0, y: 0.5 }, keys: [
    { seconds: 0, value: 0, curve: "Ease in out" }, { seconds: 1, value: -30, curve: "Ease out back" }, { seconds: 2, value: 0 }] });
  await mcp.tool("set_keys", { document, layer: id("line"), property: "trimEnd", keys: [
    { seconds: 0, value: 0, curve: "Ease out" }, { seconds: 1, value: 100 }, { seconds: 2, value: 100 }] });
  await mcp.tool("set_keys", { document, layer: id("dot"), property: "scale", keys: [
    { seconds: 0, value: 100, curve: "Ease in out" }, { seconds: 1, value: 180, curve: "Ease in out" }, { seconds: 2, value: 100 }] });
  const moments = [0, 0.5, 1, 1.5];
  for (const seconds of moments) {
    const frame = await mcp.tool("video_frame", { document, seconds, maxSize: 240 }, 60_000);
    writeFileSync(`${scratch}/timeline-${seconds}.png`, Buffer.from(frame.image, "base64"));
  }
  const file = `${scratch}/parity.svg`;
  const written = (await mcp.tool("export", { document, format: "svg", path: file, background: false })).json;
  console.log(`exported: lap ${written.lapSeconds}, left still: ${JSON.stringify(written.notMoving ?? [])}`);
  console.log(execFileSync("swift", ["Scripts/ask-eval/svg-frames.swift", `${scratch}/file.png`, file, "2", "--frames", "5"]).toString().trim());
} finally {
  mcp.close?.();
}
