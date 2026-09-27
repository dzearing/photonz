#!/usr/bin/env node
// Which switches a person gets without touching anything, read out of the
// app's own list of them (Sources/PhotonzCore/FeatureCatalog.swift).
//
// The queue needs this to refuse `done` on a task whose feature only a walk
// that forces a switch on can reach: for five days in September 2026 about
// twenty video features were audited as ready to try while every one sat
// behind a switch that was off at Next defaults. The answer has to come from
// the app, not from what a runner or an audit says, and the queue is node, so
// the catalog's source is read here. It is regular by construction (one
// `Definition(` per switch, `releases:` and `enabledByDefaultIn:` after the
// flag), and FlagDefaultsReaderTests runs this file and compares what it says
// with the catalog itself, so a shape this cannot read fails the test suite
// rather than quietly reading every switch as off.
//
//   node queue/bin/flag-defaults.mjs [next|current]   one line per switch: on/off, name
//   node queue/bin/flag-defaults.mjs --json            { release: { name: true|false } }
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
export const CATALOG = join(HERE, '..', '..', 'Sources', 'PhotonzCore', 'FeatureCatalog.swift');
export const RELEASES = ['current', 'next'];

// Each switch the catalog defines: { name, releases, onIn, needs }.
export function parseCatalog(source) {
  const names = new Map();
  for (const m of source.matchAll(/static let (\w+)\s*=\s*"([^"]*)"/g)) names.set(m[1], m[2]);
  const nameOf = (token) => {
    const t = token.trim();
    if (t.startsWith('"')) return t.slice(1, -1);
    if (!names.has(t)) throw new Error(`the switch list names ${t}, which is not a constant it declares`);
    return names.get(t);
  };
  const list = (text) => text.split(',').map((s) => s.trim()).filter(Boolean);
  const start = source.indexOf('func definitions(for release');
  if (start < 0) throw new Error('no definitions(for:) in the switch list');
  const chunks = source.slice(start).split(/\bDefinition\(/).slice(1);
  return chunks.map((chunk) => {
    const flag = chunk.match(/FeatureFlag\(\s*name:\s*(\w+|"[^"]*")/);
    if (!flag) throw new Error('a switch in the list has no name this reader can find');
    const name = nameOf(flag[1]);
    // The last match, because a description is free text and comes first.
    const last = (key) => {
      const all = [...chunk.matchAll(new RegExp(`\\b${key}:\\s*\\[([^\\]]*)\\]`, 'g'))];
      return all.length ? all[all.length - 1][1] : null;
    };
    const releases = last('releases');
    const onIn = last('enabledByDefaultIn');
    if (releases === null || onIn === null) throw new Error(`${name}: no releases or enabledByDefaultIn this reader can find`);
    const needs = last('needs');
    return {
      name,
      releases: list(releases).map((r) => r.replace(/^\./, '')),
      onIn: list(onIn).map((r) => r.replace(/^\./, '')),
      needs: needs === null ? [] : list(needs).map(nameOf),
    };
  });
}

let cache = null; // { source, defs }
export function readCatalog(file = CATALOG) {
  const source = readFileSync(file, 'utf8');
  if (!cache || cache.source !== source) cache = { source, defs: parseCatalog(source) };
  return cache.defs;
}

// name -> whether it starts on, for the switches `release` offers.
export function flagDefaults(release = 'next', defs = readCatalog()) {
  const out = {};
  for (const d of defs) if (d.releases.includes(release)) out[d.name] = d.onIn.includes(release);
  return out;
}

// What a walk switches ON that `release` has off, given its setup's flags.
// Switching a feature off, or on when it already is, forces nothing a person
// would not see; so does naming a switch this release does not offer, since
// the harness leaves it alone there.
export function forcedOn(walkFlags = {}, defaults = flagDefaults()) {
  return Object.entries(walkFlags || {})
    .filter(([name, on]) => on === true && defaults[name] === false)
    .map(([name]) => name)
    .sort();
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const args = process.argv.slice(2);
  if (args[0] === '--json') {
    const out = {};
    for (const r of RELEASES) out[r] = flagDefaults(r);
    process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  } else {
    const defaults = flagDefaults(args[0] || 'next');
    for (const [name, on] of Object.entries(defaults)) process.stdout.write(`${on ? 'on ' : 'off'}\t${name}\n`);
  }
}
