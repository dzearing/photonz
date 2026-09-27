#!/usr/bin/env node
// Reach drill: prove an app task cannot be marked done while the only walks it
// names switch on a feature a person running Next does not have on.
//
//   node queue/bin/reach-drill.mjs
//
// From 2026-09-18 to 09-23 about twenty video features were audited as ready
// to try while a switch that was off by default hid every one; each walk
// turned it on in its setup and passed. The guards below have to hold:
//
//   1. `queue.mjs status <id> done` is refused, naming the walk and the switch,
//      when every walk the task names turns on a switch that is off in Next
//   2. the refusal leaves the task in progress and says why in its history
//   3. one walk that reaches the feature without switching anything on is enough
//   4. switching a feature on that is already on, or switching one off, forces nothing
//   5. saying the feature is deliberately off by default lets it through
//   6. a task that is not app work, or names no walks, is not judged
//   7. the defaults come from the app's list of switches: flip the switch on
//      there and the same task is let through, whatever the walk says
//   8. the dashboard's own status path is not gated
//   9. an audit lists the switches its setup changed from the defaults, as read
//      from the app's list, so the dashboard can show it as not reachable yet
//
// Runs against a throwaway queue and a throwaway switch list; FlagDefaultsReaderTests
// runs it as part of Scripts/test.sh.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const sandbox = mkdtempSync(join(tmpdir(), 'photonz-reach-'));
process.env.PHOTONZ_QUEUE_DIR = join(sandbox, 'queue');
const q = await import('./queue-lib.mjs');

const catalogFile = join(sandbox, 'Sources', 'PhotonzCore', 'FeatureCatalog.swift');
mkdirSync(dirname(catalogFile), { recursive: true });
const catalog = (hiddenOn) => `public enum FeatureCatalog {
    public static let shownFlag = "next-shown"
    public static let hiddenFlag = "next-hidden"
    private static func definitions(for release: Release) -> [Definition] {
        [
            Definition(
                flag: FeatureFlag(name: shownFlag, title: "Shown", description: "On for everyone in Next. releases: [.current]", area: .app, isEnabled: false, parameters: []),
                releases: [.next],
                enabledByDefaultIn: [.next]),
            Definition(
                flag: FeatureFlag(name: hiddenFlag, title: "Hidden", description: "Off until switched on.", area: .app, isEnabled: false, parameters: []),
                releases: [.next],
                enabledByDefaultIn: [${hiddenOn ? '.next' : ''}]),
        ]
    }
}
`;
writeFileSync(catalogFile, catalog(false));

const walks = join(sandbox, 'Scripts', 'playtest');
mkdirSync(walks, { recursive: true });
const walk = (name, flags) => writeFileSync(join(walks, `${name}.json`),
  JSON.stringify({ setup: flags ? { flags } : {}, steps: [] }));
walk('forces-hidden-walk', { 'next-hidden': true });
walk('forces-hidden-too-walk', { 'next-hidden': true, 'next-shown': true });
walk('plain-walk', null);
walk('already-on-walk', { 'next-shown': true, 'next-hidden': false });

let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? '  PASS  ' : '  FAIL  ') + name + (!ok && detail ? '\n          ' + detail : ''));
  if (!ok) failed++;
};
const cli = (...args) => {
  try {
    return { ok: true, out: execFileSync('node', [join(HERE, 'queue.mjs'), ...args], { env: process.env, encoding: 'utf8', stdio: 'pipe' }) };
  } catch (e) {
    return { ok: false, out: String(e.stderr || '') + String(e.stdout || '') };
  }
};
const task = (title, extra = {}) => {
  const t = q.addTask({ title, notes: 'drill', ...extra });
  q.setStatus(t.id, 'in_progress', 'claimed by drill');
  return t.id;
};

try {
  // --- 1 + 2: every walk forces a switch that is off ---------------------
  const hidden = task('A feature behind a switch', { walks: ['forces-hidden-walk', 'forces-hidden-too-walk'] });
  const refused = cli('status', hidden, 'done', 'shipped');
  check('done is refused when every walk turns on a switch that is off in Next', !refused.ok, refused.out.trim());
  check('the refusal names the walk and the switch', /forces-hidden-walk turns on next-hidden/.test(refused.out), refused.out.trim());
  check('the task stays in progress', q.findTask(hidden).status === 'in_progress', q.findTask(hidden).status);
  check('its history says why', q.findTask(hidden).log.some((e) => /^not done yet: .*next-hidden/.test(e.note)));

  // --- 3: one walk that reaches it at defaults ---------------------------
  const reached = task('A feature with a plain walk', { walks: ['forces-hidden-walk', 'plain-walk'] });
  check('one walk that switches nothing on is enough', cli('status', reached, 'done', 'shipped').ok);
  check('...and the task is done', q.findTask(reached).status === 'done');

  // --- 4: forcing what is already on, or switching off, forces nothing ---
  const already = task('A feature already on', { walks: ['already-on-walk'] });
  check('switching on what is on and off what is off is not forcing', cli('status', already, 'done', 'shipped').ok);

  // --- 5: said to be off by default -------------------------------------
  const meant = task('A feature meant to stay off', { walks: ['forces-hidden-walk'] });
  check('off-by-default needs a reason in words', !cli('off-by-default', meant, '  ').ok);
  check('off-by-default records the reason', cli('off-by-default', meant, 'a debug view, not for people').ok
    && q.findTask(meant).offByDefault === 'a debug view, not for people');
  check('a task that says it is deliberately off is let through', cli('status', meant, 'done', 'shipped').ok);

  // --- 6: not app work, or no walks --------------------------------------
  const infra = task('A loop change', { walks: ['forces-hidden-walk'] });
  const it = q.findTask(infra); it.area = 'queue'; q.saveTask(it);
  check('a task that is not app work is not judged', cli('status', infra, 'done', 'shipped').ok);
  const none = task('A task with no walks');
  check('a task that names no walks is not judged', cli('status', none, 'done', 'shipped').ok);
  const ghost = task('A task naming a walk that does not exist', { walks: ['no-such-walk'] });
  check('a walk that does not exist counts neither way', cli('status', ghost, 'done', 'shipped').ok);

  // --- 7: the app's own list decides -------------------------------------
  const flipped = task('A feature whose switch is turned on by default', { walks: ['forces-hidden-walk'] });
  check('refused while the list has it off', !cli('status', flipped, 'done', 'shipped').ok);
  writeFileSync(catalogFile, catalog(true));
  check('let through once the list has it on, with the walk unchanged', cli('status', flipped, 'done', 'shipped').ok);
  writeFileSync(catalogFile, catalog(false));

  // --- 8: the dashboard's path ------------------------------------------
  const byHand = task('Marked done by the user', { walks: ['forces-hidden-walk'] });
  q.setStatus(byHand, 'done', 'set from dashboard');
  check('the dashboard can still mark it done', q.findTask(byHand).status === 'done');

  // --- 9: an audit that changed a switch shows as not reachable yet ------
  const audits = join(sandbox, 'queue', 'audits');
  mkdirSync(audits, { recursive: true });
  const audit = (name, extra) => writeFileSync(join(audits, name), JSON.stringify({ feature: name, try: [{ do: 'a' }], ...extra }));
  audit('2026-09-27-forced.json', { switched: { 'next-hidden': true } });
  audit('2026-09-27-at-defaults.json', { switched: { 'next-shown': true, 'next-hidden': false } });
  audit('2026-09-27-turned-off.json', { switched: { 'next-shown': false } });
  audit('2026-09-27-silent.json', {});
  audit('2026-09-27-listed.json', { switched: ['next-hidden'] });
  const rows = Object.fromEntries(q.auditIndex().map((r) => [r.name, r.switched]));
  check('an audit that switched on what is off lists it', JSON.stringify(rows['2026-09-27-forced.json']) === '["next-hidden"]', JSON.stringify(rows));
  check('naming switches at their defaults changes nothing', rows['2026-09-27-at-defaults.json'].length === 0, JSON.stringify(rows));
  check('switching one off is a change too', JSON.stringify(rows['2026-09-27-turned-off.json']) === '["next-shown"]', JSON.stringify(rows));
  check('an audit that says nothing lists nothing', rows['2026-09-27-silent.json'].length === 0);
  check('a bare list of names means each was switched on', JSON.stringify(rows['2026-09-27-listed.json']) === '["next-hidden"]', JSON.stringify(rows));
  writeFileSync(catalogFile, catalog(true));
  const later = Object.fromEntries(q.auditIndex().map((r) => [r.name, r.switched]));
  check('turning the switch on by default in the app clears it, from the app\'s list not the audit', later['2026-09-27-forced.json'].length === 0, JSON.stringify(later));
  writeFileSync(catalogFile, catalog(false));
} finally {
  rmSync(sandbox, { recursive: true, force: true });
}

console.log(failed ? `\n${failed} check(s) FAILED` : '\nall checks passed');
process.exit(failed ? 1 : 0);
