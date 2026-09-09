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
#   PHOTONZ_MANAGER_LOW_WATER  run the manager pass when fewer than this many
#                         tasks are ready to claim. Default 3; 0 disables it.
#   PHOTONZ_MANAGER_COOLDOWN   seconds between manager passes. Default 1200.
#   PHOTONZ_RUNNER_MODEL  model every runner (task, manager, digest) runs on.
#                         Default claude-opus-5: the user asked on 2026-09-01
#                         that the loop run on Opus 5 with high thinking.
#   PHOTONZ_RUNNER_EFFORT effort level for those runners. Default high.
#   PHOTONZ_AUTO_REFRESH  0 to stop the loop rebuilding and relaunching the
#                         user's dev app after a task lands app code. Default 1.
#   PHOTONZ_DIGEST_HOUR   earliest local hour for the daily digest. Default 5
#                         (drills set 0 so the digest pass runs whenever).
#   PHOTONZ_LOOP_RELOAD   0 to stop the loop adopting edits to this file
#                         between tasks. Default 1.
#   PHOTONZ_LOOP_ITERS    set by the loop on itself across a reload; not for
#                         hand use.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
export GO_LOOP_PID=$$
# The absolute path of THIS file, kept for the reload check below. :A resolves
# it whole, so the check still works if the loop was started through a relative
# path or a symlink.
SCRIPT="${0:A}"
QDIR="${PHOTONZ_QUEUE_DIR:-$REPO/queue}"
SANDBOX=0; [[ -n "${PHOTONZ_QUEUE_DIR:-}" ]] && SANDBOX=1
MAX_ITERS="${PHOTONZ_MAX_ITERS:-0}"
Q() { node queue/bin/queue.mjs "$@"; }
LOG="$QDIR/loop.log"
mkdir -p "$QDIR/digests"
# stream-json + the formatter give this window a live feed of what each runner
# is doing (tool by tool), instead of dead air until a task ends.
RUNNER_MODEL="${PHOTONZ_RUNNER_MODEL:-claude-opus-5}"
RUNNER_EFFORT="${PHOTONZ_RUNNER_EFFORT:-high}"
CLAUDE_FLAGS=(--dangerously-skip-permissions --output-format stream-json --verbose
              --model "$RUNNER_MODEL" --effort "$RUNNER_EFFORT")
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
  # The queue picks the telling line: a sign-in failure wherever it sits, else
  # the last stderr line, else the last stdout line (some failures, API errors
  # mid-stream, only ever reach stdout).
  RUNNER_ERR=$(Q runner-error "$errf" "$outf")
  rm -f "$errf" "$outf"
  return $rc
}

# Ask the queue what that runner exit meant and adopt its answer. Defaults are
# set first so a queue CLI that itself fails still leaves the loop with a sane
# (and cautious) OUTCOME/BACKOFF rather than an unset variable. SIGNIN=1 means
# the runner could not authenticate: the queue charged nothing to the task, and
# the loop's job is to say so and wait for a person to log in. REASON names the
# refusal the runner's own words carried (signin, spend) or is empty; a digest
# run that ended in one is deferred, never stubbed.
record_exit() { # $1 = task id or "-", $2 = exit code
  OUTCOME=failed; BACKOFF=60; FAILURES=1; HEALTH=unhealthy; ENVFAIL=0; SIGNIN=0; REASON=""
  eval "$(Q runner-exit "$1" "$2" "$RUNNER_ERR")"
}

# Manager pass: the loop's own product manager. Whenever fewer than
# MANAGER_LOW_WATER tasks are ready to claim, a fresh agent reads the
# objectives, measures the app against them (and against the competition,
# the IA, the workflows, the UI, the architecture), and files the next batch
# of one-sitting tasks, so the queue refills itself instead of waiting for a
# human or for the 5am digest. See queue/bin/manager-prompt.md.
MANAGER_LOW_WATER="${PHOTONZ_MANAGER_LOW_WATER:-3}"
MANAGER_COOLDOWN="${PHOTONZ_MANAGER_COOLDOWN:-1200}"
MANAGER_STAMP="$QDIR/manager/.last-run"
mkdir -p "$QDIR/manager"
manager_due() { # $1 = ready task count; true when a pass should run now
  (( SANDBOX == 0 )) || return 1
  (( MANAGER_LOW_WATER > 0 )) || return 1
  [[ -f "$MANAGER_STAMP" ]] || return 0
  local last; last=$(stat -f %m "$MANAGER_STAMP" 2>/dev/null || echo 0)
  # The objectives are the user talking to the loop. When they change what the
  # app is FOR, a queue full of the old focus is the wrong queue, however full
  # it is, so a pass runs regardless of the ready count (2026-09-02: the user
  # moved the focus to building components and nothing would have noticed until
  # the queue drained days later). The cooldown still applies, so a burst of
  # edits costs one pass.
  local objectives="$QDIR/objectives.json" changed=0
  [[ -f "$objectives" ]] && (( $(stat -f %m "$objectives" 2>/dev/null || echo 0) > last )) && changed=1
  (( changed )) || (( $1 < MANAGER_LOW_WATER )) || return 1
  (( $(date +%s) - last >= MANAGER_COOLDOWN ))
}
manager_pass() { # $1 = ready task count (for the log)
  echo "[go-loop] $(date +%T) manager pass: $1 ready task(s), assessing objectives and refilling the queue" | tee -a "$LOG"
  Q busy "manager pass: assessing the app against the objectives and filing tasks"
  banner "**Go loop** manager pass: assessing the app against the objectives and filing the next tasks"
  state busy
  touch "$MANAGER_STAMP"
  run_runner "$(cat queue/bin/manager-prompt.md)"
  local rc=$?
  record_exit - "$rc"
  echo "[go-loop] $(date +%T) manager pass exited $rc, $(Q ready) task(s) now ready" | tee -a "$LOG"
  Q event manager_pass "{\"exit\":$rc,\"ready\":$(Q ready)}"
}

# Keep the user's app on what the loop just landed. After a task pushes changes
# under Sources/ or the package manifest, the dev bundle is rebuilt and put back
# the way it was found (running or not). Asked for on 2026-09-02: they were
# reviewing a build that was hours behind the fixes they had asked for.
AUTO_REFRESH="${PHOTONZ_AUTO_REFRESH:-1}"
refresh_dev_app() { # $1 = git rev before the task ran
  (( SANDBOX == 0 )) || return 0
  (( AUTO_REFRESH )) || return 0
  local before=$1 after
  after=$(git rev-parse HEAD 2>/dev/null) || return 0
  [[ "$before" == "$after" ]] && return 0
  git diff --name-only "$before" "$after" -- Sources Package.swift Package.resolved 2>/dev/null | grep -q . || return 0
  echo "[go-loop] $(date +%T) app code landed, refreshing the dev app" | tee -a "$LOG"
  Q note "rebuilding your dev app on the change that just landed"
  banner "**Go loop** rebuilding your dev app on the change that just landed"
  queue/bin/refresh-dev-app.sh >> "$LOG" 2>&1 \
    || echo "[go-loop] $(date +%T) dev app refresh failed; see the log" | tee -a "$LOG"
}

# The full walk sweep, run BETWEEN tasks. A runner cannot run it: 322 walks is
# about 52 minutes and a runner's background work is terminated at 600s, which
# is how eight of the twenty recorded runner failures happened (2026-09-07
# 16:22 and 2026-09-08 00:03 among them). So a runner asks with
# `queue/bin/sweep.sh request`, and the loop does the waiting here, in its own
# shell, with no task claimed and nothing else touching the probe app.
sweep_pass() {
  (( SANDBOX == 0 )) || return 0
  queue/bin/sweep.sh due || return 0
  echo "[go-loop] $(date +%T) walk sweep requested; running it before the next task" | tee -a "$LOG"
  Q busy "running the full walk sweep before the next task"
  banner "**Go loop** running the full walk sweep (about 50 minutes). No task is claimed while it runs."
  state busy
  queue/bin/sweep.sh run 2>&1 | tee -a "$LOG"
  Q event sweep_pass "$(queue/bin/sweep.sh summary 2>/dev/null || echo '{}')"
}

# ---- adopting a fix to this file -------------------------------------------
# zsh parses a script once, at start, so every later edit to this file is
# invisible to the process already running it. That is not a theoretical
# problem: the loop ran unbroken from 5 September, the walk sweep landed in
# here on the 8th, and by the 9th seven runners had asked for a sweep that the
# running loop had no code to serve. Nothing anywhere said why.
#
# So between tasks, with nothing claimed and nothing in flight, the loop
# compares the file on disk against the copy it started with and re-execs
# itself onto the new one. exec keeps the same pid, so status.json, the
# double-start guard and the Ghoztty window all carry over untouched, and the
# pass count rides across in the environment so PHOTONZ_MAX_ITERS still ends a
# drill.
#
# Only THIS file can go stale. The prompts are read with cat every pass, and
# queue.mjs, sweep.sh and refresh-dev-app.sh are fresh processes every time
# they are called, so they are always current already.
LOOP_RELOAD="${PHOTONZ_LOOP_RELOAD:-1}"
script_hash() { shasum -a 256 "$SCRIPT" 2>/dev/null | cut -d" " -f1; }
LOOP_SCRIPT_HASH=$(script_hash)
LOOP_SCRIPT_REFUSED=""   # hash of a copy that did not parse, so we say so once
reload_if_changed() {
  (( LOOP_RELOAD )) || return 0
  local fresh; fresh=$(script_hash)
  [[ -n "$fresh" && "$fresh" != "$LOOP_SCRIPT_HASH" ]] || return 0
  # Never exec a copy that does not parse or cannot be run: a half-written
  # script, or one that lost its executable bit, would end the loop on the spot
  # and the only symptom would be silence. exec failing is not recoverable, so
  # the check comes first. Keep running the copy we have, say so, and try again
  # when it changes.
  if [[ ! -x "$SCRIPT" ]] || ! zsh -n "$SCRIPT" 2>/tmp/goloop-parse.$$; then
    if [[ "$fresh" != "$LOOP_SCRIPT_REFUSED" ]]; then
      LOOP_SCRIPT_REFUSED="$fresh"
      echo "[go-loop] $(date +%T) go-loop.sh changed but does not parse; still running the copy from startup. $(head -c 300 /tmp/goloop-parse.$$)" | tee -a "$LOG"
      Q event loop_reload_refused "{\"reason\":\"parse error\"}"
      Q script "$LOOP_SCRIPT_HASH" broken "$SCRIPT"
    fi
    rm -f /tmp/goloop-parse.$$
    return 0
  fi
  rm -f /tmp/goloop-parse.$$
  echo "[go-loop] $(date +%T) go-loop.sh changed; restarting onto it (same pid $$, no task claimed)" | tee -a "$LOG"
  Q event loop_reloaded "{\"from\":\"${LOOP_SCRIPT_HASH:0:12}\",\"to\":\"${fresh:0:12}\"}"
  Q busy "restarting onto the updated loop script"
  export PHOTONZ_LOOP_ITERS=$ITERS
  exec "$SCRIPT"
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

echo "[go-loop] started pid=$$ repo=$REPO queue=$QDIR model=$RUNNER_MODEL effort=$RUNNER_EFFORT" | tee -a "$LOG"
Q event loop_started "{\"pid\":$$}"
# Tell the queue which copy of this script is running. The dashboard hashes the
# file itself and says plainly when the loop is on an older one, which covers
# the window this reload check cannot: the twenty minutes the loop spends
# inside a task, and any copy it has refused.
Q script "$LOOP_SCRIPT_HASH" running "$SCRIPT"
Q reset-health
Q busy "starting up"

# Wait out a runner failure. $1 = seconds, $2 = consecutive failures, $3 = last
# error. The banner says unhealthy for the whole wait so the window never reads
# as working when nothing is working.
backoff_wait() {
  local secs=$1 fails=$2 err=$3
  if [[ "${SIGNIN:-0}" == 1 ]]; then
    # Not a runner failure in any useful sense: nothing runs until a person
    # logs in, so the window says exactly that and what to do about it.
    echo "[go-loop] $(date +%T) sign-in needed: the agent could not authenticate ($fails attempt(s)). Run \`claude\` in a terminal and log in; retrying in ${secs}s. Last error: $err" | tee -a "$LOG"
    banner "**Go loop needs sign-in** the agent could not authenticate. Run \`claude\` in a terminal and log in; the loop retries in ${secs}s and resumes on its own."
    title "photonz: go-loop (sign-in needed)"
  elif [[ "${REASON:-}" == spend ]]; then
    # The agent refused for spend: nothing runs until the limit resets (the
    # message says when) or someone raises it, so say that, not "unhealthy".
    echo "[go-loop] $(date +%T) spend limit hit: the agent refused to run ($fails attempt(s)). Wait for the reset it names or raise the limit; retrying in ${secs}s. Last error: $err" | tee -a "$LOG"
    banner "**Go loop hit the spend limit** the agent refused to run. Wait for the reset it names or raise the limit; the loop retries in ${secs}s and resumes on its own. $err"
    title "photonz: go-loop (spend limit)"
  else
    echo "[go-loop] $(date +%T) unhealthy: $fails consecutive runner failures; waiting ${secs}s. Last error: $err" | tee -a "$LOG"
    banner "**Go loop unhealthy** $fails runner failures in a row, retrying in ${secs}s. Last error: $err"
    title "photonz: go-loop (unhealthy)"
  fi
  state idle
  sleep "$secs"
  title "photonz: go-loop"
}
DIGEST_HOUR="${PHOTONZ_DIGEST_HOUR:-5}"

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

# Passes already made before a reload, so a drill's PHOTONZ_MAX_ITERS still
# counts the whole run and not just the part after the last restart.
ITERS=${PHOTONZ_LOOP_ITERS:-0}
unset PHOTONZ_LOOP_ITERS
while :; do
  TODAY=$(date +%F)
  ITERS=$((ITERS + 1))
  rotate_log
  [[ "$MAX_ITERS" != 0 && $ITERS -gt $MAX_ITERS ]] && { echo "[go-loop] reached PHOTONZ_MAX_ITERS=$MAX_ITERS, exiting" | tee -a "$LOG"; cleanup; }

  # A fix to this file, landed by the runner of the last task, is adopted here
  # and nowhere else: no task is claimed and no sweep is running yet.
  reload_if_changed

  # A sweep a runner asked for is served here, between tasks, before anything
  # else in the pass claims work.
  sweep_pass

  # Daily digest + triage: once per calendar day, at or after 05:00 so it reads
  # as a morning report rather than a midnight one. (10# forces base-10: date
  # prints 08/09 and zsh arithmetic would otherwise read those as bad octal.)
  if [[ ! -f "$QDIR/digests/$TODAY.md" && $((10#$(date +%H))) -ge $DIGEST_HOUR ]]; then
    echo "[go-loop] $(date +%T) generating digest + triage for $TODAY" | tee -a "$LOG"
    Q busy "running daily digest + triage"
    banner "**Go loop** running daily digest + triage for $TODAY"
    state busy
    run_runner "$(cat queue/bin/digest-prompt.md)"
    DIGEST_EXIT=$?
    record_exit - "$DIGEST_EXIT"
    if [[ -n "$REASON" ]]; then
      # The runner refused to start (no sign-in, or the spend limit), so leave
      # no stub behind: with the file still missing, the digest is the first
      # thing retried on every pass, and the day gets a real one as soon as
      # the refusal clears.
      echo "[go-loop] $(date +%T) digest for $TODAY deferred: $REASON ($RUNNER_ERR)" | tee -a "$LOG"
      Q event digest_deferred "{\"reason\":\"$REASON\"}"
    # If the digest still does not exist, write a stub so we do not spin on it.
    elif [[ ! -f "$QDIR/digests/$TODAY.md" ]]; then
      printf '# Daily digest %s\n\n## Summary\nDigest generation failed; see %s.\n\n## Reflections\n(none)\n\n## Triage review\n(skipped)\n' "$TODAY" "$LOG" > "$QDIR/digests/$TODAY.md"
      Q event digest_failed "{}"
    fi
    if [[ "$OUTCOME" != "ok" ]]; then
      backoff_wait "$BACKOFF" "$FAILURES" "$RUNNER_ERR"
      continue
    fi
  fi

  # Refill before the queue runs dry: when few tasks are ready, the manager
  # pass files the next batch (bounded by a cooldown so an empty pass cannot
  # spin). A failed pass backs off like any other runner failure.
  READY=$(Q ready)
  if manager_due "$READY"; then
    manager_pass "$READY"
    if [[ "$OUTCOME" != "ok" ]]; then
      backoff_wait "$BACKOFF" "$FAILURES" "$RUNNER_ERR"
      continue
    fi
  fi

  # Claim the next ready task.
  TASK_FILE=$(Q next)
  if [[ "$TASK_FILE" == "none" ]]; then
    Q idle
    banner "**Go loop** idle, no ready tasks; the manager pass runs again in a few minutes. Or queue one from the dashboard."
    state idle
    sleep 60
    continue
  fi

  REV_BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "")
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
  [[ $SANDBOX == 0 ]] && { git push -q origin main >> "$LOG" 2>&1 || true; }

  if [[ "$OUTCOME" == "ok" ]]; then
    [[ -n "$REV_BEFORE" ]] && refresh_dev_app "$REV_BEFORE"
    Q note "between tasks"
    sleep 5
    continue
  fi

  [[ "$OUTCOME" == "parked" ]] && echo "[go-loop] $(date +%T) parked $TASK_ID after repeated runner failures" | tee -a "$LOG"
  backoff_wait "$BACKOFF" "$FAILURES" "$RUNNER_ERR"
done
