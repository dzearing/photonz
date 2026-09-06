#!/bin/bash
# Runs every scripted walk in Scripts/playtest, one after another, and prints a
# line per walk saying whether it passed. The point is repeatability: a walk
# that only passes the first time it is ever run on a machine is worse than no
# walk, so run this twice in a row and expect the same answers both times.
#
#   Scripts/playtest-all.sh                 build once, then run them all
#   Scripts/playtest-all.sh --no-build      reuse the built probe
#   Scripts/playtest-all.sh --no-build a b  only the walks whose names match
#
# Exits 0 when every walk passed. Never touches "dist/Photonz Dev.app".
set -uo pipefail
cd "$(dirname "$0")/.."

BUILD=1
PATTERNS=()
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    *) PATTERNS+=("$arg") ;;
  esac
done

# Build the PROBE BUNDLE, which is the thing every walk below then runs
# against. A plain `swift build` here would warm a debug product nothing in
# this script ever launches, and the run would quietly report on whatever
# bundle happened to be sitting in dist/ (found 2026-09-05).
if [[ $BUILD == 1 ]]; then
  Scripts/probe-app.sh --quit >/dev/null 2>&1
  echo "==> Building the probe bundle..."
  Scripts/build-app.sh --probe >/dev/null || { echo "!! probe build failed"; exit 1; }
fi

PASSED=0
FAILED=()
for walk in Scripts/playtest/*.json; do
  name="$(basename "$walk" .json)"
  if (( ${#PATTERNS[@]} )); then
    match=0
    for p in "${PATTERNS[@]}"; do [[ "$name" == *"$p"* ]] && match=1; done
    (( match )) || continue
  fi
  printf '%-40s ' "$name"
  if out="$(Scripts/playtest.sh "$walk" --no-build 2>&1)"; then
    echo "ok"
    PASSED=$((PASSED + 1))
  else
    reason="$(printf '%s' "$out" | sed -n 's/.*"error" : "\(.*\)",*$/\1/p' | head -1)"
    echo "FAILED  ${reason:-no done.json}"
    FAILED+=("$name")
  fi
done

echo
echo "==> $PASSED passed, ${#FAILED[@]} failed"
(( ${#FAILED[@]} == 0 )) || printf '    %s\n' "${FAILED[@]}"
exit $(( ${#FAILED[@]} == 0 ? 0 : 1 ))
