#!/usr/bin/env node
// Photonz task queue CLI. Thin wrapper over queue-lib.mjs so the go loop,
// task runners, and humans all mutate the queue the same way.
//
//   node queue/bin/queue.mjs next            claim highest-priority ready task; prints its file path, or "none"
//   node queue/bin/queue.mjs idle            mark the loop idle (heartbeat)
//   node queue/bin/queue.mjs stopped         mark the loop stopped
//   node queue/bin/queue.mjs note <msg>      update the live status note (shown on the dashboard)
//   node queue/bin/queue.mjs status <id> <pending|in_progress|blocked|done|dropped> [note]
//   node queue/bin/queue.mjs add <title> [priority] [notes]
//   node queue/bin/queue.mjs priority <id> <p0-critical|p1-high|p2-normal|p3-low>
//   node queue/bin/queue.mjs decision <taskId> <question> <optionsJSON> [context] [recommended]
//   node queue/bin/queue.mjs resolve <decisionId> <choiceId> [note]
//   node queue/bin/queue.mjs guard           reset any in_progress task back to pending
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
    case 'idle':
      q.writeStatus({ state: 'idle', task: null, note: 'waiting for tasks', pid });
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
    case 'priority':
      out(q.setPriority(args[0], args[1]).id);
      break;
    case 'decision':
      out(q.addDecision({ taskId: args[0], question: args[1], options: JSON.parse(args[2] || '[]'), context: args[3] || '', recommended: args[4] || '' }).id);
      break;
    case 'resolve':
      out(q.resolveDecision(args[0], args[1], args.slice(2).join(' ')).id);
      break;
    case 'guard':
      out(q.guardStuck());
      break;
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
