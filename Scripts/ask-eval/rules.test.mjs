// node --test Scripts/ask-eval/rules.test.mjs
// The rule scores must tell the user's three failures from clean work.
import { test } from "node:test";
import assert from "node:assert/strict";
import { score, flatten, cells } from "./rules.mjs";

const canvas = { width: 1440, height: 1024 };
const background = { id: "bg", name: "Background", kind: "image", locked: true, frame: { x: 0, y: 0, width: 1440, height: 1024 } };
const shape = (name, x, y, width, height, kind = "ellipse") => ({ id: name, name, kind: "shape", frame: { x, y, width, height }, shape: { shape: kind } });
const text = (string, x, y, size = 15, weight = "regular", width = string.length * size * 0.55, height = size * 1.3) =>
  ({ id: string, name: string, kind: "text", frame: { x, y, width, height }, text: { string, size, weight, font: "SF Pro", color: "#000000" } });
const component = (name, x, y, width, height, children) => ({ id: name, name, kind: "component", frame: { x, y, width, height }, children });
const read = (layers) => ({ canvas, layers: [...layers, background] });

const smiley = { group: "drawing", expect: { words: false, icon: true, parts: [{ name: "eye", count: 2 }, { name: "mouth|smile|grin" }], inside: [["eye|mouth|smile|grin", "face|head|circle|smiley"]] } };

test("the user's smiley, eyes above the face and no smile, fails what was asked", () => {
  // The Ask run of 2026-10-20 (read back from the probe while building this).
  const result = score(read([shape("Right Eye", 800, 200, 60, 60), shape("Left Eye", 600, 200, 60, 60), shape("Smiley Face Circle", 500, 300, 440, 440)]), smiley);
  assert.ok(result.rules.asked.score < 4, result.rules.asked.note);
  assert.match(result.rules.asked.note, /Left Eye NOT inside/);
  assert.match(result.rules.asked.note, /0 of 1 mouth/);
});

test("a smiley with its eyes and smile in the face, centred and square, passes", () => {
  const result = score(read([
    shape("Smile", 590, 600, 260, 90, "path"), shape("Left Eye", 600, 380, 60, 90), shape("Right Eye", 780, 380, 60, 90),
    shape("Face", 400, 192, 640, 640)]), smiley);
  assert.equal(result.rules.asked.score, 10, result.rules.asked.note);
  assert.ok(result.rules.composed.score > 9, result.rules.composed.note);
});

test("a word laid on a drawing that needed none is a miss", () => {
  const result = score(read([text("Dog", 800, 500, 48), shape("Dog Body", 600, 600, 300, 200)]), { group: "drawing", expect: { words: false } });
  assert.match(result.rules.asked.note, /MISS words on a drawing/);
});

test("parts that should touch the body are checked", () => {
  const result = score(read([shape("Dog Ear", 100, 100, 20, 20), shape("Dog Leg", 400, 500, 20, 60), shape("Dog Body", 300, 300, 300, 200)]),
    { group: "drawing", expect: { touch: [["ear|leg", "body|head"]] } });
  assert.match(result.rules.asked.note, /Dog Ear does NOT touch/);
  assert.match(result.rules.asked.note, /ok Dog Leg touches/);
});

const sheet = { group: "sheet", expect: { title: true, headers: ["default", "hover", "pressed", "disabled"], headersAtLeast: 3, minCells: 8, rowLabels: true } };

// The user's mess (queue/audits/2026-10-20-user-ask-component-sheet-mess.png):
// five starter components where they fell, five words laid over them.
const mess = read([
  // Measured off the screenshot: 1.617 pixels to a point.
  text("Click me", 199, 133, 24), text("Enter text here", 199, 234, 24), text("Card Content", 220, 324, 24),
  text("Navigation Bar", 720, 403, 24), text("Badge", 99, 504, 24),
  component("Button", 101, 101, 198, 57, [text("Button", 70, 30, 13, "semibold")]),
  component("Text Field", 101, 180, 198, 36, [text("Placeholder", 10, 10, 13)]),
  component("Card", 90, 234, 259, 171, [shape("Image", 10, 10, 230, 90, "rectangle"), text("Card title", 10, 105, 15, "semibold"), text("Supporting text goes here.", 10, 130, 12)]),
  component("Nav Bar", 0, 400, 1440, 50, [text("Back", 560, 0, 15), text("Title", 720, 0, 15, "semibold")]),
  component("Badge", 101, 500, 98, 40, [text("3", 0, 0, 11, "bold")]),
]);

test("the user's component sheet mess scores low on every rule", () => {
  const result = score(mess, sheet);
  assert.ok(result.rules.noOverlap.score < 3, result.rules.noOverlap.note);
  // The starters do fall in one tidy column, so alignment alone is middling.
  assert.ok(result.rules.alignment.score < 7, result.rules.alignment.note);
  assert.ok(result.rules.asked.score < 4, result.rules.asked.note);
  assert.ok(result.score < 6, JSON.stringify(result.rules));
});

// A clean sheet: a title, four state headers, three rows of a labelled
// component in each state, on one grid with equal gaps.
function cleanSheet() {
  const layers = [text("Base components", 120, 80, 34, "bold", 300, 44)];
  const states = ["Default", "Hover", "Pressed", "Disabled"];
  states.forEach((s, i) => layers.push(text(s, 320 + i * 260, 180, 13, "semibold", 200, 18)));
  ["Button", "Text field", "Toggle"].forEach((kind, row) => {
    layers.push(text(kind, 120, 242 + row * 120, 15, "medium", 160, 20));
    states.forEach((s, i) => layers.push(component(`${kind} ${s}`, 320 + i * 260, 230 + row * 120, 200, 44, [text(kind, 20, 12, 15, "medium", 160, 20)])));
  });
  return read(layers);
}

test("a clean sheet scores high on every rule", () => {
  const result = score(cleanSheet(), sheet);
  for (const [name, rule] of Object.entries(result.rules)) assert.ok(rule.score >= 9, `${name}: ${rule.note}`);
});

test("children are measured from their group's top left", () => {
  const nodes = flatten([component("C", 100, 200, 50, 50, [text("x", 5, 6)])]);
  assert.deepEqual([nodes[1].frame.x, nodes[1].frame.y], [105, 206]);
});

test("a group of groups is looked inside; a group of plain pieces is a cell", () => {
  const board = { id: "b", name: "Board", kind: "group", frame: { x: 0, y: 0, width: 600, height: 300 }, children: [
    { id: "c1", name: "Cell", kind: "group", frame: { x: 0, y: 0, width: 100, height: 40 }, children: [shape("bg", 0, 0, 100, 40, "rectangle"), text("A", 10, 10)] },
    { id: "c2", name: "Cell", kind: "group", frame: { x: 120, y: 0, width: 100, height: 40 }, children: [shape("bg", 0, 0, 100, 40, "rectangle"), text("B", 10, 10)] },
  ] };
  assert.deepEqual(cells(flatten([board])).map((c) => c.layer.id), ["c1", "c2"]);
});

test("more than four type sizes loses points", () => {
  const many = read([12, 14, 16, 18, 22, 28, 40].map((size, i) => text(`Words ${i}`, 100, 100 + i * 60, size)));
  const result = score(many, { group: "sheet", expect: {} });
  assert.equal(result.rules.typeScale.score, 2.5, result.rules.typeScale.note);
});

test("measurements are counted on a screenshot", () => {
  const shot = { canvas, layers: [
    ...Array.from({ length: 5 }, (_, i) => ({ id: `m${i}`, name: "Size", kind: "measurement", frame: { x: 100 * i, y: 50, width: 80, height: 30 } })),
    { id: "s", name: "settings.png", kind: "image", frame: { x: 0, y: 0, width: 1440, height: 1024 } }] };
  const result = score(shot, { group: "redline", expect: { minMeasurements: 4, maxMeasurements: 24 } });
  assert.equal(result.rules.asked.score, 10, result.rules.asked.note);
});

test("nothing made scores zero", () => {
  assert.equal(score(read([]), sheet).score, 0);
});

test("prices are found in a pricing section", () => {
  const result = score(read([text("Pricing", 600, 80, 40, "bold"), text("$9/mo", 300, 300), text("$29/mo", 700, 300), text("Free", 1100, 300)]),
    { group: "layout", expect: { prices: 2 } });
  assert.match(result.rules.asked.note, /ok 3 prices/);
});

test("the clean sheet made by hand, read back from the app, scores 9 or more", async () => {
  const { readFileSync } = await import("node:fs");
  const real = JSON.parse(readFileSync(new URL("./calibration/clean-component-sheet.read.json", import.meta.url), "utf8"));
  const result = score(real, sheet);
  assert.ok(result.score >= 9, JSON.stringify(result.rules));
});

test("a backdrop over the whole canvas is not the drawing's size", () => {
  const result = score(read([{ id: "g", name: "Bicycle", kind: "group", frame: { x: 0, y: 0, width: 1440, height: 1024 }, children: [
    shape("Wheel", 400, 400, 240, 240), shape("Wheel", 800, 400, 240, 240), shape("Ground", 0, 0, 1440, 1024, "rectangle")] }]), { group: "drawing", expect: {} });
  assert.equal(result.rules.composed.score, 10, result.rules.composed.note);
});

// MARK: Video cases: read from the timeline and from the frames it plays.

const frame = { x: 0, y: 0, width: 1280, height: 800 };
const recording = (id, name, inSeconds, outSeconds, extra = {}) => ({ layer: { id, name, kind: "clip", frame, time: { inSeconds, outSeconds } }, clip: { inSeconds, outSeconds, kind: "clip", layer: id, name, ...extra } });
const titlePage = (id, words, inSeconds, outSeconds, { size = 123, color = "#F5F5F7", fill = "#000000" } = {}) => ({
  layer: { id, name: "Title Page", kind: "group", frame, time: { inSeconds, outSeconds }, children: [
    { id: `${id}-t`, name: "Title", kind: "text", frame: { x: 129, y: 276, width: 1024, height: 151 }, text: { string: words, size, weight: "semibold", font: "SF Pro", color } },
    { id: `${id}-b`, name: "Background", kind: "shape", frame, shape: { shape: "rectangle", fill } }] },
  clip: { inSeconds, outSeconds, kind: "group", layer: id, name: "Title Page" } });
const video = (parts, { cuts = [], frames } = {}) => ({
  kind: "video", canvas: { width: 1280, height: 800 }, durationSeconds: Math.max(...parts.map((p) => p.clip.outSeconds)),
  layers: parts.map((p) => p.layer), cuts,
  tracks: [{ id: "v1", kind: "video", name: "V1", clips: parts.map((p) => p.clip) }, { id: "a1", kind: "audio", name: "V1 sound", clips: [] }],
  ...(frames ? { playback: { frames } } : {}) });
const everyQuarter = (to, blankAt = []) => Array.from({ length: Math.round(to * 4) }, (_, i) => ({ seconds: i / 4, blank: blankAt.includes(i / 4) }));

const titleCase = { group: "video", expect: { recordings: 1, titles: ["Case 1"], titlesBefore: true } };

test("a title page saying Case 1 in front of the recording passes", () => {
  const result = score(video([titlePage("t1", "Case 1", 0, 4), recording("r", "Tutorial Sample", 4, 12)], { frames: everyQuarter(12, [0]) }), titleCase);
  assert.equal(result.rules.asked.score, 10, result.rules.asked.note);
  // The title's first frame, before its words come in, is not a blank frame.
  assert.equal(result.rules.plays.score, 10, result.rules.plays.note);
});

test("a title laid over the recording instead of before it fails what was asked", () => {
  const over = video([titlePage("t1", "Case 1", 0, 4), recording("r", "Tutorial Sample", 0, 8)]);
  over.tracks = [{ id: "v2", kind: "video", name: "V2", clips: [over.tracks[0].clips[0]] }, { id: "v1", kind: "video", name: "V1", clips: [over.tracks[0].clips[1]] }];
  const result = score(over, titleCase);
  assert.match(result.rules.asked.note, /MISS "Case 1" ends at 4s, after its recording starts at 0s/);
});

test("a video left as it was scores nothing on what was asked", () => {
  const result = score(video([recording("r", "Tutorial Sample", 0, 8)]), titleCase);
  assert.equal(result.rules.asked.score, 5, result.rules.asked.note);
  assert.match(result.rules.asked.note, /MISS no title says "Case 1"/);
});

test("a blank stretch on a recording, or a hole with nothing playing, costs points", () => {
  const holed = video([recording("r", "Tutorial Sample", 0, 4), recording("r2", "Tutorial Sample", 5, 9)], { frames: everyQuarter(9, [2, 4.25, 4.5]) });
  const result = score(holed, { group: "video", expect: { recordings: 2 } });
  assert.equal(result.rules.plays.score, 1, result.rules.plays.note);
  assert.match(result.rules.plays.note, /3 of 36 frames blank/);
});

test("titles Case 1 to 3 before three clips in one look pass, and a different look fails", () => {
  const each = { group: "video", expect: { recordings: 3, titles: ["Case 1", "Case 2", "Case 3"], titlesBefore: true, sameLook: true } };
  const parts = [titlePage("t1", "Case 1", 0, 3), recording("r1", "Tutorial Sample", 3, 11), titlePage("t2", "Case 2", 11, 14),
    recording("r2", "Tutorial Sample", 14, 22), titlePage("t3", "Case 3", 22, 25), recording("r3", "Tutorial Sample", 25, 33)];
  assert.equal(score(video(parts), each).rules.asked.score, 10, score(video(parts), each).rules.asked.note);
  parts[4] = titlePage("t3", "Case 3", 22, 25, { size: 80, fill: "#FFFFFF", color: "#000000" });
  const odd = score(video(parts), each);
  assert.match(odd.rules.asked.note, /MISS the titles have 2 looks/);
  // All three titles before the first clip is not one before each.
  const bunched = [titlePage("t1", "Case 1", 0, 3), titlePage("t2", "Case 2", 3, 6), titlePage("t3", "Case 3", 6, 9),
    recording("r1", "Tutorial Sample", 9, 17), recording("r2", "Tutorial Sample", 17, 25), recording("r3", "Tutorial Sample", 25, 33)];
  assert.match(score(video(bunched), each).rules.asked.note, /MISS "Case 2" starts at 3s, before the recording ahead of it ends at 17s/);
});

test("a dissolve across a cut inside the recording, near the moment asked for", () => {
  const cutCase = { group: "video", expect: { recordings: 1, cut: { near: 2, within: 1, transition: "dissolve" } } };
  const doc = (cuts) => video([recording("r", "Tutorial Sample", 0, 8, { pieces: 2 })], { cuts });
  assert.equal(score(doc([{ atSeconds: 2.1, from: "Tutorial Sample", to: "Tutorial Sample", transition: { kind: "dissolve", seconds: 0.5 } }]), cutCase).rules.asked.score, 10);
  assert.match(score(doc([{ atSeconds: 2.1, from: "Tutorial Sample", to: "Tutorial Sample" }]), cutCase).rules.asked.note, /MISS a cut at 2.1s with no dissolve/);
  assert.match(score(doc([{ atSeconds: 6, from: "Tutorial Sample", to: "Tutorial Sample", transition: { kind: "dissolve", seconds: 0.5 } }]), cutCase).rules.asked.note, /MISS the cut at 6s is not within 1s of 2s/);
  assert.match(score(doc([]), cutCase).rules.asked.note, /MISS no cut inside a recording/);
});

test("zooms are counted on the recordings, and a later recording must follow the first", () => {
  const zoomed = video([recording("r", "Tutorial Sample", 0, 8, { zooms: 1 })]);
  assert.equal(score(zoomed, { group: "video", expect: { recordings: 1, zooms: 1 } }).rules.asked.score, 10);
  const after = { group: "video", expect: { recordings: 2, after: { clip: "Recording 0002", follows: "Tutorial Sample" } } };
  assert.equal(score(video([recording("r", "Tutorial Sample", 0, 8), recording("r2", "Recording 0002", 8, 16)]), after).rules.asked.score, 10);
  assert.match(score(video([recording("r", "Tutorial Sample", 4, 12), recording("r2", "Recording 0002", 0, 4)]), after).rules.asked.note, /MISS Recording 0002 starts at 0s, before Tutorial Sample ends at 12s/);
  assert.match(score(video([recording("r", "Tutorial Sample", 0, 8)]), after).rules.asked.note, /MISS no Recording 0002 on the timeline/);
});

test("a trim is read from how long the video now runs", () => {
  const trimmed = { group: "video", expect: { recordings: 1, length: [5, 6.5] } };
  assert.equal(score(video([recording("r", "Tutorial Sample", 0, 6)]), trimmed).rules.asked.score, 10);
  assert.match(score(video([recording("r", "Tutorial Sample", 0, 8)]), trimmed).rules.asked.note, /MISS 8s long \(5 to 6.5s wanted\)/);
});

test("hidden words overlap nothing: a copy showing one of three option words is clean", () => {
  const option = (string, x, hidden) => ({ ...text(string, x, 6, 13), id: `${string}-${x}`, hidden });
  const look = (x, shown) => component("Segmented Control", x, 300, 180, 32,
    [option("Option 1", 2, shown !== 1), option("Option 2", 60, shown !== 2), option("Option 3", 60, shown !== 3)]);
  const result = score(read([look(200, 1), look(540, 2), look(880, 3)]), sheet);
  assert.equal(result.rules.noOverlap.score, 10, result.rules.noOverlap.note);
  // Shown, the second and third words do sit on each other.
  const shown = score(read([component("Segmented Control", 200, 300, 180, 32,
    [option("Option 2", 60, false), option("Option 3", 60, false)])]), sheet);
  assert.ok(shown.rules.noOverlap.score < 10, shown.rules.noOverlap.note);
});
