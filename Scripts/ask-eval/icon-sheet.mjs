// The sheet an icon case is judged on (README, "Icon cases"): icon-sheet.swift
// draws it, this fetches the Lucide and Material Symbols reference files it
// shows. They sit under .ask-eval/references, outside the repo's history, are
// only ever read by that script for the judge, and Ask never sees them.
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { repo } from "./engines.mjs";
import { run } from "./judge.mjs";

const here = path.join(repo, "Scripts/ask-eval");
const folder = path.join(repo, ".ask-eval/references");
const SETS = {
  lucide: { label: "Lucide", url: (name) => `https://cdn.jsdelivr.net/npm/lucide-static@latest/icons/${name}.svg` },
  material: { label: "Material Symbols", url: (name) => `https://cdn.jsdelivr.net/npm/@material-symbols/svg-400@latest/outlined/${name}.svg` },
};

/// A reference file on disk, fetched once. A reference that cannot be fetched
/// is left off the sheet: the case is still judged against the rest.
async function reference(set, name) {
  const file = path.join(folder, set, `${name}.svg`);
  if (existsSync(file)) return file;
  try {
    const answer = await fetch(SETS[set].url(name), { signal: AbortSignal.timeout(10_000) });
    if (!answer.ok) return null;
    mkdirSync(path.dirname(file), { recursive: true });
    // Lucide draws in the page's colour, which a file on its own does not have.
    writeFileSync(file, (await answer.text()).replaceAll("currentColor", "#000000"));
    return file;
  } catch { return null; }
}

/// Draws `dir`/icon-sheet.png for this case and answers its path, or the plain
/// picture when the sheet could not be drawn.
export async function iconSheet(testCase, dir, picture) {
  const out = path.join(dir, "icon-sheet.png");
  const said = testCase.reference ?? {};
  const alone = path.join(dir, "icon.png");
  const args = [path.join(here, "icon-sheet.swift"), out, existsSync(alone) ? alone : picture, said.sf ?? "-"];
  for (const set of Object.keys(SETS)) {
    const file = said[set] ? await reference(set, said[set]) : null;
    if (file) args.push(file, SETS[set].label);
  }
  const made = await run("swift", args, { cwd: repo, timeoutMS: 120_000 });
  if (made.code !== 0) { console.error(`!! icon sheet: ${made.stderr.trim().split("\n").pop()}`); return picture; }
  return out;
}
