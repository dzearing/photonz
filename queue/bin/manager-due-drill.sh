#!/bin/zsh
# Manager-pass trigger drill: prove a manager pass cannot wake itself up again.
#
#   queue/bin/manager-due-drill.sh
#
# The manager pass is supposed to run on two triggers and no others: the queue
# has run low, or somebody changed what the app is for. On 2026-09-13 it ran
# twice inside half an hour with sixty nine tasks ready, because the pass has
# staging authority over queue/objectives.json, so its OWN edit looked to the
# next check like the objectives having changed. Every spurious pass costs a
# runner slot and files more tasks onto an already overfull queue.
#
# This drill sources the real go-loop.sh for its real manager_due/manager_pass
# (PHOTONZ_GO_LOOP_DEFS_ONLY, so nothing below the definitions runs) and drives
# them in a throwaway queue with a stub runner. It is zsh because the loop is.
#
#   1. the very first check, with no pass ever run, is due
#   2. a pass that restages an epic itself does not make the next check due
#   3. an edit by anyone else still makes the next check due
#   4. a full queue with nothing changed is not due
#   5. a queue below the low water mark is due, changed or not
#   6. a rewrite that leaves the objectives identical is not due
#   7. a pass whose runner failed does not swallow the edit that triggered it
#   8. the recorded timestamps of the 2026-09-13 pass, and it does not fire
#   9. that whole day replayed in order: the two right passes run, the two
#      spurious ones do not
#
# Nothing here touches the real queue.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

SANDBOX_DIR=$(mktemp -d -t photonz-mgr-drill)
trap 'rm -rf "$SANDBOX_DIR"' EXIT
QUEUE="$SANDBOX_DIR/queue"
mkdir -p "$QUEUE/manager"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); print -r -- "  ok   $1"; }
bad()  { FAIL=$((FAIL+1)); print -r -- "  FAIL $1"; }
check_due()     { if manager_due "$1"; then ok "$2"; else bad "$2 (expected due, got not due)"; fi }
check_not_due() { if manager_due "$1"; then bad "$3 (expected NOT due, got due)"; else ok "$3"; fi }

objectives() { print -r -- "$QUEUE/objectives.json"; }
write_objectives() { # $1 = focus, $2 = stage for the first epic
  cat > "$(objectives)" <<JSON
{ "updated": "2026-09-13T00:00:00.000Z", "focus": "$1", "principles": [],
  "epics": [ { "id": "ui-building", "title": "Build UI", "stage": "$2", "children": [] } ] }
JSON
}
write_objectives ui-building now

# The loop refuses a manager pass in a sandbox queue (SANDBOX=1) precisely so a
# drill cannot file real tasks. We want the real gate, not that guard, so the
# queue is pointed at the sandbox and SANDBOX is put back to 0 afterwards.
export PHOTONZ_QUEUE_DIR="$QUEUE"
export PHOTONZ_GO_LOOP_DEFS_ONLY=1
export PHOTONZ_MANAGER_LOW_WATER=3
export PHOTONZ_MANAGER_COOLDOWN=1200
source queue/bin/go-loop.sh || { print -r -- "could not source go-loop.sh for its definitions"; exit 1 }
SANDBOX=0

# ---- stubs: everything a pass touches except the manager bookkeeping --------
RUNNER_RC=0            # what the stub runner exits with
RUNNER_EDITS=""        # non-empty: the pass restages an epic, like a real one
Q() { # only the handful of queue calls a manager pass makes
  case "$1" in
    ready) print -r -- "$STUB_READY" ;;
    runner-exit)
      if [[ "$3" == 0 ]]; then
        print -r -- 'OUTCOME=ok; BACKOFF=0; FAILURES=0; HEALTH=healthy; ENVFAIL=0; SIGNIN=0; REASON=""'
      else
        print -r -- 'OUTCOME=failed; BACKOFF=60; FAILURES=1; HEALTH=unhealthy; ENVFAIL=0; SIGNIN=0; REASON=""'
      fi ;;
    *) : ;;
  esac
}
banner() { : }
state()  { : }
run_runner() {
  # A real pass takes minutes, and its stamp is written before the agent starts,
  # so anything the pass edits lands after its own stamp: that gap is the whole
  # bug. Age the stamp by the three minutes the 2026-09-13 log recorded between
  # the pass starting and the epics it restaged.
  local m; m=$(stat -f %m "$MANAGER_STAMP" 2>/dev/null) \
    && touch -t "$(date -r $((m - 180)) +%Y%m%d%H%M.%S)" "$MANAGER_STAMP"
  [[ -n "$RUNNER_EDITS" ]] && write_objectives ui-building "$RUNNER_EDITS"
  return $RUNNER_RC
}
STUB_READY=69
run_pass() { # $1 = stage the pass restages to (empty: it changes nothing), $2 = runner exit
  RUNNER_EDITS="${1:-}"; RUNNER_RC="${2:-0}"
  manager_pass "$STUB_READY" >/dev/null 2>&1
  RUNNER_EDITS=""; RUNNER_RC=0
}
# Twenty minutes pass. The loop gets there by the clock moving forward, so the
# drill moves every timestamp back by the same amount instead of back-dating
# one stamp: shifting them together keeps their order, and a drill that
# back-dates a single file ends up testing the drill.
time_passes() { # $1 = seconds
  local f m
  for f in "$(objectives)" "$QUEUE"/manager/.*(.N); do
    m=$(stat -f %m "$f" 2>/dev/null) || continue
    touch -t "$(date -r $((m - $1)) +%Y%m%d%H%M.%S)" "$f"
  done
}
cooldown_elapsed() { time_passes 1800 }

print -r -- "manager-due drill: $QUEUE"

# 1. nothing has ever run: the first check is due whatever the queue holds
[[ -f "$MANAGER_STAMP" ]] && rm -f "$MANAGER_STAMP"
check_due 69 "1. the first check ever, with a full queue, is due"

# 2. THE BUG: a pass restages an epic, and that must not wake the next one
run_pass later 0
cooldown_elapsed
check_not_due 69 x "2. a pass that restaged an epic does not make the next check due"

# 3. but somebody else editing the objectives still does
write_objectives icon-svg later
check_due 69 "3. an edit by a person or a task is still due at once"

# 4. that edit gets served by a pass, and the queue goes quiet again
cooldown_elapsed                         # the edit sits until the next pass is allowed
run_pass "" 0
cooldown_elapsed
check_not_due 69 x "4. a full queue with nothing changed is not due"

# 5. the other trigger still works: the queue running low
check_due 2 "5. a queue below the low water mark is due"

# 6. a rewrite that changes nothing is not a change
write_objectives icon-svg later
check_not_due 69 x "6. rewriting the objectives byte for byte is not a change"

# 7. a pass that never got off the ground must not eat the edit that called it
write_objectives ui-layout now          # a person edits
cooldown_elapsed                         # and the pass it triggers starts later, as passes do
run_pass "" 1                            # the runner dies
cooldown_elapsed
check_due 69 "7. a failed pass leaves the objectives edit still pending"
run_pass "" 0                            # ...and the retry serves it
cooldown_elapsed
check_not_due 69 x "7b. once a pass really runs, that same edit is spent"

# 8. the recorded incident, replayed against its own timestamps:
#    07:10 a pass runs with 65 ready; 07:13 that pass promotes two epics;
#    07:37 the next check sees 69 ready and fired anyway.
run_pass later 0
touch -t 202609130710.00 "$MANAGER_STAMP"
touch -t 202609130713.56 "$(objectives)"
check_not_due 69 x "8. the spurious 07:37 pass of 2026-09-13 does not fire"
#    ...and the real trigger that morning still does: the last pass before it
#    ran at 05:30, and the user's 06:08 intake edit promoted an epic.
run_pass "" 0
touch -t 202609130530.00 "$MANAGER_STAMP"
write_objectives icon-svg now
check_due 65 "8b. the user's 06:08 objectives edit that morning still fires"

# 9. the whole of that day in order. Four passes ran and two had no business
#    running, each woken by the edit the pass before it had made:
#      06:08  the user promotes icon-svg
#      07:10  pass one runs, 65 ready                       right
#      07:14  pass one promotes icon-export and icon-grid
#      07:37  pass two runs, 69 ready                       spurious
#      08:26  a task edits the objectives
#      09:12  pass three runs, 72 ready                     right
#      09:16  pass three restages again
#      09:39  pass four runs, 72 ready                      spurious
write_objectives ui-building now         # where the objectives stood overnight
run_pass "" 0; cooldown_elapsed          # ...and the pass that ran against them
write_objectives icon-svg now            # 06:08, the user promotes icon-svg
cooldown_elapsed
check_due 65 "9. 07:10, on the user's edit, is right to run"
run_pass later 0                         # ...and restages two epics at 07:14
cooldown_elapsed
check_not_due 69 x "9b. 07:37, woken by that pass's own edit, does not run"
write_objectives icon-export now         # 08:26, a task
cooldown_elapsed
check_due 72 "9c. 09:12, on a task's edit, is right to run"
run_pass later 0                         # ...and restages again at 09:16
cooldown_elapsed
check_not_due 72 x "9d. 09:39, woken the same way, does not run"

print -r -- ""
print -r -- "manager-due drill: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
