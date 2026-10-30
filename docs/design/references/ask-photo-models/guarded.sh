#!/bin/bash
# guarded.sh <log> <command...>: runs the command in its own process group and
# kills the group the moment the person touches the Mac (idle under 20 s).
log=$1; shift
set -m
"$@" > "$log" 2>&1 &
pid=$!
while kill -0 $pid 2>/dev/null; do
  idle=$(/Users/dzearing/git/photonz/queue/bin/person-at-mac.sh idle)
  if (( idle < 20 )); then
    echo "PERSON BACK at $(date +%T), stopping" >> "$log"
    kill -TERM -$pid 2>/dev/null; sleep 3; kill -KILL -$pid 2>/dev/null
    /Users/dzearing/git/photonz/Scripts/probe-app.sh --quit >/dev/null 2>&1
    echo "exit stopped" >> "$log"; exit 0
  fi
  sleep 3
done
wait $pid; echo "exit $?" >> "$log"
