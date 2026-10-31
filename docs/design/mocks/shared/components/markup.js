/* MARKUP — behaviour for markup.css: ink → legible plate, status markers, and
   the ten arrow styles. Idempotent upgrade pass; a no-op on a page with no
   `.mu-chip`, `svg.mu-arrow` or `[data-ink]`. Rules: docs/design/markup.md.
   Publishes window.PZ.markup for pages that build marks in script. */
(function () {
  "use strict";
  const PZ = (window.PZ = window.PZ || {});
  if (PZ.markup) return;

  // ---------- Ink → plate ----------
  // The line keeps the ink as picked. The plate behind the words is derived so
  // the words reach 4.8:1 (4.5 plus margin for the lit gradients): a mid or
  // dark ink is darkened just enough for white words; a light ink whose
  // darkening would pass 22 percent keeps its colour and takes dark words.
  const hex2rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
  const rgb2hex = c => "#" + c.map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join("");
  const lum = c => { const l = c.map(v => (v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)); return .2126 * l[0] + .7152 * l[1] + .0722 * l[2]; };
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };
  const WHITE = [1, 1, 1], DARK = hex2rgb("#1d1d1f");
  function darkenUntil(c, against, target) {
    for (let k = 0; k <= 1.0001; k += .01) { const d = c.map(v => v * (1 - k)); if (ratio(d, against) >= target) return [d, k]; }
    return [[0, 0, 0], 1];
  }
  // Glass lets the picture through, so its plate is judged over the worst
  // picture behind it: at GLASS_ALPHA opacity the words must reach 4.8:1 over
  // pure white AND pure black. White words take a darkened tint, dark words a
  // lightened one, whichever moves the colour less.
  const GLASS_ALPHA = .82, BLACK = [0, 0, 0];
  const over = (c, bg, a) => c.map((v, i) => v * a + bg[i] * (1 - a));
  function glassFor(ink) {
    const okWhite = g => ratio(over(g, WHITE, GLASS_ALPHA), WHITE) >= 4.8 && ratio(over(g, BLACK, GLASS_ALPHA), WHITE) >= 4.8;
    const okDark = g => ratio(over(g, WHITE, GLASS_ALPHA), DARK) >= 4.8 && ratio(over(g, BLACK, GLASS_ALPHA), DARK) >= 4.8;
    let a = null, b = null;
    for (let k = 0; k <= 1.0001 && !a; k += .01) { const g = ink.map(v => v * (1 - k)); if (okWhite(g)) a = [g, k]; }
    for (let m = 0; m <= 1.0001 && !b; m += .01) { const g = ink.map(v => v + (1 - v) * m); if (okDark(g)) b = [g, m]; }
    const darkWords = b && (!a || b[1] < a[1]);
    const [g] = darkWords ? b : a;
    const worst = Math.min(...[WHITE, BLACK].map(bg => ratio(over(g, bg, GLASS_ALPHA), darkWords ? DARK : WHITE)));
    return { glass: rgb2hex(g), onGlass: darkWords ? "#1d1d1f" : "#ffffff", glassContrast: worst };
  }
  function plateFor(hex) {
    const ink = hex2rgb(hex);
    const [dark, k] = darkenUntil(ink, WHITE, 4.8);
    const darkWords = k > .22 && ratio(ink, DARK) >= 4.5;
    const plate = darkWords ? ink : dark;
    return Object.assign({
      ink: hex, plate: rgb2hex(plate), onPlate: darkWords ? "#1d1d1f" : "#ffffff",
      inkText: rgb2hex(darkenUntil(ink, WHITE, 4.6)[0]),  // 4.6 so rounding to a byte keeps 4.5
      contrast: ratio(plate, darkWords ? DARK : WHITE),
    }, glassFor(ink));
  }
  function setInk(el, hex) {
    const p = plateFor(hex);
    el.style.setProperty("--mu-ink", hex);
    el.style.setProperty("--mu-plate", p.plate);
    el.style.setProperty("--mu-on-plate", p.onPlate);
    el.style.setProperty("--mu-ink-text", p.inkText);
    el.style.setProperty("--mu-glass", p.glass);
    el.style.setProperty("--mu-on-glass", p.onGlass);
    el.style.setProperty("--mu-glass-shadow", p.onGlass === "#ffffff" ? "0 1px 2px rgba(0,0,0,.45)" : "0 1px 1px rgba(255,255,255,.35)");
    return p;
  }

  // ---------- Markers ----------
  // Status colours keep their meaning on any ink. On an ink-filled plate the
  // icon sits on a white disc with its colour in the glyph; on a light or
  // graphite plate it is the coloured disc with a white glyph (dark on yellow).
  const SEM = { error: "#ff3b30", warning: "#ffcc00", success: "#34c759", info: "#0a84ff" };
  const SEM_ON_WHITE = { error: "#ff3b30", warning: "#ff9500", success: "#28a745", info: "#0a84ff" };
  const FILLED = new Set(["today", "solid", "squircle", "glass", "tag", "twotone"]);
  function icon(kind, disc, glyph) {
    const g = {
      error: `<path d="M6.6 6.6 13.4 13.4M13.4 6.6 6.6 13.4" stroke="${glyph}" stroke-width="2.2" stroke-linecap="round"/>`,
      success: `<path d="M5.7 10.4 8.7 13.3 14.4 7.3" fill="none" stroke="${glyph}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>`,
      info: `<path d="M10 9.2V14.3" stroke="${glyph}" stroke-width="2.2" stroke-linecap="round"/><circle cx="10" cy="6.2" r="1.35" fill="${glyph}"/>`,
      warning: `<path d="M10 7.6V11.6" stroke="${glyph}" stroke-width="2.1" stroke-linecap="round"/><circle cx="10" cy="14.4" r="1.25" fill="${glyph}"/>`,
    }[kind];
    const shape = kind === "warning"
      ? `<path d="M10 2.2 18.4 17.2H1.6Z" fill="${disc}" stroke="${disc}" stroke-width="1.6" stroke-linejoin="round"/>`
      : `<circle cx="10" cy="10" r="9" fill="${disc}"/>`;
    return `<svg viewBox="0 0 20 20" aria-hidden="true">${shape}${g}</svg>`;
  }
  function markerIcon(kind, chipStyle) {
    if (!SEM[kind]) return "";
    return FILLED.has(chipStyle)
      ? icon(kind, "#fff", SEM_ON_WHITE[kind])
      : icon(kind, SEM[kind], kind === "warning" ? "#1d1d1f" : "#fff");
  }

  // ---------- Arrow styles ----------
  // Stand-ins for the app's rasterizer (ArrowStyle.swift, HandMadeArrow.swift):
  // the same arrow, the same two ends and colour, painted ten ways. P0 tail,
  // P1 the bend, P2 the tip; k scales weights (tiles draw at about .7).
  function arrow(style, P0, P1, P2, k = 1) {
    const B = t => [0, 1].map(i => (1 - t) ** 2 * P0[i] + 2 * (1 - t) * t * P1[i] + t * t * P2[i]);
    const D = t => [0, 1].map(i => 2 * (1 - t) * (P1[i] - P0[i]) + 2 * t * (P2[i] - P1[i]));
    const unit = v => { const l = Math.hypot(v[0], v[1]) || 1; return [v[0] / l, v[1] / l]; };
    const u = unit(D(1)), n = [-u[1], u[0]];
    const at = (p, a, b) => [p[0] + a * u[0] + b * n[0], p[1] + a * u[1] + b * n[1]];
    const pt = p => p[0].toFixed(1) + " " + p[1].toFixed(1);
    const tip = P2, L = 11 * k, W = 6 * k;
    const sty = (w, extra = "") => `style="stroke-width:${w};${extra}"`;
    const sample = (t0, t1, steps, wob) => {
      const out = [];
      for (let i = 0; i <= steps; i++) {
        const t = t0 + (t1 - t0) * i / steps, p = B(t), nn = unit(D(t));
        const w = wob ? (Math.sin(t * 9.5) * .7 + Math.sin(t * 23) * .3) * wob : 0;
        out.push([p[0] - nn[1] * w, p[1] + nn[0] * w]);
      }
      return out;
    };
    const poly = pts => "M " + pts.map(pt).join(" L ");
    const solidHead = () => `<path class="mu-fill" d="M ${pt(tip)} L ${pt(at(tip, -L, W))} L ${pt(at(tip, -L, -W))} Z"/>`;
    const chevron = (w, extra = "") => `<path d="M ${pt(at(tip, -L, W))} L ${pt(tip)} L ${pt(at(tip, -L, -W))}" ${sty(w, "stroke-linejoin:round;" + extra)}/>`;
    switch (style) {
      case "handDrawn":
        return `<path d="${poly(sample(0, 1, 28, .8 * k))}" ${sty(1.6 * k, "stroke-linejoin:round")}/>`
          + `<path d="M ${pt(at(tip, -L * 1.05, W * 1.05))} Q ${pt(at(tip, -L * .45, W * .25))} ${pt(tip)} Q ${pt(at(tip, -L * .5, -W * .2))} ${pt(at(tip, -L * .95, -W * .95))}" ${sty(1.6 * k, "stroke-linejoin:round")}/>`;
      case "marker":
        return `<path d="${poly(sample(0, .985, 24, .6 * k))}" ${sty(4.6 * k, "stroke-linejoin:round;opacity:.96")}/>`
          + `<path d="M ${pt(at(tip, -L * 1.1, W * 1.15))} L ${pt(at(tip, .5 * k, .6 * k))}" ${sty(4.2 * k, "opacity:.96")}/>`
          + `<path d="M ${pt(at(tip, -1 * k, -.4 * k))} L ${pt(at(tip, -L, -W * 1.2))}" ${sty(4.2 * k, "opacity:.96")}/>`;
      case "brush": {
        const left = [], right = [];
        for (let i = 0; i <= 24; i++) {
          const t = i / 24 * .93, p = B(t), nn = unit(D(t));
          const w = (0.3 + 2.6 * Math.sin(Math.PI * Math.min(1, t * 1.15)) ** .8) * k;
          left.push([p[0] - nn[1] * w, p[1] + nn[0] * w]); right.push([p[0] + nn[1] * w, p[1] - nn[0] * w]);
        }
        const body = "M " + left.map(pt).join(" L ") + " L " + right.reverse().map(pt).join(" L ") + " Z";
        const wing = s => `M ${pt(at(tip, .8 * k, 0))} Q ${pt(at(tip, -L * .35, W * .45 * s))} ${pt(at(tip, -L * 1.3, W * 1.3 * s))} Q ${pt(at(tip, -L * .9, W * .45 * s))} ${pt(at(tip, -L * .35, -W * .12 * s))} Z`;
        return `<path class="mu-fill" d="${body}"/><path class="mu-fill" d="${wing(1)}"/><path class="mu-fill" d="${wing(-1)}"/>`;
      }
      case "sketch": {
        const hw = 2.6 * k, HL = 13 * k, HW = 8 * k, a = [], b = [];
        for (let i = 0; i <= 12; i++) {
          const t = i / 12 * .82, p = B(t), nn = unit(D(t));
          a.push([p[0] - nn[1] * hw, p[1] + nn[0] * hw]); b.push([p[0] + nn[1] * hw, p[1] - nn[0] * hw]);
        }
        const out = "M " + a.map(pt).join(" L ") + ` L ${pt(at(tip, -HL, hw))} L ${pt(at(tip, -HL, HW))} L ${pt(tip)} L ${pt(at(tip, -HL, -HW))} L ${pt(at(tip, -HL, -hw))} L ` + b.reverse().map(pt).join(" L ") + " Z";
        return `<path d="${out}" ${sty(1.3 * k, `stroke-linejoin:round;stroke-dasharray:${26 * k} ${2.5 * k} ${12 * k} ${1.8 * k}`)}/>`
          + `<path d="${out}" transform="translate(${.7 * k} ${.5 * k})" ${sty(1 * k, `stroke-linejoin:round;opacity:.75;stroke-dasharray:${18 * k} ${3 * k} ${30 * k} ${2 * k}`)}/>`;
      }
      case "dashed":
        return `<path d="M ${pt(P0)} Q ${pt(P1)} ${pt(at(tip, -L * .6, 0))}" ${sty(2 * k, `stroke-dasharray:${6 * k} ${4 * k};stroke-linecap:butt`)}/>` + solidHead();
      case "block": {
        const left = [], right = [], HL = 14 * k, HW = 10 * k;
        for (let i = 0; i <= 16; i++) {
          const t = i / 16 * .78, p = B(t), nn = unit(D(t)), w = (1.4 + 3.2 * t / .78) * k;
          left.push([p[0] - nn[1] * w, p[1] + nn[0] * w]); right.push([p[0] + nn[1] * w, p[1] - nn[0] * w]);
        }
        const d = "M " + left.map(pt).join(" L ") + ` L ${pt(at(tip, -HL, HW))} L ${pt(tip)} L ${pt(at(tip, -HL, -HW))} L ` + right.reverse().map(pt).join(" L ") + " Z";
        return `<path class="mu-fill" d="${d}" style="stroke:var(--mu-ink);stroke-width:${k};stroke-linejoin:round"/>`;
      }
      case "neon": {
        const line = `M ${pt(P0)} Q ${pt(P1)} ${pt(at(tip, -1 * k, 0))}`;
        const core = "stroke:color-mix(in srgb, var(--mu-ink) 35%, #fff)";
        return `<g style="filter:drop-shadow(0 0 ${2.5 * k}px var(--mu-ink)) drop-shadow(0 0 ${6 * k}px var(--mu-ink))"><path d="${line}" ${sty(3.2 * k)}/>${chevron(3.2 * k)}</g>`
          + `<path d="${line}" ${sty(1.1 * k, core)}/>` + chevron(1.1 * k, core);
      }
      case "dotted":
        return `<path d="M ${pt(P0)} Q ${pt(P1)} ${pt(at(tip, -2.5 * k, 0))}" ${sty(2.8 * k, `stroke-dasharray:0 ${6.5 * k}`)}/>`
          + `<circle class="mu-fill" cx="${P0[0]}" cy="${P0[1]}" r="${3.2 * k}"/>` + chevron(2.3 * k);
      case "elbow": {
        const c = [P2[0], P0[1]], r = 7 * k, sx = Math.sign(c[0] - P0[0]) || 1, sy = Math.sign(P2[1] - c[1]) || 1;
        const uu = [0, sy], nn2 = [-uu[1], uu[0]];
        const at2 = (p, a, b) => [p[0] + a * uu[0] + b * nn2[0], p[1] + a * uu[1] + b * nn2[1]];
        return `<path d="M ${pt(P0)} L ${pt([c[0] - sx * r, c[1]])} Q ${pt(c)} ${pt([c[0], c[1] + sy * r])} L ${pt(at2(tip, -L * .6, 0))}" ${sty(2 * k, "stroke-linejoin:round")}/>`
          + `<path class="mu-fill" d="M ${pt(tip)} L ${pt(at2(tip, -L, W))} L ${pt(at2(tip, -L, -W))} Z"/>`
          + `<circle class="mu-fill" cx="${P0[0]}" cy="${P0[1]}" r="${2.4 * k}"/>`;
      }
      default: // clean
        return `<path d="M ${pt(P0)} Q ${pt(P1)} ${pt(at(tip, -L * .6, 0))}" ${sty(2 * k)}/>` + solidHead();
    }
  }

  const CHIPS = [
    ["today", "Today"], ["solid", "Solid pill"], ["squircle", "Flat squircle"], ["hairline", "Hairline plate"], ["glass", "Glass"],
    ["paper", "Paper"], ["spec", "Spec badge"], ["tag", "Lit tag"], ["twotone", "Two-tone badge"], ["highlight", "Highlighter"],
  ];
  const ARROWS = [
    ["clean", "Clean"], ["handDrawn", "Hand-drawn"], ["marker", "Marker"], ["brush", "Brush"], ["sketch", "Sketch"],
    ["dashed", "Dashed"], ["block", "Block"], ["neon", "Neon"], ["dotted", "Dotted"], ["elbow", "Elbow"],
  ];
  const MARKERS = [["none", "None"], ["accent", "Accent"], ["error", "Error"], ["warning", "Warning"], ["success", "Done"], ["info", "Info"]];
  const PALETTE = ["#ff375f", "#ff9f0a", "#ffd60a", "#30d158", "#0a84ff", "#bf5af2", "#1d1d1f", "#ffffff"];

  const nums = s => (s || "").split(",").map(Number);
  function paint(root = document) {
    // The root itself may carry the ink (a page or a scene), not only its children.
    if (root.dataset && root.dataset.ink) setInk(root, root.dataset.ink);
    root.querySelectorAll("[data-ink]").forEach(el => setInk(el, el.dataset.ink));
    root.querySelectorAll(".mu-chip[data-marker]").forEach(chip => {
      let mk = chip.querySelector(":scope > .mu-mk");
      const html = markerIcon(chip.dataset.marker, chip.dataset.chip);
      if (!html) { if (mk) mk.remove(); return; }
      if (!mk) { mk = document.createElement("span"); mk.className = "mu-mk"; chip.prepend(mk); }
      mk.innerHTML = html;
    });
    root.querySelectorAll("svg.mu-arrow[data-from][data-to]").forEach(svg => {
      const P0 = nums(svg.dataset.from), P2 = nums(svg.dataset.to);
      const P1 = svg.dataset.via ? nums(svg.dataset.via) : [(P0[0] + P2[0]) / 2, (P0[1] + P2[1]) / 2];
      svg.innerHTML = arrow(svg.dataset.arrow || "clean", P0, P1, P2, Number(svg.dataset.weight || 1));
    });
  }

  PZ.markup = { plateFor, glassFor: hex => glassFor(hex2rgb(hex)), GLASS_ALPHA, setInk, icon, markerIcon, arrow, paint, contrast: (a, b) => ratio(hex2rgb(a), hex2rgb(b)), CHIPS, ARROWS, MARKERS, PALETTE };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => paint());
  else paint();
})();
