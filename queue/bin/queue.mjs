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
//   node queue/bin/queue.mjs priority <id> <p0-critical|p1-high|p2-normal|p3-low>
//   node queue/bin/queue.mjs seq <id> <number>   set sort order within the priority (decimals fine)
//   node queue/bin/queue.mjs decision <taskId> <question> <optionsJSON> [context] [recommended]
//   node queue/bin/queue.mjs resolve <decisionId> <choiceId> [note]
//   node queue/bin/queue.mjs alive           print the live loop's pid, or "no" if none is running
//   node queue/bin/queue.mjs guard           reset any in_progress task back to pending (parks one that keeps failing)
//   node queue/bin/queue.mjs compact        collapse old churn events in history.jsonl into counted entries
//   node queue/bin/queue.mjs reset-health   clear the unhealthy flag (the loop does this on start)
//   node queue/bin/queue.mjs runner-exit <taskId|-> <exitCode> [error]
//                                            record how a runner ended; prints shell vars
//                                            (OUTCOME/BACKOFF/FAILURES/HEALTH) for the go loop to eval
//   node queue/bin/queue.mjs event <ev> [dataJSON]
//   node queue/bin/queue.mjs state           print aggregate dashboard state JSON
import * as q from './queue-lib.mjs';

const [cmd, ...args] = process.argv.slice(2);
const pid = process.env.GO_LOOP_PID ? Number(process.env.GO_LOOP_PID) : null;
const out = (v) => console.log(typeof v === 'string' ? v : JSON.stringify(v, null, 2));

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
      out(q.addTask({ title: args[0], priority: args[1] || 'p2-normal', notes: args.slice(2).join(' ') }).id);
      break;
    // the structured form, and the one to prefer: it can carry the plain-language
    // goal and the acceptance checklist, which the positional form cannot.
    //   queue.mjs addjson '{"title":"...","goal":"...","acceptance":["..."],"priority":"p2-normal","notes":"..."}'
    case 'addjson':
      out(q.addTask(JSON.parse(args[0])).id);
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
    // The go loop evals this, so print shell assignments, not JSON. OUTCOME is
    // ok|failed|parked, BACKOFF is seconds to wait before claiming again.
    case 'runner-exit': {
      const r = q.recordRunnerExit({
        taskId: args[0] && args[0] !== '-' ? args[0] : null,
        exit: Number(args[1] || 0),
        error: args.slice(2).join(' '),
        kind: args[0] && args[0] !== '-' ? 'task' : 'digest',
      });
      out(`OUTCOME=${r.outcome} BACKOFF=${r.backoff} FAILURES=${r.consecutiveFailures} HEALTH=${r.consecutiveFailures >= q.UNHEALTHY_AT ? 'unhealthy' : 'ok'} ENVFAIL=${r.environment ? 1 : 0}`);
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
