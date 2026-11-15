#!/usr/bin/env node
// The best four and the worst four cases of a run, as one reel for a person to
// watch: each case's own reel (the exported SVG as WebKit plays it, two laps)
// one after another: the best four from the best down, then the worst four
// from the worst up, a white second between them. (This Mac's ffmpeg has no
// drawtext, so the order is the label.)
//
//   node Scripts/ask-eval/ends-reel.mjs <run>
//
// Written where the run is (`.ask-eval/runs/<run>/` or
// `.ask-eval/held-out-runs/<run>/`), as ends-reel.mp4. It prints only the
// path, never a case, so a held-out run stays read in total (README, "The
// held-out set"): a runner draws it for the user's audit after its last change
// and never opens it.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const repo = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const id = process.argv[2];
if (!id) { console.error("usage: ends-reel.mjs <run>"); process.exit(1); }
const runDir = ["runs", "held-out-runs"].map((d) => path.join(repo, ".ask-eval", d, id)).find((d) => existsSync(path.join(d, "run.json")));
if (!runDir) { console.error(`no run ${id}`); process.exit(1); }
const meta = JSON.parse(readFileSync(path.join(runDir, "run.json"), "utf8"));
const scored = Object.entries(meta.cases)
  .filter(([caseID, r]) => !r.unrun && existsSync(path.join(runDir, caseID, "reel.gif")))
  .sort((a, b) => b[1].score - a[1].score);
const best = scored.slice(0, 4).map(([c]) => ({ c }));
const worst = scored.slice(-4).reverse().map(([c]) => ({ c }));
const picked = [...best, ...worst.filter((w) => !best.some((b) => b.c === w.c))];
if (!picked.length) { console.error("no reels in that run"); process.exit(1); }
const args = ["-y", "-loglevel", "error"];
for (const p of picked) args.push("-stream_loop", "1", "-i", path.join(runDir, p.c, "reel.gif"));
const chains = picked.map((p, i) => `[${i}:v]scale=480:480:force_original_aspect_ratio=decrease,pad=480:480:(ow-iw)/2:(oh-ih)/2:white,` +
  `setsar=1,fps=30,tpad=stop_mode=add:stop_duration=1:color=white[v${i}]`);
const filter = `${chains.join(";")};${picked.map((_, i) => `[v${i}]`).join("")}concat=n=${picked.length}:v=1:a=0,format=yuv420p[out]`;
const out = path.join(runDir, "ends-reel.mp4");
// Quiet on failure too: an error would print the cases it was given.
try { execFileSync("ffmpeg", [...args, "-filter_complex", filter, "-map", "[out]", out], { stdio: "ignore" }); }
catch { console.error("!! ffmpeg could not make the reel"); process.exit(1); }
console.log(out);
