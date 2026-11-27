#!/usr/bin/env node
// Measures an exported reel across each of its transitions (task
// 3d-transitions-ease-in-and-out-of-the-picture-in): for every frame of the
// move, how much of the frame is pure black, and how far the picture stepped
// from the frame before.
//
//   Scripts/depth-transition-measure.mjs <reel.mp4> <cuts.json> [lengthSeconds]
//
// cuts.json is what Scripts/depth-transition-drill.mjs writes. Prints one JSON
// object: per kind, the worst black share in the middle half of the move, the
// biggest step, and the hitch count.
//
// Pure black: every channel under 10 of 255, read at 480x270.
// A step: the mean absolute difference between two frames in a row, nought to
// one. A hitch: a frame where the picture jumps (a step over 0.03 and more
// than twice the mean of the steps either side) or stalls between two frames
// that move (both steps beside it over 0.03, it under a quarter of the
// smaller), judged against the frames beside it, since
// an eased move is meant to be fast in its middle and slow at its ends.
// The same rule as DepthTransitionEaseRenderTests.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const [reel, cutsFile, lengthArg] = process.argv.slice(2);
if (!reel || !cutsFile) {
  console.error("usage: depth-transition-measure.mjs <reel.mp4> <cuts.json> [lengthSeconds]");
  process.exit(2);
}
const length = Number(lengthArg ?? 0.8);
const { placed } = JSON.parse(readFileSync(cutsFile, "utf8"));
const W = 480, H = 270;

function frames(from, to) {
  const raw = execFileSync("ffmpeg", ["-v", "error", "-ss", String(from), "-to", String(to), "-i", reel,
                                      "-vf", `scale=${W}:${H}`, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                           { maxBuffer: 1 << 30 });
  const size = W * H * 3;
  const out = [];
  for (let offset = 0; offset + size <= raw.length; offset += size) out.push(raw.subarray(offset, offset + size));
  return out;
}

function blackShare(frame) {
  let black = 0;
  for (let i = 0; i < frame.length; i += 3) {
    if (frame[i] < 10 && frame[i + 1] < 10 && frame[i + 2] < 10) black++;
  }
  return black / (frame.length / 3);
}

function step(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) sum += Math.abs(a[i] - b[i]);
  return sum / a.length / 255;
}

const round = (x) => Math.round(x * 1000) / 1000;
const result = {};
for (const { kind, seconds } of placed) {
  // Across the cut, the default alignment: half before, half after.
  const from = seconds - length / 2, to = seconds + length / 2;
  const shots = frames(from - 1 / 30, to);
  const move = shots.slice(1);
  const blacks = move.map(blackShare);
  const steps = move.map((frame, i) => step(shots[i], frame));
  let hitches = 0;
  for (let i = 1; i + 1 < steps.length; i++) {
    const beside = (steps[i - 1] + steps[i + 1]) / 2;
    if (steps[i] > 0.03 && steps[i] > 2 * beside) hitches++;
    const either = Math.min(steps[i - 1], steps[i + 1]);
    if (either > 0.03 && steps[i] < either / 4) hitches++;
  }
  const middle = blacks.slice(Math.floor(blacks.length / 4), Math.ceil(blacks.length * 3 / 4));
  result[kind] = {
    frames: move.length,
    worstBlackInMiddleHalf: round(Math.max(...middle)),
    blackPerFrame: blacks.map(round),
    biggestStep: round(Math.max(...steps)),
    steps: steps.map(round),
    hitches,
  };
}
console.log(JSON.stringify(result, null, 1));
