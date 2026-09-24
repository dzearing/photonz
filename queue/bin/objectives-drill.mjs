#!/usr/bin/env node
// Drill for what the objectives say done looks like (queue-lib writeObjectives,
// objectivesGaps, focusBrief).
//
// The video epic and all five of its children went five days with no success
// criteria while the loop built against them, and a save from the dashboard's
// Objectives tab erased every success list there was, because writeObjectives
// rebuilt each epic from a list of fields that did not include one. This proves
// four things: a save keeps success lists and specs, the check names every now
// epic with no definition of done, the manager's focus section follows the
// focus when it moves, and the real objectives.json has no gaps today. Run it
// after touching objectives in queue-lib.mjs, the manager prompt, or the
// objectives themselves.
//
//   node queue/bin/objectives-drill.mjs
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const BIN = dirname(fileURLToPath(import.meta.url));
const REAL = JSON.parse(readFileSync(join(BIN, '..', 'objectives.json'), 'utf8'));

const dir = mkdtempSync(join(tmpdir(), 'photonz-objectives-'));
process.env.PHOTONZ_QUEUE_DIR = dir;
const lib = await import('./queue-lib.mjs');

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

const spec = (name) => ({ mocks: [`${name}.html`], competitors: [`${name} rival`], workflow: `walk ${name}` });
const tree = () => ([
  { id: 'video', title: 'Video', stage: 'now', success: ['cuts a recording'], spec: spec('video'),
    children: [
      { id: 'cutting', title: 'Cutting', stage: 'now', success: ['blade on B'] },
      { id: 'audio', title: 'Audio', stage: 'now', children: [] },          // now, nothing written
      { id: 'share', title: 'Share', stage: 'later' },                      // later: nothing owed
    ] },
  { id: 'icons', title: 'Icons', stage: 'now', success: ['draws on a grid'], spec: spec('icons'), children: [] },
  { id: 'someday', title: 'Someday', stage: 'later', children: [] },
]);
writeFileSync(join(dir, 'objectives.json'), JSON.stringify({ focus: 'video', principles: ['p'], epics: tree() }));

console.log('a save keeps what done looks like');
lib.writeObjectives(lib.readObjectives().epics);
let doc = lib.readObjectives();
check('the epic keeps its success list', JSON.stringify(doc.epics[0].success) === '["cuts a recording"]', doc.epics[0].success);
check('a sub-epic keeps its success list', JSON.stringify(doc.epics[0].children[0].success) === '["blade on B"]', doc.epics[0].children[0]);
check('the epic keeps its spec', doc.epics[0].spec?.mocks?.[0] === 'video.html' && doc.epics[0].spec.workflow === 'walk video', doc.epics[0].spec);
check('an epic with nothing written gains no empty list', !('success' in doc.epics[0].children[1]) && !('spec' in doc.epics[0].children[1]), doc.epics[0].children[1]);
check('focus and principles survive', doc.focus === 'video' && doc.principles[0] === 'p', doc);
const hist = readFileSync(join(dir, 'history.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
check('the save is recorded as objectives_updated', hist.at(-1)?.ev === 'objectives_updated', hist.at(-1));
lib.writeObjectives(doc.epics, { by: 'drill', change: 'said why' });
const last = readFileSync(join(dir, 'history.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l)).at(-1);
check('a save that says why records who and why', last.by === 'drill' && last.change === 'said why', last);

console.log('the check names every gap');
let gaps = lib.objectivesGaps();
check('a now sub-epic with no success list is named', gaps.some((g) => g.startsWith('audio ')), gaps);
check('a later sub-epic is not', !gaps.some((g) => g.startsWith('share ')), gaps);
check('a later epic is not', !gaps.some((g) => g.startsWith('someday ')), gaps);
check('that is the only gap', gaps.length === 1, gaps);
doc.epics[0].children[1].success = ['a waveform under the picture'];
lib.writeObjectives(doc.epics);
check('writing it clears the check', lib.objectivesGaps().length === 0, lib.objectivesGaps());

console.log('the manager brief follows the focus');
let brief = lib.focusBrief();
check('the brief names the focus mocks', brief.includes('video.html'), brief);
check('the brief carries the focus success list', brief.includes('cuts a recording'), brief);
check('the brief carries its now sub-epics', brief.includes('blade on B') && brief.includes('a waveform under the picture'), brief);
check('the brief names the competitors and the workflow', brief.includes('video rival') && brief.includes('walk video'), brief);
check('the brief says nothing of another epic', !brief.includes('icons.html'), brief);
lib.writeObjectives(lib.readObjectives().epics, { focus: 'icons' });
brief = lib.focusBrief();
check('moving the focus moves the brief with it', brief.includes('icons.html') && brief.includes('icons rival') && !brief.includes('video.html'), brief);

console.log('a focus with nothing to measure against is a gap');
doc = lib.readObjectives();
delete doc.epics[1].spec;
lib.writeObjectives(doc.epics);
gaps = lib.objectivesGaps();
check('missing mocks, competitors and workflow are each named', ['spec.mocks', 'spec.competitors', 'spec.workflow'].every((k) => gaps.some((g) => g.includes(k))), gaps);
brief = lib.focusBrief();
check('and the brief puts them first, as the pass\'s first job', brief.indexOf('have gaps') > -1 && brief.indexOf('have gaps') < brief.indexOf('**Focus:'), brief);
lib.writeObjectives(doc.epics, { focus: 'someday' });
check('a focus staged later is a gap', lib.objectivesGaps().some((g) => g.includes('staged later')), lib.objectivesGaps());
lib.writeObjectives(doc.epics, { focus: 'gone' });
check('a focus that is not in the tree is a gap', lib.objectivesGaps().some((g) => g.includes('not an epic')), lib.objectivesGaps());

console.log('the real objectives and the manager prompt');
const real = lib.objectivesGaps(REAL);
check('queue/objectives.json has no gaps today', real.length === 0, real);
const prompt = readFileSync(join(BIN, 'manager-prompt.md'), 'utf8');
const handWritten = ['video*.html', 'comp-video.html', 'next-measure.md', 'CleanShot', 'Screen Studio'].filter((s) => prompt.includes(s));
check('the manager prompt writes no focus\'s mocks or competitors by hand', handWritten.length === 0, handWritten);
check('the manager prompt tells the pass to run the check', prompt.includes('objectives-check'));
const loop = readFileSync(join(BIN, 'go-loop.sh'), 'utf8');
check('the go loop hands the manager the generated brief', /run_runner "\$\(cat queue\/bin\/manager-prompt\.md;[^"]*Q focus-brief/.test(loop));

rmSync(dir, { recursive: true, force: true });
console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
