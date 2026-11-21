#!/bin/bash
# A profile of each main thread pass an edit makes, for when Instruments will
# not connect (developer mode off: `DevToolsSecurity -status`).
#
#   Scripts/perf/pass-profile.sh <walk.json> [--no-build] [--match "trim, picked"]
#
# The walk is a speed walk with an `edits` measure (Scripts/playtest/speed-walk.json
# is one), and it must end with a wait the probe sits through, so the samples
# can be named against the live process before it quits:
#
#   { "do": "wait", "seconds": 60, "onTheClock": true }
#
# While it runs, the probe samples its main thread's stack every half
# millisecond (`Sources/Photonz/Playtest/PassSampler.swift`) and keeps the
# samples inside each pass of 6 ms or more the main thread meter reports,
# labelled with the edit. lldb then names the addresses, and
# Scripts/perf/pass-profile.py prints, for each edit and each pass after it,
# where its milliseconds went. The folder stays behind for another reading:
#   Scripts/perf/pass-profile.py /tmp/photonz-pass-sampler --match undo
#
# The sampling stops the main thread for a few microseconds every half
# millisecond, so a profiled pass reads a little longer than it does without:
# judge a fix with the speed walk, never with this.
set -euo pipefail
cd "$(dirname "$0")/../.."

walk=""; build=""; match=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) build="--no-build" ;;
    --match) match=(--match "$2"); shift ;;
    *) walk="$1" ;;
  esac
  shift
done
[ -n "$walk" ] || { sed -n '2,13p' "$0"; exit 2; }
grep -q '"onTheClock": *true' "$walk" || {
  echo "!! $walk has no wait on the clock for the probe to sit through; add one at the end (see the top of this script)"; exit 2; }

folder=/tmp/photonz-pass-sampler
rm -rf "$folder"; mkdir -p "$folder"; touch "$folder/on"
trap 'rm -f "$folder/on"' EXIT

Scripts/playtest.sh "$walk" $build > "$folder/walk.txt" 2>&1 &
walker=$!
waited=0
# A build, the reference edit opening and the edits come first: up to ten
# minutes. Only the file is watched; the walk's own exit is read after.
while [ ! -s "$folder/passes.txt" ] && [ $waited -lt 600 ]; do
  [ -f "$folder/walk.txt" ] && grep -q '^==> Verdict' "$folder/walk.txt" && break
  sleep 1; waited=$((waited + 1))
done
if [ ! -s "$folder/passes.txt" ]; then
  wait $walker || true
  echo "!! the walk wrote no passes (does it time edits?); its output: $folder/walk.txt"; exit 1
fi
sleep 1
pid=$(head -1 "$folder/passes.txt" | cut -d' ' -f2)
grep -v '^PASS\|^pid' "$folder/passes.txt" | tr ' ' '\n' | grep . | sort -u | sed 's/^/0x/' > "$folder/addresses.txt"
cat > "$folder/name_them.py" <<'EOF'
import lldb
def name_them(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    with open('/tmp/photonz-pass-sampler/syms.txt', 'w') as out:
        for line in open('/tmp/photonz-pass-sampler/addresses.txt'):
            found = target.ResolveLoadAddress(int(line.strip(), 16))
            symbol = found.GetSymbol()
            module = found.GetModule().GetFileSpec().GetFilename()
            out.write(f"{line.strip()}\t{module}\t{symbol.GetName() if symbol.IsValid() else '?'}\n")
def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand('command script add -f name_them.name_them name_them')
EOF
lldb -p "$pid" --batch -o "command script import $folder/name_them.py" -o name_them -o detach \
  > "$folder/lldb.txt" 2>&1 || true
wait $walker || true
[ -s "$folder/syms.txt" ] || { echo "!! lldb named nothing (did the probe quit first?): $folder/lldb.txt"; exit 1; }
python3 Scripts/perf/pass-profile.py "$folder" ${match[@]+"${match[@]}"}
