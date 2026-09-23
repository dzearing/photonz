#!/usr/bin/env node
// Drill for "how far behind is the dev app" (queue-lib devAppState/devAppSentence).
//
// The user opens "dist/Photonz Dev.app" to look at what the loop built. When
// queue/playtest.lock is held the loop correctly refuses to rebuild it, and
// until 2026-09-20 nothing said so anywhere a person looks: the app on disk was
// two days and twelve commits old, the Save fix they had reported was missing
// from it, and the app read as broken when it was only old. This is the code
// that says it out loud, so it has to be right about five things:
//
//   a build newer than every commit is NOT behind and must stay silent;
//   a held lock is named as the reason, with the time it was taken;
//   a lock older than a day is called out as probably forgotten;
//   a commit that landed a moment ago is quiet, because the refresh is still
//     compiling and an alarm that fires on every build is one nobody reads;
//   nothing here ever clears the lock or touches the app.
//
// And it has to say the same thing tomorrow as it says today. Every time in
// here is measured from the drill's own fixed clock, never the machine's: a
// state and the sentence written from it share one clock, so the drill cannot
// go red just because a day passed. It did, once, and a runner lost a morning
// to a failure that was only the calendar moving.
//
//   node queue/bin/dev-app-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, utimesSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dir = mkdtempSync(join(tmpdir(), 'photonz-dev-app-'));
process.env.PHOTONZ_QUEUE_DIR = dir;
mkdirSync(dir, { recursive: true });
const lib = await import('../bin/queue-lib.mjs');

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

const HOUR = 3600 * 1000;
const NOW = Date.parse('2026-09-20T09:00:00Z');
const ago = (h) => new Date(NOW - h * HOUR).toISOString();

// The lock is a real file, because its age comes from its mtime.
const LOCK = join(dir, 'playtest.lock');
const holdLock = (hoursAgo, text = 'Someone is working in the dev app. Created 2026-09-18 08:09 by testing.sh.') => {
  writeFileSync(LOCK, text + '\n');
  const t = (NOW - hoursAgo * HOUR) / 1000;
  utimesSync(LOCK, t, t);
};
const releaseLock = () => rmSync(LOCK, { force: true });

// Everything else is injected, so the drill never needs a build or a git repo.
const state = (o = {}) => lib.devAppState({
  at: NOW,
  builtAt: o.builtAt === undefined ? ago(49) : o.builtAt,          // built 2 days ago
  commits: o.commits === undefined ? [] : o.commits,
});
const twelve = () => Array.from({ length: 12 }, (_, i) => ({ sha: 'abc' + i, at: ago(47 - i * 3), subject: 'commit ' + i }));

console.log('a dev app that is up to date');
releaseLock();
let s = state({ commits: [] });
check('no commits since the build means not behind', s.behind === 0 && s.stale === false, s);
check('it still says when the app was built', s.builtAt === ago(49), s.builtAt);
check('no lock means no lock', s.lock.held === false, s.lock);
check('the state carries the clock it was read at', s.at === NOW, s.at);
check('nothing to say, so the sentence is empty', lib.devAppSentence(s) === '', lib.devAppSentence(s));

console.log('a build newer than the newest commit');
s = state({ builtAt: ago(1), commits: twelve() });
check('commits older than the build do not count', s.behind === 0 && s.stale === false, { behind: s.behind });

console.log('a dev app left behind, with nobody holding the lock');
s = state({ commits: twelve() });
check('every commit after the build counts', s.behind === 12, s.behind);
check('the newest commit is carried, so the page can say how long', s.newest.at === ago(14), s.newest);
check('so is the oldest, which is how long the gap has been open', s.oldest.at === ago(47), s.oldest);
check('behind is stale', s.stale === true, s.stale);
check('with no lock held, the reason is a refresh that never closed the gap', s.reason === 'not-refreshed', s.reason);
let free = lib.devAppSentence(s);
check('the sentence says the count and does not blame a lock', /12 commits behind/.test(free) && !/playtest[.]lock/.test(free), free);
check('it points at the refresh, which is the thing to look at', /refresh-dev-app[.]sh/.test(free), free);

console.log('a commit that landed a moment ago, with the refresh still compiling');
s = state({ commits: [{ sha: 'a', at: ago(0.1), subject: 'just landed' }] });
check('it is behind as a fact', s.behind === 1, s.behind);
check('but not yet worth saying: the refresh is mid-build', s.stale === false && s.reason === 'refresh-pending', s);
check('so nothing is said', lib.devAppSentence(s) === '', lib.devAppSentence(s));

console.log('the same fresh commit with the lock held');
holdLock(2);
s = state({ commits: [{ sha: 'a', at: ago(0.1), subject: 'just landed' }] });
check('a held lock says it at once, because the gap is not closing at all', s.stale === true && s.reason === 'locked', s);
releaseLock();

console.log('a dev app left behind because the lock is held');
holdLock(48.5);
s = state({ commits: twelve() });
check('the lock is seen and dated', s.lock.held === true && s.lock.since === new Date(NOW - 48.5 * HOUR).toISOString(), s.lock);
check('the lock is named as the reason', s.reason === 'locked', s.reason);
check('a lock held over a day is called probably forgotten', s.lock.forgotten === true, s.lock);
check('the one command that clears it is carried, and it is the only one', s.lock.release === 'queue/bin/testing.sh off', s.lock.release);
check('whoever took it is carried from the lock file', /testing\.sh/.test(s.lock.who), s.lock.who);
let line = lib.devAppSentence(s);
check('the sentence says how far behind', /12 commits behind/.test(line), line);
check('the sentence says the lock is the reason and how long it has been held', /playtest\.lock/.test(line) && /2 days/.test(line), line);
check('the sentence says the lock looks forgotten', /forgotten/.test(line), line);
check('the sentence hands over the release command', /queue\/bin\/testing\.sh off/.test(line), line);

console.log('a lock taken minutes ago is somebody working, not a leftover');
holdLock(0.5);
s = state({ commits: twelve() });
check('a fresh lock is not called forgotten', s.lock.held === true && s.lock.forgotten === false, s.lock);
line = lib.devAppSentence(s);
check('and the sentence does not say forgotten', !/forgotten/.test(line), line);
check('but it still says the app is behind', /12 commits behind/.test(line), line);

console.log('a lock held with the app already current');
s = state({ commits: [] });
check('a held lock alone is not a warning', s.stale === false, s);
check('and says nothing, because nothing is being missed', lib.devAppSentence(s) === '', lib.devAppSentence(s));

console.log('no dev app on disk at all');
releaseLock();
s = state({ builtAt: null, commits: twelve() });
check('an app that was never built is absent, not behind', s.present === false && s.stale === false && s.behind === 0, s);
check('and says nothing: a fresh clone has no dev app and that is fine', lib.devAppSentence(s) === '', lib.devAppSentence(s));

console.log('nothing here touches the app or the lock');
holdLock(48.5);
lib.devAppState({ at: NOW, builtAt: ago(49), commits: twelve() });
lib.devAppSentence(state({ commits: twelve() }));
check('the lock file is still there after reading the state', lib.devAppState({ at: NOW, builtAt: ago(49), commits: [] }).lock.held === true);

// The words are about the state, so they are measured from the clock that
// state was read at. Otherwise a fixture written today is described by the
// machine's clock tomorrow, and the age in the sentence grows by a day a day.
console.log('the same state says the same thing however long ago it was read');
holdLock(48.5);
s = state({ commits: twelve() });
const written = lib.devAppSentence(s);
check('a state read at a fixed clock is described at that clock', / 2 days/.test(written), written);
const realNow = Date.now;
Date.now = () => realNow() + 30 * 24 * HOUR;   // the machine's clock, a month on
try {
  check('a month of machine clock does not change a word of it', lib.devAppSentence(s) === written, lib.devAppSentence(s));
  check('and a state read with no clock given still uses the machine\'s', Math.abs(lib.devAppState({ builtAt: ago(49), commits: [] }).at - Date.now()) < 5000);
} finally { Date.now = realNow; }

// The dashboard polls aggregateState every four seconds forever, and the git
// log inside it is the only expensive part of this whole feature.
console.log('the git log behind it is not re-run on every poll');
lib.forgetDevAppCommits();
const repo = join(process.cwd());
const first = lib.devAppCommitsSince('2026-01-01T00:00:00.000Z', repo);
check('a second call in the same breath returns the same rows object',
  lib.devAppCommitsSince('2026-01-01T00:00:00.000Z', repo) === first);
check('a different build date is a different question and is asked again',
  lib.devAppCommitsSince('2026-01-02T00:00:00.000Z', repo) !== first);
lib.forgetDevAppCommits();
check('and the cache can be dropped', lib.devAppCommitsSince('2026-01-02T00:00:00.000Z', repo) !== first);

console.log('the dashboard poll carries it');
const poll = lib.aggregateState({ tasks: false });
check('aggregateState has a devApp section', poll.devApp && typeof poll.devApp.behind === 'number', poll.devApp);
check('and it reads the real lock', poll.devApp.lock.held === true, poll.devApp.lock);

rmSync(dir, { recursive: true, force: true });
console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
