// Writes the plate rule's answers for 5,472 colours (every 5 degrees of hue,
// four saturations, nineteen lightnesses), computed by the design system's
// own markup.js, so PhotonzCore can be held to them to the hex digit
// (Tests/PhotonzCoreTests/ChipStyleTests.swift, docs/design/markup.md section 3).
// Run: node Scripts/markup-plate-fixture.cjs > docs/design/markup-plate-sweep.tsv
const path = require("path");
global.window = {};
global.document = { readyState: "complete", querySelectorAll: () => [] };
require(path.join(__dirname, "../docs/design/mocks/shared/components/markup.js"));
const m = window.PZ.markup;
const hex = c => "#" + c.map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join("");
function hsl(h, s, l) {
  const k = n => (n + h / 30) % 12, a = s * Math.min(l, 1 - l);
  const f = n => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return [f(0), f(8), f(4)];
}
const out = ["ink\tplate\tonPlate\tinkText\tglass\tonGlass"];
for (let h = 0; h < 360; h += 5)
  for (const s of [0.25, 0.5, 0.75, 1])
    for (let l = 5; l <= 95; l += 5) {
      const ink = hex(hsl(h, s, l / 100));
      const p = m.plateFor(ink);
      out.push([ink, p.plate, p.onPlate, p.inkText, p.glass, p.onGlass].join("\t"));
    }
console.log(out.join("\n"));
