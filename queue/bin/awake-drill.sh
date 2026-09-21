#!/bin/zsh
# Drill for the hold that keeps the Mac awake while the go loop is working.
#
#   queue/bin/awake-drill.sh
#
# The user asked on 2026-09-20 for the loop to stop their Mac locking itself
# while it works. Until 2026-09-21 the only hold in the tree belonged to
# Scripts/playtest-all.sh and lasted exactly one sweep, so the Mac was let go in
# every gap between sweeps. It locked itself in one of those gaps thirty one
# minutes after the answer and stayed locked, which cost 163 of 544 walks on
# every sweep afterwards and put a caveat on every picture in every audit.
#
# A hold is a thing left running on somebody else's machine, so what this drill
# holds honest is mostly about letting go:
#
#   1. a loop takes a real power assertion when it starts, not a promise of one
#   2. it is the display-and-idle assertion, and never the one that lights a
#      display somebody has put to sleep
#   3. a reload adopts the hold it already has instead of stacking a second
#   4. a clean stop releases it and leaves nothing behind
#   5. a SIGKILL, which runs no trap at all, releases it too
#   6. a sweep defers to the loop's hold rather than taking its own
#   7. nothing here ever touches a hold the user started by hand
#   8. no code anywhere reaches for pkill to put a hold down
#   9. the hold does not unlock a locked Mac, and the loop says so plainly
#
# It takes real holds on this machine and puts every one of them down; the last
# check is that none of them is still standing.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

SANDBOX_DIR=$(mktemp -d -t photonz-awake-drill)
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); print -r -- "  ok   $1" }
bad() { FAIL=$((FAIL+1)); print -r -- "  FAIL $1" }
alive() { kill -0 "$1" 2>/dev/null }
asserted() { pmset -g assertions 2>/dev/null | grep -q "pid $1(caffeinate)" }

# Everything this drill starts, by pid, so the cleanup cannot miss one. Never a
# pattern: a pkill for caffeinate would take the user's own hold with it.
STARTED=()
cleanup_drill() {
  for p in ${STARTED[@]+"${STARTED[@]}"}; do kill "$p" 2>/dev/null; done
  rm -rf "$SANDBOX_DIR"
}
trap cleanup_drill EXIT INT TERM

export PHOTONZ_QUEUE_DIR="$SANDBOX_DIR/queue"
mkdir -p "$PHOTONZ_QUEUE_DIR"
export PHOTONZ_GO_LOOP_DEFS_ONLY=1
source queue/bin/go-loop.sh || { print -r -- "could not source go-loop.sh for its definitions"; exit 1 }

print -r -- "a loop that starts takes a real hold:"
hold_awake
STARTED+=("$AWAKE")
if [[ -n "$AWAKE" ]] && alive "$AWAKE"; then ok "it started one (pid $AWAKE)"; else bad "no hold was started"; fi
sleep 1
if asserted "$AWAKE"; then ok "and the system agrees it is holding an assertion"
else bad "pmset does not list an assertion owned by pid $AWAKE"; fi
if [[ "$(cat "$AWAKE_PIDFILE" 2>/dev/null)" == "$AWAKE" ]]; then ok "the pid is written down, so it can be put down by pid"
else bad "the pidfile does not name the hold"; fi

print -r -- "it holds off the display and the idle sleep behind the lock:"
WHAT=$(pmset -g assertions 2>/dev/null | grep "pid $AWAKE(caffeinate)")
if print -r -- "$WHAT" | grep -q PreventUserIdleDisplaySleep; then ok "PreventUserIdleDisplaySleep, which is what the screen saver hangs off"
else bad "the assertion is not PreventUserIdleDisplaySleep: $WHAT"; fi
# -u would light up a display somebody has already put to sleep, at whatever
# hour the loop reaches it. The loop must never take that one.
if print -r -- "$WHAT" | grep -q UserIsActive; then bad "it claims the user is active, which can wake a sleeping display"
else ok "it never claims the user is active, so it cannot wake a sleeping display"; fi
if ps -o command= -p "$AWAKE" | grep -q -- "-w"; then ok "it is watching the loop's pid, so the loop dying releases it"
else bad "it is not watching a pid: $(ps -o command= -p "$AWAKE")"; fi

print -r -- "a reload keeps the hold it already has:"
FIRST=$AWAKE
hold_awake
if [[ "$AWAKE" == "$FIRST" ]]; then ok "a second hold_awake adopts the live one instead of stacking"
else bad "it started a second hold (was $FIRST, now $AWAKE)"; STARTED+=("$AWAKE"); fi

print -r -- "a hold that is not ours is never adopted, however the pidfile reads:"
# A loop that was SIGKILLed leaves the note behind even though its hold went
# with it, and on a machine where the user runs caffeinate by hand that pid can
# come round again. Adopting one would mean killing it on the way out.
# Started from a subshell that exits at once, so the caffeinate is reparented
# away and looks exactly like one left over from a loop that is gone, or one a
# person started in another window.
( caffeinate -d -i -t 30 & print -r -- $! > "$SANDBOX_DIR/stranger.pid" )
sleep 1
STRANGER=$(cat "$SANDBOX_DIR/stranger.pid")
STARTED+=("$STRANGER")
print -r -- "$STRANGER" > "$AWAKE_PIDFILE"
KEEP=$AWAKE; AWAKE=""
hold_awake
if [[ "$AWAKE" != "$STRANGER" ]]; then ok "it started its own instead (pid $AWAKE, not $STRANGER)"; STARTED+=("$AWAKE")
else bad "it adopted a caffeinate it did not start"; fi
release_awake
sleep 1
if alive "$STRANGER"; then ok "and the stranger is still running"
else bad "it killed a caffeinate it did not start"; fi
kill "$STRANGER" 2>/dev/null
AWAKE=$KEEP
print -r -- "$KEEP" > "$AWAKE_PIDFILE"

print -r -- "a hold the user started by hand is never touched:"
caffeinate -d -i -t 60 &
USERS=$!
STARTED+=("$USERS")
release_awake
sleep 1
if alive "$USERS"; then ok "release_awake left it alone (pid $USERS)"
else bad "release_awake killed a hold it did not start"; fi
kill "$USERS" 2>/dev/null

print -r -- "a clean stop leaves nothing behind:"
if alive "$FIRST"; then bad "the loop's own hold is still running after release_awake"
else ok "the loop's own hold is gone"; fi
if [[ -e "$AWAKE_PIDFILE" ]]; then bad "the pidfile is still there"; else ok "and so is the note of it"; fi
# A pid recorded minutes ago may be somebody else's process by now, and killing
# that would be worse than leaving a hold behind.
if is_a_live_hold $$; then bad "the pid-reuse guard calls this shell a hold"
else ok "and it refuses to call a pid that is not a caffeinate a hold"; fi

print -r -- "a SIGKILL releases it too, with no trap run at all:"
# The whole reason the loop's hold is -w rather than -t: a killed loop runs no
# handler, so nothing of ours gets the chance to tidy up and caffeinate has to
# notice by itself.
VICTIMF="$SANDBOX_DIR/victim.pid"
# exec keeps the pid, so the hold is watching the pid that is about to be killed
# and there is nothing left in that process that could tidy up after itself.
zsh -c 'caffeinate -d -i -w $$ & print -r -- $! > "$1"; exec sleep 30' _ "$VICTIMF" &
VICTIM_PID=$!
sleep 1
VICTIM_HOLD=$(cat "$VICTIMF" 2>/dev/null)
if [[ -n "$VICTIM_HOLD" ]] && alive "$VICTIM_HOLD"; then
  STARTED+=("$VICTIM_HOLD")
  kill -9 "$VICTIM_PID" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do alive "$VICTIM_HOLD" || break; sleep 1; done
  if alive "$VICTIM_HOLD"; then bad "the hold outlived the process it was watching (pid $VICTIM_HOLD)"
  else ok "the hold went with the process it was watching"; fi
else
  bad "could not start a hold to kill"
fi

print -r -- "a sweep defers to the loop's hold instead of taking its own:"
hold_awake
STARTED+=("$AWAKE")
LOOPS=$AWAKE
BEFORE=$(pgrep -x caffeinate | wc -l | tr -d ' ')
WALKPID="$SANDBOX_DIR/walk-awake.pid"
OUT=$(PHOTONZ_WALK_AWAKE_PIDFILE="$WALKPID" Scripts/playtest-all.sh --no-build zzz-no-such-walk 2>&1)
AFTER=$(pgrep -x caffeinate | wc -l | tr -d ' ')
if print -r -- "$OUT" | grep -q "already holding this Mac awake (pid $LOOPS)"; then
  ok "it says whose hold is covering the run"
else
  bad "it did not defer: $(print -r -- "$OUT" | head -3)"
fi
if [[ "$BEFORE" == "$AFTER" ]]; then ok "and took no second hold ($BEFORE before, $AFTER after)"
else bad "a second hold appeared ($BEFORE before, $AFTER after)"; fi
# No pidfile is the signal to sweep.sh stop_the_run and sweep-recover.mjs that
# there is no hold of the sweep's to release, so neither of them reaches for
# the loop's.
if [[ -e "$WALKPID" ]]; then bad "it wrote a pidfile for a hold it did not take"
else ok "and left no pidfile, so nothing downstream goes looking for the loop's"; fi
release_awake

print -r -- "nobody anywhere puts a hold down with a pattern:"
# pkill caffeinate matches the user's own hold exactly as well as ours.
# Only lines that would RUN one. Every mention in the tree today is a comment
# saying not to, and those are the reason it stays that way.
HITS=$(grep -rn "pkill" Scripts queue/bin 2>/dev/null | grep -v "^queue/bin/awake-drill.sh:" \
       | grep -i caffeinate | grep -vE ':[[:space:]]*(#|//)')
if [[ -z "$HITS" ]]; then ok "no pkill anywhere near a caffeinate"
else bad "something reaches for pkill: $HITS"; fi

print -r -- "the hold does not unlock a Mac, and the loop says so:"
# The one thing a hold cannot do. A loop starting on a locked screen that read
# as having fixed it would send runners looking for bugs that are not there.
if screen_locked; then STATE=locked; else STATE=unlocked; fi
ok "this Mac reads as $STATE right now"
hold_awake
STARTED+=("$AWAKE")
SAID=$(say_about_the_hold 2>&1)
release_awake
if [[ "$STATE" == locked ]]; then
  if print -r -- "$SAID" | grep -q "ALREADY LOCKED"; then ok "and the loop says the screen is already locked and it does not unlock it"
  else bad "the loop did not say the screen was already locked: $SAID"; fi
  if print -r -- "$SAID" | grep -q "stops the NEXT lock"; then ok "and says what the hold does buy"
  else bad "it did not say what the hold buys: $SAID"; fi
else
  if print -r -- "$SAID" | grep -q "holding the Mac awake"; then ok "and the loop says it is holding the Mac awake"
  else bad "the loop said nothing about the hold: $SAID"; fi
fi

print -r -- "nothing this drill started is still running:"
LEFT=()
for p in ${STARTED[@]+"${STARTED[@]}"}; do alive "$p" && LEFT+=("$p"); done
if (( ${#LEFT[@]} == 0 )); then ok "every hold it took is down"
else bad "still holding: ${LEFT[*]}"; fi

print -r -- ""
print -r -- "$PASS passed, $FAIL failed"
exit $(( FAIL > 0 ))
