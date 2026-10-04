#!/usr/bin/env node
// Every target in Package.swift must list, as a dependency of its own, every
// module of ours it imports.
//
// The build decides whether a target is up to date by looking only at the
// modules it lists. A test target that reached PhotonzCore through
// PhotonzRender alone was therefore never recompiled when a core type changed
// shape: PhotonzRender's module came out byte for byte the same, so nothing the
// tests listed had changed, and they kept writing a field at its old offset.
// The suite then failed on correct code until a test file was touched
// (2026-09-25, 2026-10-02). `Scripts/stale-build-drill.sh` shows it happening.
//
//     node Scripts/check-direct-imports.mjs     # exit 1, naming each gap
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const pkg = JSON.parse(execFileSync("swift", ["package", "dump-package"], {
  cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "inherit"],
}));

const ours = new Set(pkg.targets.map((t) => t.name));

function swiftFiles(dir) {
  let out = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) out = out.concat(swiftFiles(path));
    else if (name.endsWith(".swift")) out.push(path);
  }
  return out;
}

function listed(target) {
  return new Set(target.dependencies.flatMap((d) =>
    (d.byName ?? d.target ?? d.product ?? []).filter((x) => typeof x === "string").slice(0, 1)));
}

const importLine = /^\s*(?:@testable\s+|@_implementationOnly\s+|(?:public|internal|package)\s+)?import\s+(\w+)/gm;
const gaps = [];
for (const target of pkg.targets) {
  const dir = join(root, target.path ?? (target.type === "test" ? "Tests" : "Sources"),
    target.path ? "" : target.name);
  const deps = listed(target);
  const missing = new Map();
  for (const file of swiftFiles(dir)) {
    for (const [, module] of readFileSync(file, "utf8").matchAll(importLine)) {
      if (module !== target.name && ours.has(module) && !deps.has(module) && !missing.has(module)) {
        missing.set(module, file.slice(root.length + 1));
      }
    }
  }
  for (const [module, file] of missing) gaps.push({ target: target.name, module, file });
}

if (gaps.length) {
  for (const g of gaps) {
    console.log(`==> ${g.target} imports ${g.module} (${g.file}) without listing it in Package.swift, ` +
      `so a change to ${g.module} can leave ${g.target} running old compiled code.`);
  }
  process.exit(1);
}
console.log(`Every target lists every module of ours it imports (${pkg.targets.length} targets).`);
