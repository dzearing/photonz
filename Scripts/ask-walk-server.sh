#!/bin/bash
# The one Ask model server a walk run shares (Sources/PhotonzCore/AskWalkServer.swift).
#
# Every walk starts a new probe, and every probe used to load the whole Ask
# model for itself: about 23 GB and the GPU flat out for a minute or more, once
# per Ask walk. Now the first probe in a run that needs the model starts one
# server outside itself, gently, and the probes after it adopt it. This script
# is the run's side of that: it says which run owns the server, and lets the
# server go when that run ends.
#
#   Scripts/ask-walk-server.sh begin <pid>   <pid>'s run owns the shared server,
#                                            unless a run still going already does
#   Scripts/ask-walk-server.sh end <pid>     <pid>'s run is over: stop the server
#                                            if <pid> owns it
#   Scripts/ask-walk-server.sh stop          stop it, whoever owns it (the go loop)
#   Scripts/ask-walk-server.sh status        what is running, if anything
#
# The server's own watch lets it go anyway when the owning run is gone or after
# three idle minutes, so a run killed with SIGKILL leaves nothing loaded either.
set -uo pipefail

DIR="$HOME/Library/Caches/Photonz/ask-walk-server"
RUN="$DIR/run"

alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }

stop_server() {
  local pids server watch i
  pids="$(cat "$DIR/server.pid" 2>/dev/null || true)"
  server="${pids%% *}"
  watch="${pids##* }"
  [[ -n "$pids" && "$server" != "$watch" ]] || { rm -f "$DIR/record.json"; return 0; }
  alive "$watch" && kill -TERM "$watch" 2>/dev/null
  for ((i = 0; i < 100; i++)); do alive "$server" || break; sleep 0.1; done
  if alive "$server" && ps -o command= -p "$server" | grep -q 'llama-server'; then
    kill -9 "$server" 2>/dev/null
  fi
  rm -f "$DIR/server.pid" "$DIR/record.json"
  echo "==> Shared Ask walk server stopped (it was pid $server)."
}

case "${1:-}" in
  begin)
    mkdir -p "$DIR"
    owner="$(cat "$RUN" 2>/dev/null || true)"
    # A run still going keeps it: playtest-all.sh owns it for every
    # playtest.sh it calls.
    if alive "$owner" && [[ "$owner" != "${2:?pid}" ]]; then exit 0; fi
    echo "$2" > "$RUN"
    ;;
  end)
    owner="$(cat "$RUN" 2>/dev/null || true)"
    [[ "$owner" == "${2:?pid}" ]] || exit 0
    rm -f "$RUN"
    stop_server
    ;;
  stop)
    rm -f "$RUN"
    stop_server
    ;;
  status)
    if [[ -f "$DIR/server.pid" ]]; then
      server="$(cut -d' ' -f1 "$DIR/server.pid")"
      if alive "$server"; then
        echo "==> Shared Ask walk server: pid $server, $(ps -o rss= -p "$server" | awk '{printf "%.1f GB", $1/1048576}') held"
        cat "$DIR/record.json" 2>/dev/null; echo
      else
        echo "==> No shared Ask walk server running (a stale pid file names $server)."
      fi
    else
      echo "==> No shared Ask walk server running."
    fi
    owner="$(cat "$RUN" 2>/dev/null || true)"
    alive "$owner" && echo "==> Owned by the walk run with pid $owner."
    ;;
  *)
    echo "usage: Scripts/ask-walk-server.sh begin <pid> | end <pid> | stop | status" >&2
    exit 1
    ;;
esac
exit 0
