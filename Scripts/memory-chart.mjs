#!/usr/bin/env node
// Draws what Scripts/memory-watch.sh recorded: one line per program (Photonz
// and each helper it started), megabytes against minutes, as an SVG.
//
//   node Scripts/memory-chart.mjs <samples.csv> <chart.svg> ["title"] [only]
//
// `only` draws just the programs whose name it matches (a regular
// expression): "^Photonz" for the app on its own scale.
//
// Programs are named the way Activity Monitor names them, and the chat model
// server and the picture model get the names a person would recognise.
import fs from 'node:fs';

const [csvPath, outPath, title = 'Memory over the session', only] = process.argv.slice(2);
if (!csvPath || !outPath) {
  console.error('usage: memory-chart.mjs <samples.csv> <chart.svg> ["title"]');
  process.exit(2);
}

const friendly = (name) => {
  if (/^Photonz/.test(name)) return 'Photonz';
  if (name === 'llama-server') return 'Ask chat model (llama-server)';
  if (/^python/.test(name)) return 'Ask picture model (python)';
  return name;
};

const rows = fs.readFileSync(csvPath, 'utf8').trim().split('\n').slice(1)
  .map((line) => line.split(','))
  .filter((f) => f.length >= 4 && f[2] && !/^(zsh|bash|sh|sleep|uv)$/.test(f[2]))
  .filter((f) => !only || new RegExp(only).test(f[2]))
  .map(([s, pid, name, bytes]) => ({ s: Number(s), pid, name: friendly(name), mb: Number(bytes) / 1048576 }));

const series = new Map();
for (const r of rows) {
  if (!series.has(r.name)) series.set(r.name, []);
  series.get(r.name).push(r);
}
// Two of one program at once (a helper restarted) are summed per sample.
for (const [name, points] of series) {
  const byTime = new Map();
  for (const p of points) byTime.set(p.s, (byTime.get(p.s) ?? 0) + p.mb);
  series.set(name, [...byTime].map(([s, mb]) => ({ s, mb })).sort((a, b) => a.s - b.s));
}

const W = 760, H = 560, L = 70, R = 20, T = 50, B = 150;
const maxS = Math.max(60, ...rows.map((r) => r.s));
const maxMB = Math.max(100, ...[...series.values()].flat().map((p) => p.mb));
const niceTop = Math.ceil(maxMB / 500) * 500;
const x = (s) => L + (s / maxS) * (W - L - R);
const y = (mb) => H - B - (mb / niceTop) * (H - T - B);
const colours = ['#2f6fdb', '#d9534f', '#e0a020', '#3a9d5d', '#8a55c9'];

let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" font-family="-apple-system, Helvetica, sans-serif">\n`;
svg += `<rect width="${W}" height="${H}" fill="#ffffff"/>\n`;
svg += `<text x="${L}" y="28" font-size="16" font-weight="600" fill="#1d1d1f">${title}</text>\n`;
for (let mb = 0; mb <= niceTop; mb += niceTop / 5) {
  svg += `<line x1="${L}" x2="${W - R}" y1="${y(mb)}" y2="${y(mb)}" stroke="#e5e5ea"/>`;
  svg += `<text x="${L - 8}" y="${y(mb) + 4}" font-size="11" text-anchor="end" fill="#6e6e73">${Math.round(mb)} MB</text>\n`;
}
const stepMin = maxS > 1200 ? 5 : maxS > 300 ? 1 : 0.5;
for (let m = 0; m * 60 <= maxS; m += stepMin) {
  svg += `<text x="${x(m * 60)}" y="${H - B + 18}" font-size="11" text-anchor="middle" fill="#6e6e73">${m}</text>`;
}
svg += `<text x="${(L + W - R) / 2}" y="${H - B + 34}" font-size="12" text-anchor="middle" fill="#6e6e73">minutes</text>\n`;
let i = 0;
for (const [name, points] of series) {
  const colour = colours[i % colours.length];
  // A gap of more than a minute is the program not running: the line breaks.
  const d = points.map((p, k) => `${k && p.s - points[k - 1].s <= 60 ? 'L' : 'M'}${x(p.s).toFixed(1)},${y(p.mb).toFixed(1)}`).join(' ');
  svg += `<path d="${d}" fill="none" stroke="${colour}" stroke-width="2"/>\n`;
  const peak = Math.max(...points.map((p) => p.mb));
  const last = points[points.length - 1].mb;
  const ly = H - B + 50 + Math.floor(i / 2) * 40;
  const lx = L + (i % 2) * 330;
  svg += `<rect x="${lx}" y="${ly - 9}" width="12" height="12" rx="2" fill="${colour}"/>`;
  svg += `<text x="${lx + 18}" y="${ly + 1}" font-size="12" fill="#1d1d1f">${name}</text>`;
  svg += `<text x="${lx + 18}" y="${ly + 17}" font-size="11" fill="#6e6e73">peak ${Math.round(peak)} MB, last ${Math.round(last)} MB</text>\n`;
  i += 1;
}
svg += '</svg>\n';
fs.writeFileSync(outPath, svg);
console.log(`chart: ${outPath} (${series.size} program(s), ${rows.length} samples over ${(maxS / 60).toFixed(1)} min)`);
