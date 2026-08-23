#!/bin/zsh
# Photonz go loop: executes queued tasks one at a time, unmanned.
# Run via the /go skill (spawns this in a Ghoztty window titled "Photonz Go Loop")
# or directly:  queue/bin/go-loop.sh
# Stop with ctrl-c; status.json is marked stopped on the way out.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
export GO_LOOP_PID=$$
Q() { node queue/bin/queue.mjs "$@"; }
LOG="queue/loop.log"
# stream-json + the formatter give this window a live feed of what each runner
# is doing (tool by tool), instead of dead air until a task ends.
CLAUDE_FLAGS=(--dangerously-skip-permissions --output-format stream-json --verbose)
run_runner() { # $1 = prompt text; streams formatted output to the pane AND loop.log
  claude -p "${CLAUDE_FLAGS[@]}" "$1" 2>>"$LOG" | node queue/bin/stream-format.mjs | tee -a "$LOG"
  return ${pipestatus[1]}
}

banner() { printf '\033]7778;%s\007' "$1"; }   # sticky Ghoztty pane banner
state()  { printf '\033]7777;%s\007' "$1"; }   # Ghoztty activity state
title()  { printf '\033]2;%s\007' "$1"; }      # window title

# Refuse to double-start: two loops race on task claims (seen 2026-08-22,
# pids 56941/59762). status.json records the owning pid; if that process is
# alive AND still looks like a go loop (pid reuse guard), decline. A stale
# pid is fine to take over.
OWNER=$(Q alive)
if [[ "$OWNER" != "no" && "$OWNER" != "$$" ]] && ps -o command= -p "$OWNER" 2>/dev/null | grep -q 'go-loop'; then
  echo "[go-loop] declining to start: another go loop is already running (pid $OWNER, per queue/status.json)." | tee -a "$LOG"
  echo "[go-loop] stop it first (ctrl-c in its window, or: kill $OWNER) and try again." | tee -a "$LOG"
  exit 1
fi

cleanup() {
  Q stopped
  banner "**Go loop stopped**"
  state idle
  title "photonz: go-loop (stopped)"
  exit 0
}
trap cleanup INT TERM
title "photonz: go-loop"

echo "[go-loop] started pid=$$ repo=$REPO" | tee -a "$LOG"
Q event loop_started "{\"pid\":$$}"
Q busy "starting up"

while :; do
  TODAY=$(date +%F)

  # Daily digest + triage: once per calendar day, before picking new work.
  if [[ ! -f "queue/digests/$TODAY.md" ]]; then
    echo "[go-loop] $(date +%T) generating digest + triage for $TODAY" | tee -a "$LOG"
    Q busy "running daily digest + triage"
    banner "**Go loop** running daily digest + triage for $TODAY"
    state busy
    run_runner "$(cat queue/bin/digest-prompt.md)"
    # If the digest still does not exist, write a stub so we do not spin on it.
    if [[ ! -f "queue/digests/$TODAY.md" ]]; then
      printf '# Daily digest %s\n\n## Summary\nDigest generation failed; see queue/loop.log.\n\n## Reflections\n(none)\n\n## Triage review\n(skipped)\n' "$TODAY" > "queue/digests/$TODAY.md"
      Q event digest_failed "{}"
    fi
  fi

  # Claim the next ready task.
  TASK_FILE=$(Q next)
  if [[ "$TASK_FILE" == "none" ]]; then
    Q idle
    banner "**Go loop** idle, no ready tasks. Queue one from the dashboard."
    state idle
    sleep 60
    continue
  fi

  TASK_ID=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$TASK_FILE','utf8')).id)")
  TASK_TITLE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$TASK_FILE','utf8')).title)")
  echo "[go-loop] $(date +%T) running task $TASK_ID" | tee -a "$LOG"
  banner "**Go loop** working: $TASK_TITLE ($TASK_ID)"
  state busy

  run_runner "$(cat queue/bin/runner-prompt.md)

TASK FILE: $TASK_FILE"
  EXIT=$?
  echo "[go-loop] $(date +%T) task $TASK_ID runner exited $EXIT" | tee -a "$LOG"

  # Safety net: a runner must finalize its task; reset it if it did not.
  Q guard >> "$LOG" 2>&1
  # Runners push their own commits; this catches anything they left behind.
  git push -q origin main >> "$LOG" 2>&1 || true
  Q note "between tasks"
  sleep 5
done
