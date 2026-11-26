#!/bin/bash
# Does the loop's probe ever ask for a permission more than once? Launches the
# probe ten times in a row the way a night of walks does, each launch reading
# Screen Recording as never granted, and counts the requests it would have made.
# Exactly one must be an ask; every launch after it must say it asked before.
#
# On 2026-11-26 the person came back to a stack of "Photonz Probe would like to
# record this computer's screen and audio" dialogs and denied a dozen in a row
# while each next one came straight up: the probe asked once per LAUNCH, macOS
# 26 asks every time (Deny records nothing), and each dialog waits behind the
# one on screen after the probe has quit. The rule now lives in one place,
# PermissionGate (Sources/Photonz/Capture), over PermissionAskPolicy (core,
# unit tested); this is the proof on the real app's launch path.
#
#   queue/bin/permission-drill.sh            ten launches of the existing probe
#   queue/bin/permission-drill.sh --build    build the probe first
#   queue/bin/permission-drill.sh -n 20      twenty launches
#
# Nothing reaches macOS: under --permission-drill the probe reads every grant as
# missing, keeps its ledger in a scratch folder (never the real
# dist/probe-permission-asks.json), writes each decision to decisions.log and
# quits. It raises no dialog and opens no window, so it runs whoever is at the
# Mac. Exits 0 when the count is right, 1 when it is not, 2 when it could not run.
set -euo pipefail
cd "$(dirname "$0")/../.."

LAUNCHES=10
BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build) BUILD=1; shift ;;
    -n) LAUNCHES="$2"; shift 2 ;;
    *) echo "usage: $0 [--build] [-n launches]" >&2; exit 2 ;;
  esac
done

APP="dist/Photonz Probe.app"
if (( BUILD )); then Scripts/build-app.sh --probe >/dev/null; fi
[[ -d "$APP" ]] || { echo "!! $APP does not exist; run with --build" >&2; exit 2; }

DIR="$(mktemp -d /tmp/photonz-permission-drill.XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

lines() { if [[ -f "$DIR/decisions.log" ]]; then wc -l < "$DIR/decisions.log" | tr -d ' '; else echo 0; fi; }
for (( i = 1; i <= LAUNCHES; i++ )); do
  before=$(lines)
  # -n: a new copy, so a probe a walk is driving is never disturbed. -g: never
  # brought forward. The drill quits itself a moment after its launch path ran.
  open -g -n "$APP" --args --permission-drill "$DIR"
  for _ in $(seq 1 100); do
    now=$(lines)
    (( now > before )) && break
    sleep 0.1
  done
  if (( now <= before )); then
    echo "!! launch $i wrote no decision in 10 s; the probe may not have started" >&2
    exit 2
  fi
  # Wait for that copy to quit before the next launch, as walks do.
  for _ in $(seq 1 50); do
    pgrep -f "Photonz Probe.app/Contents/MacOS/Photonz Probe --permission-drill $DIR" >/dev/null || break
    sleep 0.1
  done
  pkill -f "Photonz Probe.app/Contents/MacOS/Photonz Probe --permission-drill $DIR" 2>/dev/null || true
done

ASKS=$(grep -c '^screenRecording ask$' "$DIR/decisions.log" || true)
BEFORE=$(grep -c '^screenRecording asked before ' "$DIR/decisions.log" || true)
echo "==> $LAUNCHES launches without the Screen Recording grant: $ASKS ask(s), $BEFORE said it asked before."
sed 's/^/    /' "$DIR/decisions.log"
if (( ASKS == 1 && BEFORE == LAUNCHES - 1 )); then
  echo "==> Verdict: ok  the probe asks once and never again"
  exit 0
fi
echo "==> Verdict: FAILED  expected 1 ask and $((LAUNCHES - 1)) 'asked before'"
exit 1
