// Rule scores for one eval case, read from the document (read_document), never
// from the picture: words over words or over a control, things meant to line up
// that do not, too many type sizes, asked-for items missing, anything off the
// canvas. Each rule scores 0 to 10, or is left out when it does not apply; the
// case's rule score is their mean. See Scripts/ask-eval/README.md.

const EDGE = 1.5; // points: two edges this close are the same edge

/// Every layer in the read with its frame on the canvas, top first. A child's
/// frame is measured from its group's top left (read_document), so it is moved
/// by every group above it.
export function flatten(layers, origin = { x: 0, y: 0 }, parent = null, out = []) {
  for (const layer of layers ?? []) {
    const frame = { x: origin.x + layer.frame.x, y: origin.y + layer.frame.y, width: layer.frame.width, height: layer.frame.height };
    const node = { layer, frame, parent, depth: parent ? parent.depth + 1 : 0 };
    out.push(node);
    if (layer.children) flatten(layer.children, { x: frame.x, y: frame.y }, node, out);
  }
  return out;
}

/// The layers the run made: everything but the picture it started on (a locked
/// Background, or an image that covers the canvas).
export function made(read) {
  const canvas = read.canvas;
  const isBase = (layer) => layer.kind === "image" && (layer.name === "Background" || layer.locked
    || (Math.abs(layer.frame.width - canvas.width) < 2 && Math.abs(layer.frame.height - canvas.height) < 2));
  return (read.layers ?? []).filter((layer) => !isBase(layer));
}

const area = (f) => Math.max(0, f.width) * Math.max(0, f.height);
function overlap(a, b) {
  const w = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
  const h = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
  return w > 1 && h > 1 ? w * h : 0;
}
const contains = (outer, inner, slack = 1) => inner.x >= outer.x - slack && inner.y >= outer.y - slack
  && inner.x + inner.width <= outer.x + outer.width + slack && inner.y + inner.height <= outer.y + outer.height + slack;
function gapBetween(a, b) {
  const dx = Math.max(0, Math.max(a.x, b.x) - Math.min(a.x + a.width, b.x + b.width));
  const dy = Math.max(0, Math.max(a.y, b.y) - Math.min(a.y + a.height, b.y + b.height));
  return Math.hypot(dx, dy);
}
const ancestors = (node) => { const out = new Set(); for (let p = node.parent; p; p = p.parent) out.add(p); return out; };
// A part's name as a whole word, plurals too: "smile" is not "Smiley".
const named = (node, pattern) => new RegExp(`\\b(${pattern})(s|es)?\\b`, "i").test(node.layer.name ?? "");
const texts = (nodes) => nodes.filter((n) => n.layer.kind === "text");
const words = (node) => node.layer.text?.string ?? "";

// MARK: The rules

/// Everything the run made sits on the canvas.
function onCanvas(nodes, read) {
  const top = nodes.filter((n) => n.depth === 0);
  if (!top.length) return null;
  const canvas = { x: 0, y: 0, width: read.canvas.width, height: read.canvas.height };
  const off = top.filter((n) => !contains(canvas, n.frame, 2));
  return { score: Math.max(0, 10 - 3 * off.length), note: off.length ? `${off.length} of ${top.length} off the canvas: ${off.map((n) => n.layer.name).join(", ")}` : "all on the canvas" };
}

/// No words over other words, over a control, or half over a shape. Words
/// wholly inside a shape are on a backdrop, which is fine.
function noOverlap(nodes) {
  const all = texts(nodes);
  if (!all.length) return null;
  const bad = [];
  for (const text of all) {
    const mine = ancestors(text);
    for (const other of nodes) {
      if (other === text || mine.has(other) || ancestors(other).has(text)) continue;
      if (!overlap(text.frame, other.frame)) continue;
      const kind = other.layer.kind;
      const over = kind === "text" || kind === "component" || kind === "image" || kind === "measurement"
        || kind === "clip" || !contains(other.frame, text.frame, 2);
      if (over) { bad.push(`"${words(text).slice(0, 24)}" over ${other.layer.name}`); break; }
    }
  }
  // One overlap is a visible defect, so each costs a quarter of the score.
  return { score: Math.max(0, 10 - 2.5 * bad.length), note: bad.length ? `${bad.length} of ${all.length} words overlap: ${bad.slice(0, 4).join("; ")}` : "no words overlap" };
}

/// One type scale: at most four sizes, four weights, two fonts.
function typeScale(nodes) {
  const all = texts(nodes);
  if (all.length < 2) return null;
  const sizes = new Set(all.map((n) => Math.round(n.layer.text.size)));
  const weights = new Set(all.map((n) => n.layer.text.weight));
  const fonts = new Set(all.map((n) => n.layer.text.font));
  const score = Math.max(0, 10 - 2.5 * Math.max(0, sizes.size - 4) - 2 * Math.max(0, weights.size - 4) - 2 * Math.max(0, fonts.size - 2));
  return { score, note: `${sizes.size} sizes (${[...sizes].sort((a, b) => a - b).join(", ")}), ${weights.size} weights, ${fonts.size} fonts` };
}

/// The things a sheet is made of: a component, words, a drawn piece, or a group
/// of plain pieces (a cell). A group holding groups or components is a
/// container and is looked inside; a backdrop holding two or more things is
/// left out, since what it holds is what lines up.
export function cells(nodes) {
  const top = nodes.filter((n) => n.depth === 0);
  const out = [];
  const visit = (node) => {
    const kids = nodes.filter((n) => n.parent === node);
    const container = (node.layer.kind === "group" || node.layer.kind === "frame")
      && kids.some((k) => k.layer.kind === "group" || k.layer.kind === "frame" || k.layer.kind === "component");
    if (container) { kids.forEach(visit); return; }
    out.push(node);
  };
  top.forEach(visit);
  // A rule line between rows is a divider, not a cell.
  return out.filter((cell) => !(cell.layer.kind === "shape" && ["line", "arrow"].includes(cell.layer.shape?.shape))).filter((cell) => !(cell.layer.kind === "shape" || cell.layer.kind === "path")
    || out.filter((other) => other !== cell && contains(cell.frame, other.frame, 1)).length < 2);
}

/// Things line up: each cell shares an edge or a centre with another across
/// and down, and gaps between neighbours in a row or column are equal.
function alignment(nodes) {
  const items = cells(nodes);
  if (items.length < 3) return null;
  const xs = (f) => [f.x, f.x + f.width / 2, f.x + f.width];
  const ys = (f) => [f.y, f.y + f.height / 2, f.y + f.height];
  const shares = (a, b, pick) => pick(a).some((p, i) => Math.abs(p - pick(b)[i]) <= EDGE);
  // Lined up both ways counts whole, one way (a title over a grid) half.
  let aligned = 0;
  for (const item of items) {
    const across = items.some((o) => o !== item && shares(item.frame, o.frame, xs));
    const down = items.some((o) => o !== item && shares(item.frame, o.frame, ys));
    aligned += (across ? 0.5 : 0) + (down ? 0.5 : 0);
  }
  const fraction = aligned / items.length;
  // Rows and columns of pieces (words are left out: a label's gap to its row
  // is not a gap between cells): middles in each other's span, gaps in order.
  const pieces = items.filter((i) => i.layer.kind !== "text");
  const spread = [];
  for (const [lineOf, start, end] of [
    [(a, b) => Math.abs((a.y + a.height / 2) - (b.y + b.height / 2)) < Math.min(a.height, b.height) / 2, "x", "width"],
    [(a, b) => Math.abs((a.x + a.width / 2) - (b.x + b.width / 2)) < Math.min(a.width, b.width) / 2, "y", "height"],
  ]) {
    const seen = new Set();
    for (const item of pieces) {
      if (seen.has(item)) continue;
      const line = pieces.filter((o) => lineOf(item.frame, o.frame));
      line.forEach((o) => seen.add(o));
      if (line.length < 3) continue;
      line.sort((a, b) => a.frame[start] - b.frame[start]);
      // Equal gaps, or equal steps from middle to middle (a grid of cells of
      // different sizes): whichever the line keeps better.
      const gaps = [], steps = [];
      for (let i = 1; i < line.length; i += 1) {
        gaps.push(line[i].frame[start] - (line[i - 1].frame[start] + line[i - 1].frame[end]));
        steps.push(line[i].frame[start] + line[i].frame[end] / 2 - (line[i - 1].frame[start] + line[i - 1].frame[end] / 2));
      }
      if (gaps.some((g) => g < -1)) { spread.push(1); continue; } // they overlap
      const unevenness = (values) => {
        const mean = values.reduce((s, g) => s + g, 0) / values.length;
        const sd = Math.sqrt(values.reduce((s, g) => s + (g - mean) ** 2, 0) / values.length);
        return mean > 0 ? Math.min(1, sd / mean) : 1;
      };
      spread.push(Math.min(unevenness(gaps), unevenness(steps)));
    }
  }
  const even = spread.length ? 1 - spread.reduce((s, v) => s + v, 0) / spread.length : null;
  const score = even === null ? 10 * fraction : 10 * (0.6 * fraction + 0.4 * even);
  return { score, note: `${Math.round(fraction * 100)}% of ${items.length} cells line up across and down${even === null ? ", no row of three to space" : `, gaps ${Math.round(even * 100)}% even over ${spread.length} rows and columns`}` };
}

/// A drawing is placed on purpose: centred and a sensible size on the canvas.
function composed(nodes, read) {
  const { width, height } = read.canvas;
  // The drawn pieces, not the groups holding them, and not a backdrop that
  // covers the canvas (a coloured ground under the drawing is fine).
  const pieces = nodes.filter((n) => !n.layer.children && area(n.frame) < 0.9 * width * height);
  if (!pieces.length) return null;
  const box = bounds(pieces.map((n) => n.frame));
  const off = Math.hypot((box.x + box.width / 2 - width / 2) / width, (box.y + box.height / 2 - height / 2) / height);
  const fill = Math.max(box.width / width, box.height / height);
  const centred = Math.max(0, 1 - Math.max(0, off - 0.05) / 0.2);
  const sized = fill < 0.25 ? fill / 0.25 : fill > 0.98 ? 0.5 : 1;
  return { score: 10 * centred * sized, note: `drawing ${Math.round(fill * 100)}% of the canvas, ${Math.round(off * 100)}% off centre` };
}

function bounds(frames) {
  const x = Math.min(...frames.map((f) => f.x));
  const y = Math.min(...frames.map((f) => f.y));
  return { x, y, width: Math.max(...frames.map((f) => f.x + f.width)) - x, height: Math.max(...frames.map((f) => f.y + f.height)) - y };
}

/// Every asked-for item is there, labelled, and in its place.
function asked(nodes, read, expect) {
  const checks = [];
  const check = (ok, note) => checks.push({ ok: Boolean(ok), note });
  const allTexts = texts(nodes);
  const said = allTexts.map(words).join("\n");

  if (expect.words === false) {
    const top = allTexts.filter((t) => !t.parent);
    check(top.length === 0, top.length ? `words on a drawing that needed none: ${top.map(words).join(", ").slice(0, 60)}` : "no stray words");
  }
  for (const part of expect.parts ?? []) {
    const found = nodes.filter((n) => named(n, part.name)).length;
    check(found >= (part.count ?? 1), `${found} of ${part.count ?? 1} ${part.name.split("|")[0]}`);
  }
  for (const [part, whole] of expect.inside ?? []) {
    const parts = nodes.filter((n) => named(n, part) && !named(n, whole));
    const wholes = nodes.filter((n) => named(n, whole) && !named(n, part));
    for (const p of parts) {
      const inside = wholes.some((w) => overlap(p.frame, w.frame) >= 0.9 * area(p.frame));
      check(inside, `${p.layer.name} ${inside ? "inside" : "NOT inside"} the ${whole.split("|")[0]}`);
    }
    if (!parts.length || !wholes.length) check(false, `no ${part.split("|")[0]} inside a ${whole.split("|")[0]} to check`);
  }
  for (const [part, whole] of expect.touch ?? []) {
    const parts = nodes.filter((n) => named(n, part) && !named(n, whole));
    const wholes = nodes.filter((n) => named(n, whole) && !named(n, part));
    for (const p of parts) {
      const touches = wholes.some((w) => gapBetween(p.frame, w.frame) <= 4);
      check(touches, `${p.layer.name} ${touches ? "touches" : "does NOT touch"} the ${whole.split("|")[0]}`);
    }
  }
  if (expect.icon) {
    const top = nodes.filter((n) => n.depth === 0);
    if (top.length) {
      const box = bounds(top.map((n) => n.frame));
      const square = box.width / box.height;
      const docSquare = read.canvas.width / read.canvas.height;
      const fills = Math.min(box.width, box.height) / Math.min(read.canvas.width, read.canvas.height);
      check(square > 0.85 && square < 1.18, `drawing ${square.toFixed(2)} wide to tall`);
      check(Math.abs(docSquare - 1) < 0.02 || fills >= 0.6, `${Math.abs(docSquare - 1) < 0.02 ? "square canvas" : `fills ${Math.round(fills * 100)}% of a ${read.canvas.width} x ${read.canvas.height} canvas`}`);
    }
  }
  if (expect.title) {
    const sorted = [...allTexts].sort((a, b) => b.layer.text.size - a.layer.text.size);
    const title = sorted[0];
    const others = nodes.filter((n) => n !== title && n.depth === 0 && n.layer.kind !== "text");
    const above = title && others.every((o) => o.frame.y >= title.frame.y + title.frame.height - 2);
    const biggest = title && (sorted.length === 1 || title.layer.text.size > sorted[1].layer.text.size);
    check(title && biggest && above, title ? `title "${words(title).slice(0, 30)}" ${biggest ? "is the largest words" : "shares its size"}${above ? " and sits above" : ", not above everything"}` : "no title");
  }
  if (expect.headers) {
    const found = expect.headers.filter((h) => new RegExp(`\\b(${h})\\b`, "i").test(said));
    check(found.length >= (expect.headersAtLeast ?? expect.headers.length), `${found.length} state headers (${found.map((h) => h.split("|")[0]).join(", ") || "none"})`);
  }
  for (const label of expect.labels ?? []) {
    check(new RegExp(`\\b(${label})`, "i").test(said), `${label.split("|")[0]} ${new RegExp(`\\b(${label})`, "i").test(said) ? "labelled" : "missing"}`);
  }
  if (expect.minCells) {
    const parts = cells(nodes).filter((c) => c.layer.kind !== "text");
    check(parts.length >= expect.minCells, `${parts.length} pieces laid out (at least ${expect.minCells} wanted)`);
  }
  if (expect.rowLabels) {
    const pieces = cells(nodes).filter((c) => c.layer.kind !== "text");
    const rows = [];
    for (const p of [...pieces].sort((a, b) => a.frame.y - b.frame.y)) {
      const row = rows.find((r) => Math.abs((r.y + r.h / 2) - (p.frame.y + p.frame.height / 2)) < Math.min(r.h, p.frame.height) / 2);
      if (row) row.items.push(p); else rows.push({ y: p.frame.y, h: p.frame.height, items: [p] });
    }
    const labelled = rows.filter((r) => {
      const left = Math.min(...r.items.map((i) => i.frame.x));
      return allTexts.some((t) => t.frame.x + t.frame.width <= left + 2 && t.frame.y < r.y + r.h && t.frame.y + t.frame.height > r.y);
    });
    check(rows.length >= 2 && labelled.length === rows.length, `${labelled.length} of ${rows.length} rows have a label on their left`);
  }
  if (expect.prices) {
    const prices = allTexts.filter((t) => /(^|\s)(\$|€|£)\s?\d|\b\d+\s?(\/|per)\s?(mo|month|yr|year)|\bfree\b/i.test(words(t)));
    check(prices.length >= expect.prices, `${prices.length} prices (at least ${expect.prices} wanted)`);
  }
  if (expect.minMeasurements) {
    const count = nodes.filter((n) => n.layer.kind === "measurement").length;
    check(count >= expect.minMeasurements && count <= (expect.maxMeasurements ?? Infinity),
      `${count} measurements (${expect.minMeasurements} to ${expect.maxMeasurements ?? "any"} wanted)`);
  }
  if (!checks.length) return null;
  const passed = checks.filter((c) => c.ok).length;
  return { score: 10 * passed / checks.length, note: checks.map((c) => `${c.ok ? "ok" : "MISS"} ${c.note}`).join("; ") };
}

/// The rule scores for one case: { score, rules: { name: { score, note } } }.
export function score(read, testCase) {
  const expect = testCase.expect ?? {};
  const mine = made(read);
  if (!mine.length) return { score: 0, rules: { made: { score: 0, note: "nothing was made" } } };
  const nodes = flatten(mine);
  const drawing = testCase.group === "drawing";
  const laidOut = testCase.group === "sheet" || testCase.group === "layout";
  const rules = {
    onCanvas: onCanvas(nodes, read),
    noOverlap: drawing ? null : noOverlap(nodes),
    typeScale: laidOut ? typeScale(nodes) : null,
    alignment: laidOut ? alignment(nodes) : null,
    composed: drawing ? composed(nodes, read) : null,
    asked: asked(nodes, read, expect),
  };
  for (const key of Object.keys(rules)) if (rules[key] === null) delete rules[key];
  for (const rule of Object.values(rules)) rule.score = Math.round(rule.score * 10) / 10;
  const values = Object.values(rules).map((r) => r.score);
  return { score: Math.round(values.reduce((s, v) => s + v, 0) / values.length * 10) / 10, rules };
}
