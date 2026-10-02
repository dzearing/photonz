#!/usr/bin/env node
// Photonz task queue CLI. Thin wrapper over queue-lib.mjs so the go loop,
// task runners, and humans all mutate the queue the same way.
//
//   node queue/bin/queue.mjs next            claim highest-priority ready task; prints its file path, or "none"
//   node queue/bin/queue.mjs ready           print how many tasks are ready to claim (pending, deps done)
//   node queue/bin/queue.mjs idle            mark the loop idle (heartbeat)
//   node queue/bin/queue.mjs stopped         mark the loop stopped
//   node queue/bin/queue.mjs note <msg>      update the live status note (shown on the dashboard)
//   node queue/bin/queue.mjs status <id> <pending|in_progress|blocked|done|dropped> [note]
//                                            with only an id it prints the task and changes nothing
//   node queue/bin/queue.mjs add <title> [priority] [notes] [--dry-run]
//   node queue/bin/queue.mjs addjson '<json>' [--dry-run]
//                                            preferred: carries goal + acceptance checklist.
//                                            --dry-run prints what would be filed and files nothing.
//                                            A title needs at least three words
//   node queue/bin/queue.mjs search [--all] <words>
//                                            open tasks whose title, goal, checklist, working detail
//                                            or log mention those words. Search BEFORE filing a
//                                            follow-up; --all reads done and dropped ones too
//   node queue/bin/queue.mjs log <id> <note>    append one line to a task's log without changing its
//                                            status: how a finding folds into a task that already
//                                            covers it, and where a rough edge goes when it does not
//                                            earn its own task (queue/bin/follow-up-bar.md)
//   node queue/bin/queue.mjs walks <id> [<walk> ... | --none]
//                                            the scripted walks this task owns, so the sweep's
//                                            failing list says so instead of guessing it from the
//                                            task's wording. --none says the walks it names are only
//                                            examples. With no arguments it prints what the task says
//   node queue/bin/queue.mjs off-by-default <id> ["why" | --clear]
//                                            this task's feature is meant to stay behind a switch
//                                            that is off by default. Without it, `status <id> done`
//                                            on an app task is refused when every walk it names
//                                            turns on a switch that is off at the release's defaults
//   node queue/bin/queue.mjs needs-screen <id> [on|off] ["why"]
//                                            this task can only be answered with somebody logged in
//                                            at the Mac (a menu reading, a live screenshot). It stays
//                                            pending and visible, is not claimed while the screen is
//                                            locked, and returns to the queue by itself once it is
//                                            unlocked. With no argument it says which it is
//   node queue/bin/queue.mjs hold <id> [--by <holder>] ["why"]
//                                            somebody other than the loop is working on this task
//                                            (the intake window, by default). It goes in_progress,
//                                            guard leaves it alone, the loop never claims it, and the
//                                            dashboard says who has it. Refused while a loop runner
//                                            is on it
//   node queue/bin/queue.mjs release <id> ["note"]
//                                            hand a held task back to the queue as pending. Finishing
//                                            it with `status <id> done|dropped|blocked` also ends the hold
//   node queue/bin/queue.mjs priority <id> <p0-critical|p1-high|p2-normal|p3-low>
//   node queue/bin/queue.mjs seq <id> <number>   set sort order within the priority (decimals fine)
//   node queue/bin/queue.mjs decision <taskId> <question> <optionsJSON> [context] [recommended]
//   node queue/bin/queue.mjs resolve <decisionId> <choiceId> [note]
//   node queue/bin/queue.mjs withdraw <decisionId> <reason>
//                                            take a card down that no longer needs an answer (a
//                                            duplicate, or a question settled some other way). It
//                                            never counts as an answer and never starts the work
//                                            it was blocking; the reason is required
//   node queue/bin/queue.mjs alive           print the live loop's pid, or "no" if none is running
//   node queue/bin/queue.mjs guard           reset any in_progress task back to pending (parks one that keeps failing);
//                                            a held task is left alone
//   node queue/bin/queue.mjs compact        collapse old churn events in history.jsonl into counted entries
//   node queue/bin/queue.mjs reset-health   clear the unhealthy flag (the loop does this on start)
//   node queue/bin/queue.mjs script <sha256> <running|broken> <path>
//                                            record which copy of go-loop.sh the loop is running,
//                                            so the dashboard can say when it is older than the file
//   node queue/bin/queue.mjs runner-error <stderrFile> <stdoutFile>
//                                            print the one line of a runner's output worth keeping
//                                            (a sign-in failure first, else the last stderr/stdout line)
//   node queue/bin/queue.mjs runner-classify <stderrFile> <stdoutFile>
//                                            the same line PLUS whether the CLI itself refused, as
//                                            shell vars (RUNNER_ERR/RUNNER_REASON) for the go loop to eval
//   node queue/bin/queue.mjs runner-exit <taskId|-> <exitCode> [--reason signin|spend|''] [error]
//                                            record how a runner ended; prints shell vars
//                                            (OUTCOME/BACKOFF/FAILURES/HEALTH/ENVFAIL/SIGNIN/REASON) for the go loop to eval
//   node queue/bin/queue.mjs runner-resume <taskId> <exitCode> [--reason signin|spend|''] [error]
//                                            whether a runner that stopped with its task in progress,
//                                            saying it was waiting for something, gets its session back
//                                            for one more turn; prints RESUME=0|1 for the go loop to eval
//   node queue/bin/queue.mjs event <ev> [dataJSON]
//   node queue/bin/queue.mjs devapp [--json]
//                                            how far "dist/Photonz Dev.app" is behind the code and
//                                            why nothing is rebuilding it. Prints nothing when the
//                                            app is current. Never touches the app or the lock
//   node queue/bin/queue.mjs state           print aggregate dashboard state JSON
//   node queue/bin/queue.mjs objectives-check
//                                            print what the objectives leave unsaid (a now epic
//                                            with no success criteria, a focus with no spec);
//                                            prints nothing and exits 0 when there is nothing
//   node queue/bin/queue.mjs focus-brief     the manager's focus section (success, mocks,
//                                            competitors, workflow, and any gaps), generated
//                                            from objectives.json; the go loop appends it to
//                                            the manager prompt on every pass
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import * as q from './queue-lib.mjs';

const [cmd, ...args] = process.argv.slice(2);
const pid = process.env.GO_LOOP_PID ? Number(process.env.GO_LOOP_PID) : null;
const out = (v) => console.log(typeof v === 'string' ? v : JSON.stringify(v, null, 2));

// A new task is born, and the queue is told which open tasks already talk about
// the same thing. This is the follow-up bar's fold-first rule made visible at
// the moment it matters (queue/bin/follow-up-bar.md): it warns, it never
// blocks, and it goes to stderr so the id on stdout stays the whole of stdout.
const added = (t) => {
  const near = q.similarTasks(`${t.title} ${t.goal || ''}`, { exclude: t.id });
  if (near.length) {
    console.error(`\nThese open tasks already talk about this. Read them before leaving ${t.id} filed:`);
    for (const r of near) console.error(`  ${r.priority}\t${r.id}\t${r.title}`);
    console.error(`If one of them covers it, fold and drop instead:\n  node queue/bin/queue.mjs log <that-id> "<your finding>"\n  node queue/bin/queue.mjs status ${t.id} dropped "folded into <that-id>"\n`);
  }
  return t.id;
};

// Filing is the one command a runner tries out, and trying it out used to file
// a real task: nine stray tasks titled "x" between 2026-09-23 and 09-26, one of
// them from `addjson '{"title":"x"}' --dry-run`, whose flag was ignored. So a
// flag is either understood or refused, never dropped on the floor, and a title
// too short to say what the task is about is refused before anything is written.
const MIN_TITLE_WORDS = 3;
const fileTask = (rawArgs, fields) => {
  const flags = rawArgs.filter((a) => /^--/.test(a));
  const unknown = flags.filter((f) => f !== '--dry-run');
  if (unknown.length) throw new Error(`unknown option ${unknown.join(', ')}; the only one is --dry-run. Nothing was filed.`);
  const title = String(fields.title || '').trim();
  const words = title.split(/\s+/).filter(Boolean).length;
  if (words < MIN_TITLE_WORDS) {
    throw new Error(`Refused: the title "${title}" has ${words} word${words === 1 ? '' : 's'}. A task title needs at least three words that name the outcome, so it says what the task is about on the dashboard. Nothing was filed.`);
  }
  fields = { ...fields, title };
  if (!flags.includes('--dry-run')) return added(q.addTask(fields));
  const t = q.draftTask(fields);
  const lines = [`Dry run: nothing was filed. This is what would be:`,
    `  id        ${t.id}`, `  priority  ${t.priority} (seq ${t.seq})`, `  title     ${t.title}`];
  if (t.epic) lines.push(`  epic      ${t.epic}`);
  if (t.goal) lines.push(`  goal      ${t.goal}`);
  for (const a of t.acceptance || []) lines.push(`  [ ]       ${a}`);
  const near = q.similarTasks(`${t.title} ${t.goal || ''}`);
  if (near.length) {
    lines.push('Open tasks that already talk about this:');
    for (const r of near) lines.push(`  ${r.priority}\t${r.id}\t${r.title}`);
  }
  return lines.join('\n');
};

try {
  switch (cmd) {
    case 'next': {
      const t = q.claimNext(pid);
      out(t ? t.file : 'none');
      break;
    }
    case 'ready':
      out(String(q.readyTasks().length));
      break;
    case 'idle':
      q.writeStatus({ state: 'idle', task: null, note: 'waiting for tasks', pid });
      break;
    case 'busy':
      q.writeStatus({ state: 'running', task: null, note: args.join(' ') || 'working', pid });
      break;
    case 'stopped':
      q.writeStatus({ state: 'stopped', task: null, note: 'go loop is not running', pid: null });
      break;
    case 'note':
      q.writeStatus({ note: args.join(' ') });
      break;
    // With only an id this READS: people type `status <id>` meaning "show me
    // this task", and on 2026-09-23 that wiped a finished task's status.
    case 'status': {
      if (!args[0]) throw new Error(`usage: queue.mjs status <id> [${q.STATUSES.join('|')}] [note]`);
      if (args.length === 1) {
        const t = q.readTaskDetail(args[0]);
        if (!t) throw new Error(`no task ${args[0]}`);
        const last = (t.log || []).slice(-3).map((e) => `  ${e.t}  ${e.note}`);
        out([`${t.id}`, `  status    ${t.status}${t.heldBy ? `, held by ${t.heldBy} since ${t.heldSince || '?'}` : ''}`, `  priority  ${t.priority} (seq ${t.seq})`, `  title     ${t.title}`,
          ...(t.goal ? [`  goal      ${t.goal}`] : []), ...(last.length ? ['last log lines:', ...last] : [])].join('\n'));
        break;
      }
      out(q.setStatus(args[0], args[1], args.slice(2).join(' '), { checkReach: true }).id);
      break;
    }
    case 'add': {
      const pos = args.filter((a) => !/^--/.test(a));
      out(fileTask(args, { title: pos[0], priority: pos[1] || 'p2-normal', notes: pos.slice(2).join(' ') }));
      break;
    }
    // the structured form, and the one to prefer: it can carry the plain-language
    // goal and the acceptance checklist, which the positional form cannot.
    //   queue.mjs addjson '{"title":"...","goal":"...","acceptance":["..."],"priority":"p2-normal","notes":"..."}'
    case 'addjson':
      out(fileTask(args, JSON.parse(args.find((a) => !/^--/.test(a)) || '{}')));
      break;
    // Search first, file second. The default is the OPEN queue, because the
    // question this answers is "is somebody already on this?".
    case 'search': {
      const all = args[0] === '--all' || args[0] === '-a';
      const { rows, mode, terms } = q.searchTaskRows(args.slice(all ? 1 : 0).join(' '), { all });
      if (!rows.length) { out(`no ${all ? '' : 'open '}tasks match`); break; }
      // A widened match is a weaker claim than an exact one, and saying so is
      // what stops a runner trusting thirteen rows of coincidence.
      if (mode === 'widened') out(`no task carries that phrase. Widened to tasks mentioning all of: ${terms.join(', ')}`);
      for (const r of rows) out(`${r.priority}\t${r.status}\t${r.id}\t${r.title}`);
      out(`${rows.length} match${rows.length === 1 ? '' : 'es'}${mode === 'widened' ? ', widened' : ''}`);
      break;
    }
    case 'log':
      out(q.noteTask(args[0], args.slice(1).join(' ')).id);
      break;
    // Ownership of a failing walk, said rather than guessed. The sweep reads
    // title, goal, notes and acceptance for walk names when a task has not
    // said, and a name quoted as an example reads exactly like a name claimed
    // as work: on 2026-09-14 one failing walk came out owned by three tasks,
    // one of which was the task about this very problem.
    case 'walks': {
      if (!args[0]) throw new Error('usage: queue.mjs walks <id> [<walk> ... | --none]');
      const t = q.readTaskDetail(args[0]);
      if (!t) throw new Error(`no task ${args[0]}`);
      if (args.length === 1) {
        out(!Array.isArray(t.walks) ? 'has not said; the sweep guesses from its wording'
          : t.walks.length ? t.walks.join('\n') : 'owns no walks; the ones it names are examples');
        break;
      }
      const list = args[1] === '--none' ? [] : args.slice(1);
      // A walk that does not exist can never be reported failing, so a typo
      // here is a declaration that silently does nothing. Say so and carry on:
      // a walk about to be written is a fair thing to claim in advance.
      // ...but only when the walks are in reach. A queue pointed somewhere else
      // (a drill, a copy) cannot see the walk library, and a warning made up
      // out of not looking is worse than no warning.
      const library = join(q.REPO, 'Scripts', 'playtest');
      const missing = existsSync(library)
        ? q.normalizeWalks(list).filter((w) => !existsSync(join(library, `${w}.json`)))
        : [];
      if (missing.length) console.error(`No such walk: ${missing.join(', ')} (${library}/<name>.json). Recorded anyway; fix it if that is a typo.`);
      out(q.setWalks(args[0], list).id);
      break;
    }
    // A feature meant to stay off by default, said in words, so `status done`
    // does not refuse it for having only walks that switch it on.
    case 'off-by-default': {
      if (!args[0]) throw new Error('usage: queue.mjs off-by-default <id> ["why" | --clear]');
      const t = q.readTaskDetail(args[0]);
      if (!t) throw new Error(`no task ${args[0]}`);
      if (args.length === 1) {
        out(t.offByDefault ? `deliberately off by default: ${t.offByDefault}` : 'not said; done needs a walk that reaches it at defaults');
        break;
      }
      const why = args[1] === '--clear' ? '' : args.slice(1).join(' ');
      if (args[1] !== '--clear' && !why.trim()) throw new Error('say why it is off by default, in words');
      out(q.setOffByDefault(args[0], why).id);
      break;
    }
    case 'needs-screen': {
      if (!args[0]) throw new Error('usage: queue.mjs needs-screen <id> [on|off] ["why"]');
      const t = q.readTaskDetail(args[0]);
      if (!t) throw new Error(`no task ${args[0]}`);
      if (args.length === 1) {
        out(t.waitsForUnlockedScreen
          ? `needs somebody at the Mac; the screen is ${q.screenIsLocked() ? 'LOCKED, so it is waiting' : 'unlocked, so it is claimable'}`
          : 'claimable whether or not the screen is locked');
        break;
      }
      out(q.setNeedsUnlockedScreen(args[0], args[1] !== 'off', args.slice(2).join(' ')).id);
      break;
    }
    case 'hold': {
      if (!args[0]) throw new Error('usage: queue.mjs hold <id> [--by <holder>] ["why"]');
      const rest = args.slice(1);
      let by = 'intake';
      const at = rest.indexOf('--by');
      if (at >= 0) {
        by = rest[at + 1] || '';
        if (!by || by.startsWith('--')) throw new Error('--by needs a holder name');
        rest.splice(at, 2);
      }
      const unknown = rest.filter((a) => /^--/.test(a));
      if (unknown.length) throw new Error(`unknown option ${unknown.join(', ')}; the only one is --by. Nothing was held.`);
      out(q.holdTask(args[0], by, rest.join(' ')).id);
      break;
    }
    case 'release':
      if (!args[0]) throw new Error('usage: queue.mjs release <id> ["note"]');
      out(q.releaseTask(args[0], args.slice(1).join(' ')).id);
      break;
    case 'priority':
      out(q.setPriority(args[0], args[1]).id);
      break;
    case 'seq':
      out(q.setSeq(args[0], Number(args[1])).id);
      break;
    case 'decision':
      out(q.addDecision({ taskId: args[0], question: args[1], options: JSON.parse(args[2] || '[]'), context: args[3] || '', recommended: args[4] || '' }).id);
      break;
    case 'resolve':
      out(q.resolveDecision(args[0], args[1], args.slice(2).join(' ')).id);
      break;
    // Tidying up is not answering. This is the only way a question leaves the
    // dashboard without somebody choosing an option, and it leaves the task it
    // was blocking exactly as blocked as it found it.
    case 'withdraw':
      if (!args[0]) throw new Error('usage: queue.mjs withdraw <decisionId> "<why it no longer needs an answer>"');
      out(q.withdrawDecision(args[0], args.slice(1).join(' ')).id);
      break;
    case 'alive': {
      const s = q.readStatus();
      out(q.loopAlive(s) ? String(s.pid) : 'no');
      break;
    }
    case 'guard':
      out(q.guardStuck());
      break;
    case 'compact': {
      const r = q.compactHistory();
      out(`history: ${r.before} -> ${r.after} events${r.changed ? '' : ' (already compact)'}`);
      break;
    }
    // A restart is a fresh claim about health: an unhealthy flag from a previous
    // run should not colour a loop that has not tried anything yet.
    case 'reset-health':
      q.writeStatus({ health: 'ok', consecutiveFailures: 0, lastError: null, failureStreak: null });
      break;
    // The loop naming the copy of itself it is running. Freshness is not
    // decided here: loopScript() hashes the file at read time, so a recorded
    // answer can never go stale behind the dashboard's back.
    case 'script':
      q.writeStatus({ script: { hash: args[0] || null, state: args[1] || 'running', path: args[2] || null, since: new Date().toISOString() } });
      break;
    // Missing files read as empty: the loop must get an answer even when a
    // temp file vanished, and "no error text" is the honest one.
    case 'runner-error': {
      const slurp = (f) => { try { return f ? readFileSync(f, 'utf8') : ''; } catch { return ''; } };
      out(q.pickRunnerError(slurp(args[0]), slurp(args[1])));
      break;
    }
    // One reading of the whole run, so the verdict travels with the line instead
    // of being guessed again from it: only here is it visible that the words
    // "spend limit" came out of the runner's own tool call.
    case 'runner-classify': {
      const slurp = (f) => { try { return f ? readFileSync(f, 'utf8') : ''; } catch { return ''; } };
      const shq = (s) => `'${String(s ?? '').replace(/'/g, `'\\''`)}'`;
      const c = q.classifyRunnerOutput(slurp(args[0]), slurp(args[1]));
      out(`RUNNER_ERR=${shq(c.line)}\nRUNNER_REASON=${shq(c.reason || '')}`);
      break;
    }
    // The go loop evals this, so print shell assignments, not JSON. OUTCOME is
    // ok|failed|parked|signin|spend, BACKOFF is seconds to wait before claiming
    // again, REASON is the refusal the runner's words named (signin|spend) or
    // empty.
    case 'runner-exit': {
      // --reason is the verdict runner-classify already reached. Present means
      // trust it (empty = no refusal, and something looked); absent means fall
      // back to reading the error line, for anything still calling the old way.
      const rest = args.slice(2);
      const flag = rest.indexOf('--reason');
      const given = flag === -1 ? undefined : (rest[flag + 1] || '');
      if (flag !== -1) rest.splice(flag, 2);
      const r = q.recordRunnerExit({
        taskId: args[0] && args[0] !== '-' ? args[0] : null,
        exit: Number(args[1] || 0),
        error: rest.join(' '),
        kind: args[0] && args[0] !== '-' ? 'task' : 'digest',
        ...(given === undefined ? {} : { reason: given }),
      });
      const health = (r.reason || r.consecutiveFailures >= q.UNHEALTHY_AT) ? 'unhealthy' : 'ok';
      // NOTIFY is the one bit the loop cannot work out for itself: whether this
      // refusal is the START of a stall (or a day older than the last time the
      // person was told), rather than one more retry inside a stall they have
      // already been told about.
      out(`OUTCOME=${r.outcome} BACKOFF=${r.backoff} FAILURES=${r.consecutiveFailures} HEALTH=${health} ENVFAIL=${r.environment ? 1 : 0} SIGNIN=${r.signIn ? 1 : 0} REASON=${r.reason || ''} NOTIFY=${r.notify ? 1 : 0} STALLHOURS=${r.stallHours || 0}`);
      break;
    }
    // Asked BEFORE runner-exit: a yes means the loop resumes the same session
    // and only records the exit after that second turn.
    case 'runner-resume': {
      const rest = args.slice(2);
      const flag = rest.indexOf('--reason');
      const reason = flag === -1 ? '' : (rest[flag + 1] || '');
      if (flag !== -1) rest.splice(flag, 2);
      const r = q.decideRunnerResume({
        taskId: args[0] && args[0] !== '-' ? args[0] : null,
        exit: Number(args[1] || 0),
        error: rest.join(' '),
        reason,
      });
      out(`RESUME=${r.resume ? 1 : 0}`);
      break;
    }
    // One plain line about how far "dist/Photonz Dev.app" is behind the code,
    // and why nobody is rebuilding it. Silent when it is current, so a script
    // can call it unconditionally. Exits 0 either way: this reports, it never
    // fails a build and it never touches the app or the lock.
    case 'devapp': {
      const st = q.devAppState();
      if (args[0] === '--json') { out(st); break; }
      const line = q.devAppSentence(st);
      if (line) out(line[0].toUpperCase() + line.slice(1));
      break;
    }
    case 'event':
      q.appendEvent(args[0], args[1] ? JSON.parse(args[1]) : {});
      break;
    case 'state':
      out(q.aggregateState());
      break;
    case 'objectives-check': {
      const gaps = q.objectivesGaps();
      for (const g of gaps) console.log(g);
      if (gaps.length) process.exit(1);
      break;
    }
    case 'focus-brief':
      out(q.focusBrief());
      break;
    default:
      console.error('unknown command; see header of queue.mjs');
      process.exit(1);
  }
} catch (e) {
  console.error(String(e.message || e));
  process.exit(1);
}
