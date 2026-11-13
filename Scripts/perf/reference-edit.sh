#!/bin/bash
# Opens the reference edit in the probe: the same long, busy video every speed
# fix measures against (`Sources/PhotonzCore/ReferenceEdit.swift`).
#
#   Scripts/perf/reference-edit.sh 6|20|60 [--no-open] [--no-build]
#
# Writes "Reference Edit <N> min.photonz" under the reference edit's folder
# (~/Library/Caches/Photonz Reference Edit, or $PHOTONZ_REFERENCE_EDIT_DIR),
# its four Retina screen recordings and its music written there first, once per
# machine (a few minutes the first time), then opens it with
# Scripts/probe-app.sh. The project is written fresh every run, so nothing saved
# into it last time carries over. A walk reaches the same edit with
# "setup": { "referenceEdit": 6 }.
set -euo pipefail
cd "$(dirname "$0")/../.."

MINUTES=""
OPEN=1
BUILD=1
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN=0 ;;
    --no-build) BUILD=0 ;;
    6|20|60) MINUTES="$arg" ;;
    *) echo "usage: $0 6|20|60 [--no-open] [--no-build]" >&2; exit 2 ;;
  esac
done
[[ -n "$MINUTES" ]] || { echo "usage: $0 6|20|60 [--no-open] [--no-build]" >&2; exit 2; }

if (( BUILD )); then
  swift build --product ReferenceEditTool 2>&1 | grep -E "error|warning: unre" || true
fi
TOOL="$(swift build --show-bin-path)/ReferenceEditTool"
[[ -x "$TOOL" ]] || { echo "!! $TOOL was not built" >&2; exit 1; }

echo "==> Writing the ${MINUTES} minute reference edit"
OUT="$("$TOOL" "$MINUTES" | tee /dev/stderr)"
PROJECT="$(printf '%s\n' "$OUT" | tail -1)"
[[ -d "$PROJECT" ]] || { echo "!! No project at $PROJECT" >&2; exit 1; }

if (( OPEN )); then
  if (( BUILD )); then
    Scripts/probe-app.sh "$PROJECT"
  else
    Scripts/probe-app.sh --no-build "$PROJECT"
  fi
fi
