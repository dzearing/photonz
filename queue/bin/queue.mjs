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
//   node queue/bin/queue.mjs add <title> [priority] [notes]
//   node queue/bin/queue.mjs addjson '<json>'   preferred: carries goal + acceptance checklist
//   node queue/bin/queue.mjs search [--all] <words>
//                                            open tasks whose title, goal, checklist, working detail
//                                            or log mention those words. Search BEFORE filing a
//                                            follow-up; --all reads done and dropped ones too
//   node queue/bin/queue.mjs log <id> <note>    append one line to a task's log without changing its
//                                            status: how a finding folds into a task that already
//                                            covers it, and where a rough edge goes when it does not
//                                            earn its own task (queue/bin/follow-up-bar.md)
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
//   node queue/bin/queue.mjs guard           reset any in_progress task back to pending (parks one that keeps failing)
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
//   node queue/bin/queue.mjs event <ev> [dataJSON]
//   node queue/bin/queue.mjs state           print aggregate dashboard state JSON
import { readFileSync } from 'node:fs';
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
    case 'status':
      out(q.setStatus(args[0], args[1], args.slice(2).join(' ')).id);
      break;
    case 'add':
      out(added(q.addTask({ title: args[0], priority: args[1] || 'p2-normal', notes: args.slice(2).join(' ') })));
      break;
    // the structured form, and the one to prefer: it can carry the plain-language
    // goal and the acceptance checklist, which the positional form cannot.
    //   queue.mjs addjson '{"title":"...","goal":"...","acceptance":["..."],"priority":"p2-normal","notes":"..."}'
    case 'addjson':
      out(added(q.addTask(JSON.parse(args[0]))));
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
      out(`OUTCOME=${r.outcome} BACKOFF=${r.backoff} FAILURES=${r.consecutiveFailures} HEALTH=${health} ENVFAIL=${r.environment ? 1 : 0} SIGNIN=${r.signIn ? 1 : 0} REASON=${r.reason || ''}`);
      break;
    }
    case 'event':
      q.appendEvent(args[0], args[1] ? JSON.parse(args[1]) : {});
      break;
    case 'state':
      out(q.aggregateState());
      break;
    default:
      console.error('unknown command; see header of queue.mjs');
      process.exit(1);
  }
} catch (e) {
  console.error(String(e.message || e));
  process.exit(1);
}
