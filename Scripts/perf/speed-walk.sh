#!/bin/bash
# The speed walk: the reference edit played, scrubbed, edited while it plays,
# its timeline scrolled and zoomed, its memory read and its export timed, the
# way a person uses it (`Sources/Photonz/Playtest/PlaytestSpeedWalk.swift`,
# `Sources/PhotonzCore/SpeedWalk.swift`). Every video speed fix is judged by
# its numbers.
#
#   Scripts/perf/speed-walk.sh [--no-build]                 the short form (the walk set's)
#   Scripts/perf/speed-walk.sh --long [6] [20] [60] [--no-build]
#   Scripts/perf/speed-walk.sh --baseline [N] [--no-build]  N short runs (3 by default), their
#                                                           worst written as the short walk's baseline
#
# A speed fix that makes the edit faster ends with --baseline, so the short
# walk holds the new numbers from then on. The baseline is the worst of a few
# runs because, while stalls last seconds, one run differs from the next by
# half again.
#
# The short form is Scripts/playtest/speed-walk.json, about two minutes, and
# fails on anything worse than Scripts/perf/baselines/short-6.json by its
# margin. The long form (Scripts/perf/walks/) plays the 6 minute edit whole,
# scrubs at three speeds, makes six edits while it plays, zooms and scrolls
# the timeline, exports, and on the 60 minute edit plays and scrubs for ten
# minutes reading memory each second: about 12 minutes plus an export of more
# than 25 minutes for the 6 minute edit, and 6 and 20 minutes for the
# 20 and 60 minute ones. It is never part of the walk set or the rotating
# check.
#
# Each run writes one results file under $PHOTONZ_SPEED_RESULTS (default
# ~/Library/Caches/Photonz Reference Edit/speed-results), named by date,
# commit, form and length, and prints its path. Set two side by side with
# Scripts/perf/compare.sh <before.json> <after.json>.
set -uo pipefail
cd "$(dirname "$0")/../.."

LONG=0
BUILD=1
BASELINE=0
LENGTHS=()
for arg in "$@"; do
  case "$arg" in
    --long) LONG=1 ;;
    --baseline) BASELINE=3 ;;
    --no-build) BUILD=0 ;;
    6|20|60) LENGTHS+=("$arg") ;;
    [1-9]) (( BASELINE )) && BASELINE="$arg" || { echo "usage: $0 [--long [6] [20] [60]] [--baseline [N]] [--no-build]" >&2; exit 2; } ;;
    *) echo "usage: $0 [--long [6] [20] [60]] [--baseline [N]] [--no-build]" >&2; exit 2 ;;
  esac
done
(( LONG )) && (( ${#LENGTHS[@]} == 0 )) && LENGTHS=(6 20 60)

RESULTS="${PHOTONZ_SPEED_RESULTS:-$HOME/Library/Caches/Photonz Reference Edit/speed-results}"
mkdir -p "$RESULTS"
HEAD="$(git rev-parse --short HEAD)"
[[ -n "$(git status --porcelain -- Sources Package.swift 2>/dev/null)" ]] && HEAD="$HEAD+changes"
STAMP="$(date +%Y-%m-%d-%H%M)"

# Runs one walk, prints the path of the speed.json it wrote.
walk() {
  local script="$1"
  local flags=()
  (( BUILD )) || flags+=(--no-build)
  BUILD=0
  Scripts/playtest.sh "$script" "${flags[@]+"${flags[@]}"}" >&2
  local status=$?
  local out
  out="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).out)' "$script")"
  if [[ ! -f "$out/speed.json" ]]; then
    echo "!! $script wrote no speed.json (walk exit $status)" >&2
    return 1
  fi
  (( status == 0 )) || echo "!! $script ended with exit $status; keeping what it measured" >&2
  echo "$out/speed.json"
}

# Folds the parts of one run into one file, stamped with the commit.
merge() {
  local dest="$1"; shift
  node -e '
    const fs = require("fs");
    const [dest, head, ...parts] = process.argv.slice(1);
    let run = null;
    for (const part of parts) {
      const one = JSON.parse(fs.readFileSync(part, "utf8"));
      if (!run) { run = one; continue; }
      for (const [key, value] of Object.entries(one)) {
        const empty = value == null || (Array.isArray(value) && !value.length)
          || (typeof value === "object" && !Array.isArray(value) && !Object.keys(value).length);
        if (!empty && !["date", "form", "head", "machine", "minutes", "frameStepMS"].includes(key)) run[key] = value;
      }
    }
    run.head = head;
    fs.writeFileSync(dest, JSON.stringify(run, null, 2) + "\n");
  ' "$dest" "$HEAD" "$@"
  echo "==> $dest"
}

if (( BASELINE )); then
  runs=()
  for ((i = 1; i <= BASELINE; i++)); do
    part="$(walk Scripts/playtest/speed-walk.json)" || exit 1
    one="$RESULTS/$STAMP-$HEAD-short-6-$i.json"
    merge "$one" "$part"
    runs+=("$one")
  done
  swift build --product ReferenceEditTool 2>&1 | grep -E " error: " || true
  "$(swift build --show-bin-path)/ReferenceEditTool" envelope Scripts/perf/baselines/short-6.json "${runs[@]}"
  Scripts/probe-app.sh --quit >/dev/null 2>&1 || true
  exit 0
fi

if (( ! LONG )); then
  part="$(walk Scripts/playtest/speed-walk.json)" || exit 1
  merge "$RESULTS/$STAMP-$HEAD-short-6.json" "$part"
  exit 0
fi

for minutes in "${LENGTHS[@]}"; do
  parts=()
  case "$minutes" in
    6) scripts=(Scripts/perf/walks/long-6-play.json Scripts/perf/walks/long-6-rest.json Scripts/perf/walks/long-6-export.json) ;;
    *) scripts=("Scripts/perf/walks/long-$minutes.json") ;;
  esac
  for script in "${scripts[@]}"; do
    part="$(walk "$script")" && parts+=("$part")
  done
  (( ${#parts[@]} )) && merge "$RESULTS/$STAMP-$HEAD-long-$minutes.json" "${parts[@]}"
done
Scripts/probe-app.sh --quit >/dev/null 2>&1 || true
