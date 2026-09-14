## A follow-up has a bar to clear

Every pass of this loop is asked to file what it left rough, and every pass does
it faithfully. That is why the queue grew by about forty tasks a week through
September 2026 while the healthy size is around twelve open. The cost is not
clutter, it is order: a report from the user waits behind a wall of the loop's
own homework, and a queue nobody can read is a queue nobody can steer. So
filing is an argument you make, not a reflex.

**A new task is earned when BOTH of these are true:**

1. **A person would notice.** Someone using the app hits it, or is stopped by
   it, or ends up wrong about what the app just did. Someone reading the
   dashboard or running the loop sees the wrong thing. A name only an agent
   reads, a shape that could be tidier, a comment, a wording nit buried in code,
   a "we could also one day" idea: none of those clear the bar.
2. **No open task already covers it.** Search first (below). If one covers it,
   fold your finding into that task instead of filing its near-twin.

**Anything actually broken clears the bar on its own.** A crash, a wrong number,
work lost, a control that does nothing, a walk that fails, a step of the loop
that does not run: file it, and file it even when it looks small. This bar
exists to stop near-twins and nits, never to let a real defect go unrecorded. A
bug still carries its reproduction: see "A bug you file must be reproduced".

### Search, then fold

```
node queue/bin/queue.mjs search "corner radius popover"     # open tasks that mention those words
node queue/bin/queue.mjs search --all "corner radius"       # done and dropped ones too
```

It reads title, goal, checklist, working detail and every line of every task
log, so search **the words of the problem**, not a title you imagine. The exact
phrase wins when it hits anything; when it hits nothing the search widens to
tasks carrying all your words in any order. Try two or three phrasings before
you conclude nothing covers it. A `--all` hit on a done task is worth reading
too: a thing fixed and now broken again belongs in that history, as a reopen or
as a new task that cites it.

When something already covers it, fold:

```
node queue/bin/queue.mjs log <that-task-id> "also happens in the effects panel: <what you saw>"
```

If your finding widens what done means for that task, add it to that task's
`acceptance` as well, so the runner who picks it up has to satisfy it.

Filing also checks for you: `queue.mjs add` and `addjson` print the open tasks
that already talk about the same thing, right after the new one is written. That
is a prompt to go read them, not a verdict. When one of them covers it, fold and
drop the task you just filed, exactly as the warning spells out.

### What does not clear the bar still gets written down

Nothing is thrown away. A rough edge that did not earn its own task goes in the
log of the task you are finishing, where the dashboard shows it under that task
and where `search` reads it:

```
node queue/bin/queue.mjs log <your-task-id> "left rough: <what it is, where it is, why it did not earn a task>"
```

That is the whole alternative: not a cap on how much gets filed, which would
lose real findings silently, but a bar plus a place to put everything under it.
A later pass looking at that area finds it, and if the same rough edge shows up
twice it has stopped being a nit and can be filed then.

The `rough` list in an audit is unchanged: keep writing it honestly. It is what
the user reacts to, and their reaction becomes a task by their hand.
