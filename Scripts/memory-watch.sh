#!/bin/zsh
# Records how much memory the probe and every program it starts hold, once
# every few seconds, the way Activity Monitor's Memory column counts it
# (`footprint`, the process's physical footprint, not RSS: a model file the
# chat server maps in shows as 22 GB of RSS and is not memory anybody lost).
#
#   Scripts/memory-watch.sh <out.csv> [--every 5] [--for 1800]
#
# One row per program per sample: seconds since the start, pid, name, bytes.
# The probe is found by its bundle's executable path, so this never measures
# the person's own app. Programs the probe starts are found by walking the
# parent tree down from it (the Ask helpers run under a small /bin/sh watch).
# It stops by itself after --for seconds, or when the probe is gone for a
# minute, so it never outlives what it watches.
#
# `node Scripts/memory-chart.mjs <out.csv> <chart.svg>` draws it.
set -u
out="${1:?usage: memory-watch.sh <out.csv> [--every s] [--for s]}"
shift
every=5
limit=1800
while (( $# )); do
  case "$1" in
    --every) every="$2"; shift 2 ;;
    --for) limit="$2"; shift 2 ;;
    *) echo "memory-watch: unknown argument $1" >&2; exit 2 ;;
  esac
done
MATCH="Photonz Probe.app/Contents/MacOS"
start=$(date +%s)
gone=0
echo "seconds,pid,name,bytes" > "$out"

descendants() {
  local parent=$1 child
  for child in $(pgrep -P "$parent" 2>/dev/null); do
    echo "$child"
    descendants "$child"
  done
}

while true; do
  now=$(date +%s)
  elapsed=$(( now - start ))
  (( elapsed > limit )) && break
  probe=$(pgrep -f "$MATCH" | head -1)
  if [[ -z "$probe" ]]; then
    gone=$(( gone + every ))
    (( gone >= 60 )) && break
  else
    gone=0
    for pid in $probe $(descendants "$probe"); do
      line=$(footprint -f bytes --noCategories -p "$pid" 2>/dev/null | grep -m1 'Footprint:')
      [[ -z "$line" ]] && continue
      bytes=$(echo "$line" | sed -E 's/.*Footprint: ([0-9]+) B.*/\1/')
      name=$(ps -o comm= -p "$pid" 2>/dev/null | sed 's#.*/##')
      [[ "$name" == "sh" || "$name" == "sleep" ]] && continue
      echo "$elapsed,$pid,$name,$bytes" >> "$out"
    done
  fi
  sleep "$every"
done
