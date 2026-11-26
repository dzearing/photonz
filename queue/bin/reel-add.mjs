#!/usr/bin/env node
// Put a reel where the user can watch it: queue/reels/, listed in reels.json,
// shown on the dashboard's Reels page and in ~/Movies/Photonz Reels.
//
//   node queue/bin/reel-add.mjs <video.mp4> --title "..." [--task <id>]
//        [--made-on "0.25.0 Dev"] [--kind sample|before|after|reference] [--notes "..."]
//
// Every sizzle reel, transition reel, title reel or before/after an agent makes
// for the user goes through here (asked for on 2026-11-26: "i would love for
// the sizzle reels to be saved somewhere so i can see samples"). A copy over
// 1080p or 25 MB is re-encoded to 1080p H.264 so the folder stays watchable and
// small enough to commit; the original is left where it was.
import { copyFileSync, existsSync, readFileSync, statSync, writeFileSync, mkdirSync, symlinkSync, lstatSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import os from 'node:os';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DIR = join(process.env.PHOTONZ_QUEUE_DIR || join(REPO, 'queue'), 'reels');
const LIST = join(DIR, 'reels.json');

const args = process.argv.slice(2);
const src = args.find((a, i) => !a.startsWith('--') && !(args[i - 1] || '').startsWith('--'));
const opt = (k) => { const i = args.indexOf('--' + k); return i > -1 ? args[i + 1] : undefined; };
if (!src || !existsSync(src) || !opt('title')) {
  console.error('usage: reel-add.mjs <video.mp4> --title "..." [--task id] [--made-on ver] [--kind sample] [--notes ...]');
  process.exit(2);
}
mkdirSync(DIR, { recursive: true });
const day = new Date().toISOString().slice(0, 10);
const slug = opt('title').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60);
let name = `${day}-${slug}.mp4`;
for (let n = 2; existsSync(join(DIR, name)); n++) name = `${day}-${slug}-${n}.mp4`;
const out = join(DIR, name);

let height = 0;
try {
  height = Number(execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=height',
    '-of', 'csv=p=0', src]).toString().trim()) || 0;
} catch {}
const big = statSync(src).size > 25 * 1024 * 1024 || height > 1080;
if (big) {
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', src, '-vf', 'scale=-2:min(ih\\,1080)', '-c:v', 'libx264',
    '-crf', '22', '-preset', 'medium', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', out]);
} else {
  copyFileSync(src, out);
}

let list = [];
try { list = JSON.parse(readFileSync(LIST, 'utf8')); } catch {}
const entry = {
  file: name, title: opt('title'), added: new Date().toISOString(),
  ...(opt('task') ? { task: opt('task') } : {}),
  ...(opt('made-on') ? { madeOn: opt('made-on') } : {}),
  kind: opt('kind') || 'sample',
  ...(opt('notes') ? { notes: opt('notes') } : {}),
};
list.unshift(entry);
writeFileSync(LIST, JSON.stringify(list, null, 2) + '\n');

// The Finder way in: ~/Movies/Photonz Reels points at this folder.
if (!process.env.PHOTONZ_QUEUE_DIR) {
  const link = join(os.homedir(), 'Movies', 'Photonz Reels');
  try { lstatSync(link); } catch { try { symlinkSync(DIR, link); } catch {} }
}
console.log(`queue/reels/${name}${big ? ' (re-encoded to 1080p)' : ''}`);
