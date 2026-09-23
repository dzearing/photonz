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
#                         Default claude-opus-5-5: the user asked on 2026-09-23
#                         that the loop run on Opus 5.5 (was Opus 5 since
#                         2026-09-01) with high thinking.
#   PHOTONZ_RUNNER_EFFORT effort level for those runners. Default high.
#   PHOTONZ_AUTO_REFRESH  0 to stop the loop rebuilding and relaunching the
#                         user's dev app after a task lands app code. Default 1.
#   PHOTONZ_DIGEST_HOUR   earliest local hour for the daily digest. Default 5
#                         (drills set 0 so the digest pass runs whenever).
#   PHOTONZ_STALL_RENOTICE  seconds a stall on a refusal only a person can clear
#                         (spend limit, sign-in) must last before they are told
#                         a second time. Default 86400; drills set it low.
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
# Whether this process is a RELOAD of a loop that was already running, rather
# than a fresh start. Read here, before anything can unset it, and used by the
# startup block below to decide whether health is a fresh claim or a carried
# one. See the reset-health call for why that matters.
RESUMED=0; [[ -n "${PHOTONZ_LOOP_ITERS:-}" ]] && RESUMED=1
Q() { node queue/bin/queue.mjs "$@"; }
LOG="$QDIR/loop.log"
mkdir -p "$QDIR/digests" "$QDIR/leftovers"
# Where run_runner writes its picture of the working tree before a runner
# starts. See settle_leftovers and queue/bin/leftovers.mjs.
LEFTOVERS_BEFORE="$QDIR/leftovers/.before.json"
# stream-json + the formatter give this window a live feed of what each runner
# is doing (tool by tool), instead of dead air until a task ends.
RUNNER_MODEL="${PHOTONZ_RUNNER_MODEL:-claude-opus-5-5}"
RUNNER_EFFORT="${PHOTONZ_RUNNER_EFFORT:-high}"
CLAUDE_FLAGS=(--dangerously-skip-permissions --output-format stream-json --verbose
              --model "$RUNNER_MODEL" --effort "$RUNNER_EFFORT")
# Set by run_runner: the last non-blank line the runner complained with. This is
# what the dashboard shows when the loop goes unhealthy, so a wedged loop names
# its own cause ("Credit balance is too low") instead of just sitting there.
# RUNNER_REASON is the verdict that goes with it: signin, spend, or empty for a
# run nothing refused.
RUNNER_ERR=""
RUNNER_REASON=""
run_runner() { # $1 = prompt text; streams formatted output to the pane AND loop.log
  local errf outf rc
  errf=$(mktemp -t goloop-err) || return 1
  outf=$(mktemp -t goloop-out) || return 1
  # What the working tree already looked like. Whatever is dirty AFTER this
  # runner that was not dirty now is the runner's doing, and settle_leftovers
  # puts it away under the runner's name instead of leaving it for the next
  # task to commit. Taken here so every kind of runner is covered.
  node queue/bin/leftovers.mjs snapshot "$LEFTOVERS_BEFORE" >/dev/null 2>&1 || : > "$LEFTOVERS_BEFORE"
  claude -p "${CLAUDE_FLAGS[@]}" "$1" 2>"$errf" | node queue/bin/stream-format.mjs | tee -a "$LOG" "$outf"
  rc=${pipestatus[1]}
  cat "$errf" >> "$LOG"
  # The queue reads the whole run once: the telling line (a refusal wherever it
  # sits on stderr, else the last stderr line, else the last stdout line — some
  # failures, API errors mid-stream, only ever reach stdout) AND whether the CLI
  # itself refused. Judging that here, with the tool calls still in view, is what
  # keeps a runner that merely TALKS about the spend limit from being read as one
  # that hit it (2026-09-12: a healthy digest recorded as an environment failure).
  RUNNER_ERR=""; RUNNER_REASON=""
  eval "$(Q runner-classify "$errf" "$outf")"
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
  NOTIFY=0; STALLHOURS=0
  eval "$(Q runner-exit "$1" "$2" --reason "$RUNNER_REASON" "$RUNNER_ERR")"
}

# Leave the terminal window. Everything else the loop does about a refusal only
# a person can clear (the banner, the window title, the dashboard hero, the
# status note) is visible only to somebody already looking at it, and on
# 2026-09-09 nobody was: the loop sat on the spend limit for sixty two hours,
# 128 refusals apart, and two days of work never happened. This is the one
# thing that reaches somebody who is doing something else.
#
# The queue decides WHEN (NOTIFY, set by record_exit): once when the stall
# starts, once more per day it survives, never once per retry. This decides
# WHAT IT SAYS, and it has one job, which is to name the one action that ends
# the stall.
notify_person() { # $1 = reason (signin|spend), $2 = whole hours stalled so far
  local title body hours=${2:-0}
  case "$1" in
    spend)
      title="Photonz build loop has stopped"
      body="Spend limit reached, so nothing is building. Raise it at claude.ai/settings/usage, or wait for the reset. It resumes on its own." ;;
    signin)
      title="Photonz build loop has stopped"
      body="Sign-in needed, so nothing is building. Run claude in a terminal and log in. It resumes on its own." ;;
    *) return 0 ;;
  esac
  (( hours > 0 )) && body="Still stopped ${hours}h later. $body"
  # A notification banner shows two or three lines and cuts the rest, so the
  # wording above puts what is wrong and where to go in the first sentence.
  # argv, not string interpolation: the refusal text and the limit URL travel
  # as data so nothing in them can be read as AppleScript.
  if osascript -e 'on run argv' \
               -e 'display notification (item 1 of argv) with title (item 2 of argv) sound name "Basso"' \
               -e 'end run' -- "$body" "$title" >/dev/null 2>&1; then
    echo "[go-loop] $(date +%T) notified you: $title. $body" | tee -a "$LOG"
    Q event stall_notified "{\"reason\":\"$1\",\"hours\":$hours}"
  else
    # Notifications can be switched off for the terminal, and there is nothing
    # the loop can do about that except say so where it can be read later.
    echo "[go-loop] $(date +%T) could not raise a notification; the stall is only visible here and on the dashboard." | tee -a "$LOG"
    Q event stall_notify_failed "{\"reason\":\"$1\",\"hours\":$hours}"
  fi
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
# What the objectives looked like when a pass last finished reading them. The
# trigger is "the objectives say something the manager has not acted on yet",
# and that is a question about CONTENT, not about mtime: the manager restages
# epics itself, so its own edit always leaves the file newer than the stamp it
# wrote on the way in, and an mtime test reads the pass's own work as the user
# having spoken. On 2026-09-13 that ran two passes in half an hour with sixty
# nine tasks ready, each one costing a runner slot and filing more tasks onto
# an already overfull queue.
#
# The one case this narrows: somebody editing the objectives WHILE a pass runs
# has their edit recorded as seen by a pass that never read it. That costs them
# the immediate trigger, not the change, since the low water mark comes round
# anyway and an intake edit files its own task. Telling the two writers apart
# needs provenance the file does not carry, and a hand edit records no event to
# read it from, so the narrow version is the honest one.
MANAGER_SEEN="$QDIR/manager/.objectives-seen"
mkdir -p "$QDIR/manager"
objectives_hash() { shasum -a 256 "$QDIR/objectives.json" 2>/dev/null | cut -d" " -f1; }
# A loop upgrading onto this fix has a stamp but no record of what it has seen.
# Treat the objectives it already ran against as seen: the pass that wrote that
# stamp read them. The cost if we are wrong is one missed trigger, which the
# low water mark catches anyway; the cost the other way is exactly the spurious
# pass this is here to stop.
[[ -f "$MANAGER_STAMP" && ! -f "$MANAGER_SEEN" ]] && objectives_hash > "$MANAGER_SEEN"
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
  local now changed=0
  now=$(objectives_hash)
  [[ -n "$now" && "$now" != "$(cat "$MANAGER_SEEN" 2>/dev/null)" ]] && changed=1
  (( changed )) || (( $1 < MANAGER_LOW_WATER )) || return 1
  (( $(date +%s) - last >= MANAGER_COOLDOWN ))
}
manager_pass() { # $1 = ready task count (for the log)
  echo "[go-loop] $(date +%T) manager pass: $1 ready task(s), assessing objectives and refilling the queue" | tee -a "$LOG"
  Q busy "manager pass: assessing the app against the objectives and filing tasks"
  banner "**Go loop** manager pass: assessing the app against the objectives and filing the next tasks"
  state busy
  touch "$MANAGER_STAMP"
  run_runner "$(cat queue/bin/manager-prompt.md; echo; cat queue/bin/follow-up-bar.md)"
  local rc=$?
  record_exit - "$rc"
  settle_leftovers manager - "$OUTCOME" "the manager pass"
  # The objectives as they stand now are what this pass acted on, its own
  # restaging included, so the next check starts from here and the pass cannot
  # wake itself up. Only a pass that actually ran gets to say so: a runner that
  # died on sign-in or spend read nothing, and the edit that called it must
  # still be waiting when the loop retries.
  [[ "$OUTCOME" == "ok" ]] && objectives_hash > "$MANAGER_SEEN"
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

# Kill anything a runner left spinning on the user's machine. A runner testing
# the perf gate once spawned ten CPU burners on purpose and cleaned up with
# `kill $(jobs -p)`, which is empty in a non-interactive shell: ten cores were
# pegged for 41 hours until the user noticed and asked us never to leave the
# machine like that. The runner prompt now forbids it, and this is the part that
# does not rely on a runner reading anything. See queue/bin/reap-runaways.sh for
# the tests it applies; a live Bash call never matches one.
reap_runaways() {
  [[ -x queue/bin/reap-runaways.sh ]] || return 0
  local out
  out=$(queue/bin/reap-runaways.sh 2>/dev/null) || return 0
  [[ -n "$out" ]] && echo "[go-loop] $(date +%T) $out" | tee -a "$LOG"
  return 0
}

# Put away what a runner walked out on. A task that runs out of its turn stops
# without committing, and its changed files used to stay in the tree for the
# next task to pick up and commit under its own name (2026-09-16, 05:18: seven
# files from separate-finds-the-boxes-in-a-dark-window-too-no, with nothing
# anywhere saying so). Now the loop names them, stashes them under the task
# that made them, and hands them back to that task the next time it is claimed.
# The queue's own files are never touched: no task owns them.
settle_leftovers() { # $1 = kind (task|digest|manager), $2 = task id or "-", $3 = outcome, $4 = label
  local out
  out=$(node queue/bin/leftovers.mjs settle "$LEFTOVERS_BEFORE" "$1" "$2" "$3" "${4:-}" 2>&1) || true
  [[ -z "$out" ]] && return 0
  echo "[go-loop] $(date +%T) $out" | tee -a "$LOG"
  banner "**Go loop** $out"
  return 0
}

# ---- holding the Mac awake for as long as the loop is working --------------
#
# The user answered a card on 2026-09-20 asking whether the loop should stop
# their Mac locking itself while it works, and chose to keep it awake. What
# already existed was much narrower than that: Scripts/playtest-all.sh holds the
# Mac for the length of ONE SWEEP and lets go the moment it ends. The loop
# spends most of its life outside a sweep, and thirty one minutes after that
# answer the Mac locked itself in a gap between two of them (11:03:19 local,
# with sweeps at 12:23, 14:02, 15:46, 17:47 and 18:58 UTC and gaps of thirty to
# seventy minutes between them). It stayed locked, which cost 163 of 544 walks
# on every sweep after it and put a caveat on every picture in every audit the
# user was asked to read. So the hold belongs to the LOOP, for its whole life,
# gaps included.
#
# -d -i holds off display sleep and idle sleep, which is what the screen saver
# and the lock behind it hang off. Deliberately NOT -u: that posts user
# activity, which would light a display somebody has already put to sleep, at
# whatever hour the loop reaches this. So this keeps an awake Mac awake and does
# nothing at all to a sleeping one. It is a power assertion rather than a
# process doing work, and it can neither wake a display nor unlock a screen.
#
# -w $$ is what makes it safe to hold for days rather than for an hour. The
# assertion is released when THIS PID exits, whatever ended it: the trap below
# covers a clean stop, and a SIGKILL, which runs no trap at all, is covered by
# caffeinate itself noticing the pid go. That is the opposite trade from the
# sweep's hold, which has to outlive a SIGKILL to its parent long enough to be
# put down by pid, and bounds itself with -t instead.
#
# The pid is written down for two reasons: so a sweep can see there is already a
# hold and not stack a second one on top of it, and so that anything putting
# this hold down does it BY PID. Never pkill caffeinate: a hold the user started
# by hand looks exactly like ours to a pattern.
AWAKE_PIDFILE="$QDIR/.loop-awake.pid"
export PHOTONZ_LOOP_AWAKE_PIDFILE="$AWAKE_PIDFILE"
AWAKE=""
# Set only for the reload below, where the process is replaced but the pid, and
# so the hold watching it, carry straight across.
RELOADING=0

# Is the Mac's screen locked right now? Nothing here ever tries to change that:
# a Mac already locked stays locked until a person logs in.
screen_locked() {
  ioreg -n Root -d1 -a 2>/dev/null | grep -A1 CGSSessionScreenIsLocked | grep -q "<true/>"
}

# True when $1 is a live caffeinate. This is the pid-reuse guard: a pid we wrote
# down minutes ago may belong to something else entirely by now, and killing
# that would be worse than leaving a hold behind.
is_a_live_hold() {
  [[ -n "${1:-}" ]] || return 1
  ps -o command= -p "$1" 2>/dev/null | grep -q caffeinate
}

hold_awake() {
  command -v caffeinate >/dev/null 2>&1 || return 0
  # A reload exec's onto an edited copy of this script with the SAME pid, so the
  # hold taken before the reload is still alive and still watching the right
  # process. Adopt it instead of stacking a second one that nothing would then
  # release until the loop stopped.
  # ...and it must be OUR hold, not merely a live caffeinate wearing the pid we
  # wrote down. A loop that was SIGKILLed leaves the pidfile behind (its hold
  # went with it, but nothing ran to tidy the note), and a pid that comes round
  # again on a machine where the user runs caffeinate by hand would otherwise be
  # adopted here and killed when this loop stops. The hold is a direct child of
  # this pid and stays one across the exec, so the parent is the whole test.
  if [[ -s "$AWAKE_PIDFILE" ]]; then
    local had; had=$(cat "$AWAKE_PIDFILE" 2>/dev/null)
    if is_a_live_hold "$had" && [[ "$(ps -o ppid= -p "$had" 2>/dev/null | tr -d ' ')" == "$$" ]]; then
      AWAKE="$had"; return 0
    fi
  fi
  caffeinate -d -i -w $$ &
  AWAKE=$!
  echo "$AWAKE" > "$AWAKE_PIDFILE"
  return 0
}

release_awake() {
  (( RELOADING )) && return 0
  local pid="$AWAKE"
  AWAKE=""
  rm -f "$AWAKE_PIDFILE"
  is_a_live_hold "$pid" || return 0
  kill "$pid" 2>/dev/null
  return 0
}

# Say what the hold bought, in the one place where the honest version matters.
# A hold stops the NEXT lock and does nothing whatever to a lock already in
# place, so a loop starting on a locked screen must not read as having fixed it.
say_about_the_hold() {
  if [[ -z "$AWAKE" ]]; then
    echo "[go-loop] no caffeinate on this machine, so nothing here stops the screen locking while the loop works." | tee -a "$LOG"
    Q event loop_awake "{\"held\":false,\"why\":\"no caffeinate\"}"
    return 0
  fi
  if screen_locked; then
    echo "[go-loop] holding the Mac awake for as long as this loop runs (caffeinate pid $AWAKE). The screen is ALREADY LOCKED and this does not unlock it: only a person logging in can. It stops the NEXT lock, so once somebody does, the screen stays up." | tee -a "$LOG"
    Q event loop_awake "{\"held\":true,\"pid\":$AWAKE,\"screenLocked\":true}"
  else
    echo "[go-loop] holding the Mac awake for as long as this loop runs (caffeinate pid $AWAKE), gaps between sweeps included." | tee -a "$LOG"
    Q event loop_awake "{\"held\":true,\"pid\":$AWAKE,\"screenLocked\":false}"
  fi
}

# The walk checks, run BETWEEN tasks. A runner cannot run the whole set: it is
# about 560 walks and about 105 minutes (queue/bin/sweep-size.mjs counts it, so
# this comment cannot go stale on its own) and a runner's background work is
# terminated at 600s, which
# is how eight of the twenty recorded runner failures happened (2026-09-07
# 16:22 and 2026-09-08 00:03 among them). So a runner asks with
# `queue/bin/sweep.sh request`, and the loop does the waiting here, in its own
# shell, with no task claimed and nothing else touching the probe app.
#
# ASKING IS NOT STARTING. Runners ask after every task, and until 2026-09-21
# every ask started a whole-set run: thirteen of them in twenty four hours,
# 835 minutes of a 1440 minute day, 58 per cent of the loop's wall clock
# (queue/bin/loop-day.mjs --hours 24). The schedule now decides
# (queue/bin/sweep-schedule.mjs): the full set at most once every twelve hours,
# and a ten minute ROTATING CHECK in between, so a regression is still caught
# the day it lands.
sweep_pass() {
  (( SANDBOX == 0 )) || return 0
  local full part what
  if queue/bin/sweep.sh due; then
    # With the screen locked only the walks that never ask for a control by name
    # can run, which is about half the set. Say which of the two is happening,
    # because one of them leaves most of the set unchecked.
    # How long to say it takes, worked out from this machine's own recorded
    # sweeps (queue/bin/sweep-size.mjs) rather than written down here.
    full=$(queue/bin/sweep-size.mjs --minutes 2>/dev/null || echo 105)
    part=$(queue/bin/sweep-size.mjs --partial-minutes 2>/dev/null || echo 55)
    what="the full walk sweep (about $full minutes)"
    if screen_locked; then
      what="the part of the walk sweep a locked screen cannot touch (about $part minutes)"
    fi
    # Say WHY, in the same sentence the rotating check prints. A full sweep is
    # two hours, and until 2026-09-22 this line said only "due", so a sweep
    # that fired on a collapsed floor looked exactly like one that fired on a
    # full twelve hours. It took two runner passes to find that the 01:30 sweep
    # of 2026-09-22 ran twenty two minutes after a check had said "6.4h"; the
    # reason was in the decision the whole time and nothing printed it.
    echo "[go-loop] $(date +%T) walk sweep due ($(queue/bin/sweep.sh why)); running $what before the next task" | tee -a "$LOG"
    Q busy "running $what before the next task"
    banner "**Go loop** running $what. No task is claimed while it runs."
    state busy
    queue/bin/sweep.sh run 2>&1 | tee -a "$LOG"
    Q event sweep_pass "$(queue/bin/sweep.sh summary 2>/dev/null || echo '{}')"
    return 0
  fi

  # Inside the twelve hour floor, the rotating check instead: about ten minutes
  # of walks, every one whose script changed plus the next chunk of the set.
  # This is what keeps a floor from being a trade of safety for speed.
  if queue/bin/sweep.sh slice-due; then
    echo "[go-loop] $(date +%T) rotating walk check before the next task ($(queue/bin/sweep.sh why-not))" | tee -a "$LOG"
    Q busy "running a rotating walk check (about 10 minutes) before the next task"
    banner "**Go loop** running a rotating walk check, about 10 minutes. No task is claimed while it runs."
    state busy
    queue/bin/sweep.sh slice 2>&1 | tee -a "$LOG"
    Q event slice_pass "$(queue/bin/sweep.sh slice-summary 2>/dev/null || echo '{}')"
    return 0
  fi
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
  # The hold on the Mac rides across untouched: caffeinate is watching this pid,
  # and exec keeps it. RELOADING stops the EXIT trap putting it down on the way
  # out, and the copy we exec onto adopts it from the pidfile rather than
  # stacking a second one.
  RELOADING=1
  exec "$SCRIPT"
}

banner() { printf '\033]7778;%s\007' "$1"; }   # sticky Ghoztty pane banner
state()  { printf '\033]7777;%s\007' "$1"; }   # Ghoztty activity state
title()  { printf '\033]2;%s\007' "$1"; }      # window title

# Everything above this line is definitions; everything below starts a loop.
# queue/bin/manager-due-drill.sh sources this file for the real manager_due and
# manager_pass rather than a copy of them, which is how the 2026-09-13
# self-waking manager pass survived review in the first place.
[[ -n "${PHOTONZ_GO_LOOP_DEFS_ONLY:-}" ]] && return 0

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
  release_awake
  Q stopped
  banner "**Go loop stopped**"
  state idle
  title "photonz: go-loop (stopped)"
  exit 0
}
trap cleanup INT TERM
# ...and for every other way this process can end, including one nobody wrote a
# handler for. release_awake is idempotent, so cleanup calling it first and this
# firing on the exit underneath costs nothing.
trap release_awake EXIT
title "photonz: go-loop"

# Take the hold now, before the first pass: the gaps this exists to cover start
# at startup, not at the first sweep.
hold_awake

echo "[go-loop] started pid=$$ repo=$REPO queue=$QDIR model=$RUNNER_MODEL effort=$RUNNER_EFFORT" | tee -a "$LOG"
Q event loop_started "{\"pid\":$$}"
say_about_the_hold
# Tell the queue which copy of this script is running. The dashboard hashes the
# file itself and says plainly when the loop is on an older one, which covers
# the window this reload check cannot: the twenty minutes the loop spends
# inside a task, and any copy it has refused.
Q script "$LOOP_SCRIPT_HASH" running "$SCRIPT"
# A START is a fresh claim about health; a RELOAD is not. The loop exec's itself
# onto an edited copy of this script between tasks, same pid, same queue, same
# run, and the pass count rides across in PHOTONZ_LOOP_ITERS. Health has to ride
# across with it. It did not until 2026-09-17, so a fix landing while the loop
# was stuck made it forget it was stuck: the consecutive failure count went back
# to zero (so the growing retry wait started again at the shortest step), the
# failure streak across tasks went with it (so the next failures were no longer
# blamed on the environment), and a task parked earlier in that same streak was
# never handed back. Exactly the wrong moment to forget: somebody is landing
# fixes precisely because the loop is failing.
if (( RESUMED )); then
  echo "[go-loop] carrying health across the restart (pass $PHOTONZ_LOOP_ITERS)" | tee -a "$LOG"
else
  Q reset-health
fi
Q busy "starting up"

# Wait out a runner failure. $1 = seconds, $2 = consecutive failures, $3 = last
# error. The banner says unhealthy for the whole wait so the window never reads
# as working when nothing is working.
backoff_wait() {
  local secs=$1 fails=$2 err=$3
  # Before the window is dressed for a person who is here, tell the one who is
  # not. Only a refusal nothing but a person can clear qualifies, and only the
  # first one of a stall (or the first of a new day inside it).
  (( ${NOTIFY:-0} )) && notify_person "${REASON:-}" "${STALLHOURS:-0}"
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
    run_runner "$(cat queue/bin/digest-prompt.md; echo; cat queue/bin/follow-up-bar.md)"
    DIGEST_EXIT=$?
    record_exit - "$DIGEST_EXIT"
    settle_leftovers digest - "$OUTCOME" "the daily digest pass"
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

  run_runner "$(cat queue/bin/runner-prompt.md; echo; cat queue/bin/follow-up-bar.md)

TASK FILE: $TASK_FILE"
  EXIT=$?
  echo "[go-loop] $(date +%T) task $TASK_ID runner exited $EXIT" | tee -a "$LOG"

  # A runner MUST finalize its task. One that did not is a failure, not a free
  # retry: recorded with its exit code and last error, retried more slowly each
  # time, and after three straight failures of the same task, parked.
  record_exit "$TASK_ID" "$EXIT"
  # Blunt safety net for anything the line above did not cover.
  Q guard >> "$LOG" 2>&1
  # ...and this catches anything it left CHANGED. Before the next task is
  # claimed, so that task starts from a tree it owns.
  settle_leftovers task "$TASK_ID" "$OUTCOME" "$TASK_TITLE"
  # Runners push their own commits; this catches anything they left behind.
  [[ $SANDBOX == 0 ]] && { git push -q origin main >> "$LOG" 2>&1 || true; }

  # ...and this catches anything they left RUNNING. Unconditional: a runner that
  # failed or was killed is likelier to have leaked a process than one that
  # finished cleanly.
  reap_runaways

  if [[ "$OUTCOME" == "ok" ]]; then
    [[ -n "$REV_BEFORE" ]] && refresh_dev_app "$REV_BEFORE"
    Q note "between tasks"
    sleep 5
    continue
  fi

  [[ "$OUTCOME" == "parked" ]] && echo "[go-loop] $(date +%T) parked $TASK_ID after repeated runner failures" | tee -a "$LOG"
  backoff_wait "$BACKOFF" "$FAILURES" "$RUNNER_ERR"
done
