#!/bin/zsh
# Kill runaway shells a task runner left behind.
#
# On 2026-09-14 the user found ten orphaned `while :; do :; done` loops pegged at
# 99% CPU for 41 hours: a runner had spawned them on purpose to simulate a slow
# machine while testing the perf gate, then cleaned up with
# `BURNERS=$(jobs -p); kill $BURNERS`. In a non-interactive shell that command
# substitution runs in a subshell that cannot see the parent's jobs, so the
# variable was empty, the kill hit nothing, and the loops were orphaned to PID 1
# when the runner exited. Ten cores were gone until a person noticed.
#
# A rule in the runner prompt is advice. This is the enforcement: the loop sweeps
# between tasks and anything matching ALL of the tests below is killed.
#
# The tests are deliberately narrow, because killing the wrong process is worse
# than leaving a busy one:
#   - the command carries the Claude shell-snapshot signature, so it was started
#     by an agent's Bash call and is not a shell the user is typing in;
#   - its parent is PID 1, so whoever started it is already gone and nothing is
#     waiting on it;
#   - it is over the CPU floor, so a quiet orphan waiting on IO is left alone;
#   - it has been alive longer than the grace period, so a legitimate build or
#     test run that is briefly parentless is not shot.
# A live Bash call never matches: its parent is alive.

set -u

CPU_FLOOR=${REAP_CPU_FLOOR:-50}      # percent of one core
MIN_SECONDS=${REAP_MIN_SECONDS:-600} # 10 minutes
DRY=${REAP_DRY_RUN:-0}

# elapsed "dd-hh:mm:ss" / "hh:mm:ss" / "mm:ss" -> seconds
elapsed_seconds() {
  local e=$1 days=0
  if [[ $e == *-* ]]; then days=${e%%-*}; e=${e#*-}; fi
  local -a p; p=(${(s/:/)e})
  local s=0
  for f in $p; do s=$(( s * 60 + 10#$f )); done
  print -- $(( s + days * 86400 ))
}

reaped=0
while read -r pid ppid pcpu etime rest; do
  [[ $ppid == 1 ]] || continue
  (( ${pcpu%%.*} >= CPU_FLOOR )) || continue
  (( $(elapsed_seconds $etime) >= MIN_SECONDS )) || continue
  if (( DRY )); then
    print -- "would reap $pid (${pcpu}% for $etime)"
  else
    kill -9 $pid 2>/dev/null && print -- "reaped runaway shell $pid (${pcpu}% for $etime)"
  fi
  reaped=$(( reaped + 1 ))
done < <(ps ax -o pid=,ppid=,pcpu=,etime=,command= | grep 'claude/shell-snapshots' | grep -v 'reap-runaways')

if (( reaped > 0 )); then
  print -- "reap-runaways: $reaped runaway shell(s)"
  if [[ -f queue/bin/queue.mjs ]]; then
    node queue/bin/queue.mjs event runaways_reaped "{\"count\":$reaped}" 2>/dev/null || true
  fi
fi
exit 0
