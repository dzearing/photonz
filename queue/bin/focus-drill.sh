#!/bin/bash
# Does a walk take the person's keyboard, focus or screen? Runs walks with a
# stand-in for the person (queue/bin/focus-canary.swift) holding the front, and
# names every walk and step during which a key typed by that person would have
# gone somewhere else.
#
# On 2026-09-26 the user could not type while the loop tested; pulling focus
# back to say "stop testing" took five tries. This is the measurement for the
# fix and the proof it stays fixed.
#
#   queue/bin/focus-drill.sh <walk-name-or-file> [...]   run those walks
#   queue/bin/focus-drill.sh --check                     the standing set, below
#   queue/bin/focus-drill.sh --all --slice 3/12          a twelfth of every walk,
#                                                        for a night's run in pieces
#
# For each walk it prints one line: `clean`, `TOOK FOCUS` with the steps, or
# `menu shown` for a walk that photographs an open menu, which cannot be done
# without the menu really open (queue/bin/walk-needs-the-mac.mjs) and takes the
# keys only for that picture.
# A theft is any of: another app became active (the probe, or anything the
# probe woke), the canary's window stopped being key, or a probe menu was on
# screen (a menu takes every key at the window server until it closes). A
# visible probe window drawn above the canary counts too, as `covered`.
#
# What was found and fixed on 2026-09-26, each one a walk in the standing set:
# opening a recording activated the probe (AppFront); a guide ordered its window
# in front of every app at every step; reading or picking from a menu opened it
# on screen (rightClick, panelMenu, including SwiftUI's own Add Effect menu); a
# press's release lifted the walk's window over the person's
# (PlaytestHarness.keepBehindThePerson and walkWindowLevel).
#
# Exits 0 when every walk that ran was clean or only showed a menu it
# photographs, 1 when one took focus, and 6 (DEFERRED) when somebody was using
# the Mac: the canary takes the front, so it never runs under a person's hands.
set -uo pipefail
cd "$(dirname "$0")/../.."

# The standing set: one walk per way a walk was seen taking the front.
CHECK=(
  a-clip-s-sound-is-linked-under-it-walk
  effects-remembered-walk
  locked-layer-key-press-walk
  tutorial-a-title-that-moves-walk
)

WALKS=()
SLICE=""
ALL=0
while (( $# )); do
  case "$1" in
    --check) WALKS+=("${CHECK[@]}") ;;
    --all) ALL=1 ;;
    --slice) SLICE="${2:-}"; shift ;;
    *) WALKS+=("$1") ;;
  esac
  shift
done
if (( ALL )); then
  mapfile_all() { ls Scripts/playtest/*-walk.json | sort; }
  i=0; part="${SLICE%%/*}"; of="${SLICE##*/}"
  [[ -n "$SLICE" ]] || { part=1; of=1; }
  while IFS= read -r f; do
    (( i % of == part - 1 )) && WALKS+=("$f")
    i=$((i + 1))
  done < <(mapfile_all)
fi
(( ${#WALKS[@]} )) || { echo "usage: focus-drill.sh <walk> [...] | --check | --all [--slice i/n]" >&2; exit 2; }

resolve() {
  local w="$1"
  [[ -f "$w" ]] && { echo "$w"; return; }
  [[ -f "Scripts/playtest/$w" ]] && { echo "Scripts/playtest/$w"; return; }
  [[ -f "Scripts/playtest/$w.json" ]] && { echo "Scripts/playtest/$w.json"; return; }
  [[ -f "Scripts/playtest/$w-walk.json" ]] && { echo "Scripts/playtest/$w-walk.json"; return; }
  return 1
}

if ! queue/bin/person-at-mac.sh away 60; then
  echo "==> Verdict: DEFERRED  somebody is using the Mac, and the canary would take their front"
  exit 6
fi

DIR=".build/focus-drill"
mkdir -p "$DIR"
CANARY="$DIR/focus-canary"
if [[ ! -x "$CANARY" || queue/bin/focus-canary.swift -nt "$CANARY" ]]; then
  swiftc -O -swift-version 5 queue/bin/focus-canary.swift -o "$CANARY" || exit 2
fi

PROBE_ID="com.dzearing.photonz.probe"
RUN="$DIR/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
WORST=0
DEFERRED=0

for w in "${WALKS[@]}"; do
  FILE="$(resolve "$w")" || { echo "!! no walk named $w" >&2; WORST=2; continue; }
  NAME="$(basename "$FILE" .json)"
  TRACE="$RUN/$NAME.jsonl"
  # A fresh canary per walk, in front, with a lifetime that outlasts the walk's
  # own timeout so it can never be left running.
  "$CANARY" "$TRACE" "$PROBE_ID" 420 &
  CANARY_PID=$!
  sleep 1
  BEGAN="$(node -e 'console.log(Date.now())')"
  Scripts/playtest.sh "$FILE" --no-build >"$RUN/$NAME.out" 2>&1
  CODE=$?
  ENDED="$(node -e 'console.log(Date.now())')"
  sleep 0.5
  kill "$CANARY_PID" 2>/dev/null; wait "$CANARY_PID" 2>/dev/null
  if (( CODE == 6 )); then
    printf '%-48s DEFERRED (somebody came back)\n' "$NAME"
    DEFERRED=1
    break
  fi
  EXPECTED="$(queue/bin/walk-needs-the-mac.mjs "$FILE" 2>/dev/null || true)"
  OUT="$(sed -n 's/^==> Waiting up to [0-9]*s for \(.*\)\/done.json$/\1/p' "$RUN/$NAME.out" | head -1)"
  node - "$TRACE" "$OUT" "$BEGAN" "$ENDED" "$NAME" "$CODE" "$FILE" "$EXPECTED" <<'NODE' || WORST=1
const fs = require("fs");
const [trace, out, began, ended, name, code, walk, expected] = process.argv.slice(2);
const lines = fs.readFileSync(trace, "utf8").split("\n").filter(Boolean).map(l => JSON.parse(l));
const canaryPid = lines.find(l => l.kind === "start")?.pid;
// Where the walk was, on the wall clock, from its own log. A log line is
// written as a step FINISHES, so whatever happened after step N's line and
// before step N+1's belongs to step N+1, named from the walk's own script.
let done = [];
let script = [];
try { script = JSON.parse(fs.readFileSync(walk, "utf8")).steps || []; } catch {}
try {
  const log = JSON.parse(fs.readFileSync(out + "/log.json", "utf8"));
  const result = JSON.parse(fs.readFileSync(out + "/done.json", "utf8"));
  const zero = fs.statSync(out + "/done.json").mtimeMs - result.seconds * 1000;
  for (const e of log) if (e.step > 0) done.push({ step: e.step, ms: zero + e.t * 1000 });
} catch {}
const stepAt = ms => {
  let last = 0;
  for (const d of done) if (d.ms <= ms && d.step > last) last = d.step;
  const running = last + 1;
  const what = script[running - 1]?.do;
  return what ? `step ${running} (${what})` : last ? `after step ${last}` : "launch and setup";
};
const inWalk = l => l.ms >= +began && l.ms <= +ended;
const took = new Map();
const note = (ms, why) => {
  const at = stepAt(ms);
  if (!took.has(at)) took.set(at, new Set());
  took.get(at).add(why);
};
let lost = 0, ticks = 0, covered = 0;
for (const l of lines.filter(inWalk)) {
  if (l.kind === "activate" && l.pid !== canaryPid) note(l.ms, `activated ${l.app}`);
  if (l.kind !== "tick") continue;
  ticks++;
  if (!l.landed) {
    lost++;
    const menu = (l.probe || []).some(p => p.layer >= 101);
    note(l.ms, menu ? "a probe menu held the keys" : !l.active ? `front was ${l.front}` : "canary window not key");
  }
  if ((l.probe || []).some(p => p.above && p.layer < 101 && (p.alpha ?? 1) > 0)) { covered++; note(l.ms, "probe window above the canary"); }
}
// A walk that photographs an open menu takes the keys for that picture and
// nothing else; anything more than the menu (another app active, the walk's
// window over the canary) is still a theft.
const onlyMenus = [...took.values()].every(why => [...why].every(w =>
  w === "a probe menu held the keys" || w === "canary window not key"));
const verdict = !took.size ? "clean" : expected && onlyMenus ? "menu shown" : "TOOK FOCUS";
console.log(`${name.padEnd(48)} ${verdict.padEnd(10)} ${lost}/${ticks} ticks lost, ${covered} covered, walk exit ${code}`);
if (verdict === "menu shown") console.log(`    expected: it ${expected}`);
for (const [at, why] of took) console.log(`    ${at}: ${[...why].join("; ")}`);
process.exit(verdict === "TOOK FOCUS" ? 1 : 0);
NODE
done

pgrep -f "$CANARY" >/dev/null && pkill -f "$CANARY"
echo "==> traces in $RUN"
(( DEFERRED )) && { echo "==> Verdict: DEFERRED  somebody came back part way through"; exit 6; }
exit "$WORST"
