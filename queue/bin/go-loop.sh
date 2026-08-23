#!/bin/zsh
# Photonz go loop: executes queued tasks one at a time, unmanned.
# Run via the /go skill (spawns this in a Ghoztty window titled "Photonz Go Loop")
# or directly:  queue/bin/go-loop.sh
# Stop with ctrl-c; status.json is marked stopped on the way out.
#
# Env:
#   PHOTONZ_QUEUE_DIR     point the loop at a throwaway queue (used by
#                         queue/bin/failure-drill.sh); also suppresses git push.
#   PHOTONZ_BACKOFF_STEPS comma-separated seconds to wait after the 1st, 2nd, ...
#                         consecutive runner failure. Default 30,120,300,900,1800.
#   PHOTONZ_MAX_ITERS     stop after N loop passes (drills only; 0 = forever).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
export GO_LOOP_PID=$$
QDIR="${PHOTONZ_QUEUE_DIR:-$REPO/queue}"
SANDBOX=0; [[ -n "${PHOTONZ_QUEUE_DIR:-}" ]] && SANDBOX=1
MAX_ITERS="${PHOTONZ_MAX_ITERS:-0}"
Q() { node queue/bin/queue.mjs "$@"; }
LOG="$QDIR/loop.log"
mkdir -p "$QDIR/digests"
# stream-json + the formatter give this window a live feed of what each runner
# is doing (tool by tool), instead of dead air until a task ends.
CLAUDE_FLAGS=(--dangerously-skip-permissions --output-format stream-json --verbose)
# Set by run_runner: the last non-blank line the runner complained with. This is
# what the dashboard shows when the loop goes unhealthy, so a wedged loop names
# its own cause ("Credit balance is too low") instead of just sitting there.
RUNNER_ERR=""
run_runner() { # $1 = prompt text; streams formatted output to the pane AND loop.log
  local errf outf rc
  errf=$(mktemp -t goloop-err) || return 1
  outf=$(mktemp -t goloop-out) || return 1
  claude -p "${CLAUDE_FLAGS[@]}" "$1" 2>"$errf" | node queue/bin/stream-format.mjs | tee -a "$LOG" "$outf"
  rc=${pipestatus[1]}
  cat "$errf" >> "$LOG"
  # Prefer stderr; some failures (API errors mid-stream) only ever reach stdout.
  RUNNER_ERR=$(grep -v '^[[:space:]]*$' "$errf" | tail -n 1)
  [[ -z "$RUNNER_ERR" ]] && RUNNER_ERR=$(grep -v '^[[:space:]]*$' "$outf" | tail -n 1)
  rm -f "$errf" "$outf"
  return $rc
}

# Ask the queue what that runner exit meant and adopt its answer. Defaults are
# set first so a queue CLI that itself fails still leaves the loop with a sane
# (and cautious) OUTCOME/BACKOFF rather than an unset variable.
record_exit() { # $1 = task id or "-", $2 = exit code
  OUTCOME=failed; BACKOFF=60; FAILURES=1; HEALTH=unhealthy; ENVFAIL=0
  eval "$(Q runner-exit "$1" "$2" "$RUNNER_ERR")"
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
  echo "[go-loop] declining to start: another go loop is already running (pid $OWNER, per $QDIR/status.json)." | tee -a "$LOG"
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

echo "[go-loop] started pid=$$ repo=$REPO queue=$QDIR" | tee -a "$LOG"
Q event loop_started "{\"pid\":$$}"
Q reset-health
Q busy "starting up"

# Wait out a runner failure. $1 = seconds, $2 = consecutive failures, $3 = last
# error. The banner says unhealthy for the whole wait so the window never reads
# as working when nothing is working.
backoff_wait() {
  local secs=$1 fails=$2 err=$3
  echo "[go-loop] $(date +%T) unhealthy: $fails consecutive runner failures; waiting ${secs}s. Last error: $err" | tee -a "$LOG"
  banner "**Go loop unhealthy** $fails runner failures in a row, retrying in ${secs}s. Last error: $err"
  state idle
  title "photonz: go-loop (unhealthy)"
  sleep "$secs"
  title "photonz: go-loop"
}

# loop.log is the raw runner transcript and grows without limit: one stuck night
# on 2026-08-23 put 2.9MB into it. Keep one generation so a loop left running
# cannot fill the disk, and so tailing it stays instant.
LOG_MAX_BYTES=$((32 * 1024 * 1024))
rotate_log() {
  local size
  size=$(stat -f %z "$LOG" 2>/dev/null || echo 0)
  (( size > LOG_MAX_BYTES )) && mv -f "$LOG" "$LOG.1"
  return 0
}

ITERS=0
while :; do
  TODAY=$(date +%F)
  ITERS=$((ITERS + 1))
  rotate_log
  [[ "$MAX_ITERS" != 0 && $ITERS -gt $MAX_ITERS ]] && { echo "[go-loop] reached PHOTONZ_MAX_ITERS=$MAX_ITERS, exiting" | tee -a "$LOG"; cleanup; }

  # Daily digest + triage: once per calendar day, at or after 05:00 so it reads
  # as a morning report rather than a midnight one. (10# forces base-10: date
  # prints 08/09 and zsh arithmetic would otherwise read those as bad octal.)
  if [[ ! -f "$QDIR/digests/$TODAY.md" && $((10#$(date +%H))) -ge 5 ]]; then
    echo "[go-loop] $(date +%T) generating digest + triage for $TODAY" | tee -a "$LOG"
    Q busy "running daily digest + triage"
    banner "**Go loop** running daily digest + triage for $TODAY"
    state busy
    run_runner "$(cat queue/bin/digest-prompt.md)"
    DIGEST_EXIT=$?
    record_exit - "$DIGEST_EXIT"
    # If the digest still does not exist, write a stub so we do not spin on it.
    if [[ ! -f "$QDIR/digests/$TODAY.md" ]]; then
      printf '# Daily digest %s\n\n## Summary\nDigest generation failed; see %s.\n\n## Reflections\n(none)\n\n## Triage review\n(skipped)\n' "$TODAY" "$LOG" > "$QDIR/digests/$TODAY.md"
      Q event digest_failed "{}"
    fi
    if [[ "$OUTCOME" != "ok" ]]; then
      backoff_wait "$BACKOFF" "$FAILURES" "$RUNNER_ERR"
      continue
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

  TASK_ID=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).id)" "$TASK_FILE")
  TASK_TITLE=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).title)" "$TASK_FILE")
  echo "[go-loop] $(date +%T) running task $TASK_ID" | tee -a "$LOG"
  banner "**Go loop** working: $TASK_TITLE ($TASK_ID)"
  state busy

  run_runner "$(cat queue/bin/runner-prompt.md)

TASK FILE: $TASK_FILE"
  EXIT=$?
  echo "[go-loop] $(date +%T) task $TASK_ID runner exited $EXIT" | tee -a "$LOG"

  # A runner MUST finalize its task. One that did not is a failure, not a free
  # retry: recorded with its exit code and last error, retried more slowly each
  # time, and after three straight failures of the same task, parked.
  record_exit "$TASK_ID" "$EXIT"
  # Blunt safety net for anything the line above did not cover.
  Q guard >> "$LOG" 2>&1
  # Runners push their own commits; this catches anything they left behind.
  [[ $SANDBOX == 0 ]] && { git push -q origin main >> "$LOG" 2>&1 || true }

  if [[ "$OUTCOME" == "ok" ]]; then
    Q note "between tasks"
    sleep 5
    continue
  fi

  [[ "$OUTCOME" == "parked" ]] && echo "[go-loop] $(date +%T) parked $TASK_ID after repeated runner failures" | tee -a "$LOG"
  backoff_wait "$BACKOFF" "$FAILURES" "$RUNNER_ERR"
done
