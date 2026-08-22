---
name: go
description: Start the unmanned Photonz go loop and set this window up for monitoring. Use when the user runs /go or asks to start, restart, or check the go loop that executes queued tasks. Spawns the loop in a Ghoztty window titled "Photonz Go Loop" and splits the current window with the live dashboard on the right.
---

# /go: start the go loop and the monitoring layout

The go loop (`queue/bin/go-loop.sh`) runs the task queue unmanned: a daily digest
plus triage pass, then one task at a time, each in a fresh headless agent. The
dashboard (Project section of the design site) is the monitoring surface. This
skill makes "get it all running again after a reboot" one command. Everything is
idempotent; running /go when things are already up just verifies and reports.

## Steps

1. **Dev server.** `curl -s -m 2 http://127.0.0.1:8791/__rev` from the repo root.
   If it fails:
   `cd docs/design/mocks && nohup node dev-server.mjs >/tmp/photonz-mock-server.log 2>&1 & disown`
   then re-curl until it answers (a couple of seconds).

2. **Go loop window.** Check `ghoztty +list --json` for a window with target
   `photonz-go-loop`, and confirm its pane's `exit_code` is `null` (still
   running). Note: on a fresh boot Ghoztty may not be running; `+new-window`
   auto-launches it, but `+list` errors, so treat a `+list` failure as "no loop
   window". If missing or exited:
   - `ghoztty +close --target=photonz-go-loop` (safe no-op when absent)
   - `ghoztty +new-window --target=photonz-go-loop --title="Photonz Go Loop" --no-activate --working-directory=<repo root> --command="queue/bin/go-loop.sh"`
   The loop keeps its own pane banner and activity state current, so the window
   title plus banner is the liveness signal a human can read at a glance.

3. **Verify the loop is actually alive** (do not skip): within ~10 seconds
   `queue/status.json` gets a fresh `updatedAt` and a `pid`; confirm with
   `node queue/bin/queue.mjs state | head` or check
   `ghoztty +read --name=photonz-go-loop --lines=5` shows the `[go-loop] started`
   line. If it did not start, read `queue/loop.log` and fix before reporting.

4. **Monitoring layout in THIS window**: chat stays left, dashboard on the right.
   `ghoztty +split --pane="$GHOZTTY_PANE_ID" --direction=right --split-percent=55 --name=photonz-dashboard --view=http://127.0.0.1:8791/`
   Idempotent: if the pane already exists it is focused, not duplicated.

5. **Report** in one short paragraph: loop state (fresh start or already
   running), current/next task from `queue.mjs state` (loop, next, decisions
   pending), and a reminder that decisions are resolved on the dashboard's
   Summary tab.

## Stopping

`ghoztty +send-keys --target=photonz-go-loop C-c` stops the loop cleanly (its
trap marks `status.json` stopped). `ghoztty +close --target=photonz-go-loop`
closes the window.
