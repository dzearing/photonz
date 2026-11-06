#!/usr/bin/env node
// An agent keys a shape over MCP, plays it and copies it as an animated SVG
// (task an-agent-can-set-read-and-change-a-layer-s-keys).
//
// Drives the probe through the MCP bridge exactly as an agent does. Each change
// is checked to be one undo step, and the file is read to see it loops.
//
//   Scripts/agent-keys-drill.mjs
//
// Writes frames, a sheet and the SVG to /tmp/photonz-agent-keys-drill. Needs the
// probe (Scripts/build-app.sh --probe); the bridge starts it in the background.
// Quit it after (Scripts/probe-app.sh --quit).
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { connect } from "./ask-eval/mcp.mjs";

const scratch = "/tmp/photonz-agent-keys-drill";
rmSync(scratch, { recursive: true, force: true });
mkdirSync(scratch, { recursive: true });

const mcp = connect({ app: "probe" });
let failures = 0;
function check(ok, words) {
  console.log(`${ok ? "ok  " : "FAIL"} ${words}`);
  if (!ok) failures += 1;
}
async function refused(tool, args, words) {
  try {
    await mcp.tool(tool, args);
    check(false, `${tool} should have been refused: ${words}`);
  } catch (error) {
    check(error.message.includes(words), `${tool} refused: ${error.message}`);
  }
}
function save(name, image) {
  if (image) writeFileSync(`${scratch}/${name}.png`, Buffer.from(image, "base64"));
  return Boolean(image);
}

try {
  await mcp.start();
  const picture = (await mcp.tool("new_picture", { width: 240, height: 240 })).json;
  const document = picture.id ?? picture.document;
  const shape = (await mcp.tool("add_shape", { document, shape: "rectangle", frame: { x: 70, y: 100, width: 100, height: 40 }, fill: "#2F6FED", name: "Bar" })).json;
  const layer = shape.layer ?? shape.id;
  check(Boolean(layer), `a shape to key: ${layer}`);
  const read = async () => (await mcp.tool("read_document", { document })).json;

  await refused("set_playhead", { document, seconds: 0.5 }, "no keys");
  await refused("set_keys", { document, layer, property: "opacity", keys: [{ seconds: 0, value: 400 }] }, "0 to 100");
  await refused("set_keys", { document, layer, property: "rotation", keys: [{ seconds: 0, value: 0, curve: "wiggly" }] }, "no curve");

  const set = (await mcp.tool("set_keys", { document, layer, property: "rotation", keys: [
    { seconds: 0, value: 0, curve: "Linear" }, { seconds: 1, value: 360 },
  ] })).json;
  check(set.keys === 2 && set.lapSeconds === 2, `set_keys: ${JSON.stringify(set)}`);
  let now = await read();
  check(now.kind === "picture" && now.lap?.seconds === 2 && now.lap?.loop === true, `it stays a picture with a lap: ${JSON.stringify(now.lap)}`);
  const keyed = now.layers[0].keyed?.[0];
  check(keyed?.property === "rotation" && keyed.keys.length === 2 && keyed.keys[0].curve === "Linear", `read_document shows the keys: ${JSON.stringify(keyed)}`);

  await mcp.tool("undo", { document });
  now = await read();
  check(!now.layers[0].keyed, "one undo takes the keys away");
  await mcp.tool("redo", { document });
  now = await read();
  check(now.layers[0].keyed?.[0].keys.length === 2, "redo puts them back");

  const timed = (await mcp.tool("set_timing", { document, seconds: 1 })).json;
  check(timed.lapSeconds === 1 && timed.loop === true, `set_timing: ${JSON.stringify(timed)}`);
  await refused("set_timing", { document, seconds: 0.5 }, "last key");

  const moved = (await mcp.tool("set_playhead", { document, seconds: 0.25 })).json;
  check(moved.playheadSeconds === 0.25, `the playhead moves on a picture: ${JSON.stringify(moved)}`);
  check(save("at-a-quarter", (await mcp.tool("render_picture", { document })).image), "render_picture draws it at the playhead");
  check(save("frame-half", (await mcp.tool("video_frame", { document, seconds: 0.5 })).image), "video_frame draws a moment of the lap");
  check(save("sheet", (await mcp.tool("contact_sheet", { document, count: 8, cellWidth: 160 })).image), "contact_sheet draws the lap");

  const played = (await mcp.tool("run_command", { document, command: "play_pause" })).json;
  check(played.ran === "play_pause", `it plays: ${JSON.stringify(played)}`);
  await new Promise((resolve) => setTimeout(resolve, 700));
  await mcp.tool("run_command", { document, command: "play_pause" });

  const exported = (await mcp.tool("export", { document, format: "svg", path: `${scratch}/keyed.svg` })).json;
  const svg = readFileSync(`${scratch}/keyed.svg`, "utf8");
  check(exported.lapSeconds === 1, `export says it moves: ${JSON.stringify(exported)}`);
  check(svg.includes("animateTransform") && svg.includes('repeatCount="indefinite"') && svg.includes('dur="1000ms"'), "the file loops, one lap a second");

  const copied = (await mcp.tool("run_command", { document, command: "copy_svg", arguments: { layers: [layer] } })).json;
  check(copied.ran === "copy_svg", `Copy SVG ran: ${JSON.stringify(copied)}`);
  // The probe keeps its clipboard off the person's, so it is read by name.
  const board = execFileSync("swift", ["-e", `import AppKit
print(NSPasteboard(name: NSPasteboard.Name("com.dzearing.photonz.probe.clipboard")).string(forType: .string) ?? "")`], { encoding: "utf8" });
  writeFileSync(`${scratch}/copied.svg`, board);
  check(board.includes("animateTransform") && board.includes('repeatCount="indefinite"'), "what Copy SVG put on the clipboard loops too");

  const gone = (await mcp.tool("remove_keys", { document, layer })).json;
  check(gone.removed === 2, `remove_keys: ${JSON.stringify(gone)}`);
  now = await read();
  check(!now.layers[0].keyed, "with its keys gone the layer reads as a still");
  await refused("video_frame", { document, seconds: 0.1 }, "no keys");
} catch (error) {
  check(false, error.message);
} finally {
  mcp.close();
}
console.log(failures === 0 ? "\nAll good." : `\n${failures} failed.`);
process.exit(failures === 0 ? 0 : 1);
