#!/bin/bash
# Opens the reference edit: the same long, busy video every speed fix measures
# against (`Sources/PhotonzCore/ReferenceEdit.swift`).
#
#   Scripts/perf/reference-edit.sh 6|20|60 [--no-open] [--no-build]
#   Scripts/perf/reference-edit.sh 6|20|60 --dev [--fresh]
#
# Writes "Reference Edit <N> min.photonz" under the reference edit's folder
# (~/Library/Caches/Photonz Reference Edit, or $PHOTONZ_REFERENCE_EDIT_DIR),
# its four Retina screen recordings and its music written there first, once per
# machine (a few minutes the first time), then opens it with
# Scripts/probe-app.sh. The project is written fresh every run, so nothing saved
# into it last time carries over. A walk reaches the same edit with
# "setup": { "referenceEdit": 6 }.
#
# --dev opens it in Photonz Dev instead, the app a person reviews in, and never
# builds, signs, quits or relaunches that app: it only asks macOS to open a
# file in it (`open -a`), launching it if it is not running. The person gets
# their own copy, "<folder>/Photonz Dev/Reference Edit <N> min.photonz", so a
# walk rewriting the walks' copy never pulls a project out from under an open
# window, and an edit saved into it is theirs. The walks' copy is written only
# if this Mac has never had it; the person's copy is made from it once, and made
# again only when the edit itself has changed and nothing was saved into the
# copy since (--fresh makes it again regardless). The dashboard's "Open in
# Photonz Dev" button on a report's try step runs exactly this, so a report
# never has to ask anybody to run a script. With the copy made once, File >
# Open reaches the same file (Cmd-Shift-G and paste the path it prints).
#
# PHOTONZ_DEV_APP points --dev at another bundle and PHOTONZ_OPEN_IN_BACKGROUND=1
# opens it without bringing it forward: both are for checking this script
# against the probe, never for a person.
set -euo pipefail
cd "$(dirname "$0")/../.."

MINUTES=""
OPEN=1
BUILD=1
DEV=0
FRESH=0
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN=0 ;;
    --no-build) BUILD=0 ;;
    --dev) DEV=1 ;;
    --fresh) FRESH=1 ;;
    6|20|60) MINUTES="$arg" ;;
    *) echo "usage: $0 6|20|60 [--no-open] [--no-build] | 6|20|60 --dev [--fresh]" >&2; exit 2 ;;
  esac
done
[[ -n "$MINUTES" ]] || { echo "usage: $0 6|20|60 [--no-open] [--no-build] | 6|20|60 --dev [--fresh]" >&2; exit 2; }

FOLDER="${PHOTONZ_REFERENCE_EDIT_DIR:-$HOME/Library/Caches/Photonz Reference Edit}"
NAME="Reference Edit ${MINUTES} min.photonz"

# Writes the walks' copy with ReferenceEditTool and prints its path.
write_edit() {
  if (( BUILD )); then
    swift build --product ReferenceEditTool 2>&1 | grep -E "error|warning: unre" >&2 || true
  fi
  local tool
  tool="$(swift build --show-bin-path)/ReferenceEditTool"
  [[ -x "$tool" ]] || { echo "!! $tool was not built" >&2; exit 1; }
  echo "==> Writing the ${MINUTES} minute reference edit" >&2
  local out
  out="$("$tool" "$MINUTES" | tee /dev/stderr)"
  printf '%s\n' "$out" | tail -1
}

if (( DEV )); then
  APP="${PHOTONZ_DEV_APP:-dist/Photonz Dev.app}"
  [[ -d "$APP" ]] || { echo "!! There is no $APP on this Mac to open the edit in." >&2; exit 1; }
  APP="$(cd "$APP" && pwd)"   # open -a takes a name or a whole path, never a relative one
  SOURCE="$FOLDER/$NAME"
  if [[ ! -f "$SOURCE/document.json" ]]; then
    SOURCE="$(write_edit)"
  fi
  [[ -f "$SOURCE/document.json" ]] || { echo "!! No project at $SOURCE" >&2; exit 1; }

  COPIES="$FOLDER/Photonz Dev"
  COPY="$COPIES/$NAME"
  # What the copy's document was when it was made, so a copy somebody has
  # saved into is never overwritten.
  STAMP="$COPIES/.$NAME.made-from"
  sum() { shasum -a 256 "$1" | cut -d' ' -f1; }
  source_sum="$(sum "$SOURCE/document.json")"
  make_copy=0
  if [[ ! -f "$COPY/document.json" ]] || (( FRESH )); then
    make_copy=1
  elif [[ -f "$STAMP" ]] && [[ "$(sum "$COPY/document.json")" == "$(cat "$STAMP")" ]] \
       && [[ "$source_sum" != "$(cat "$STAMP")" ]]; then
    make_copy=1   # untouched since it was made, and the edit itself has changed
  fi
  if (( make_copy )); then
    mkdir -p "$COPIES"
    rm -rf "$COPY"
    cp -R "$SOURCE" "$COPY"
    printf '%s\n' "$source_sum" > "$STAMP"
    echo "==> Made your copy of the ${MINUTES} minute reference edit"
  elif [[ "$(sum "$COPY/document.json")" != "$(cat "$STAMP" 2>/dev/null)" ]]; then
    echo "==> Kept your copy: it has been saved into since it was made (--fresh starts it over)"
  fi
  if (( OPEN )); then
    flags=(-a "$APP")
    [[ "${PHOTONZ_OPEN_IN_BACKGROUND:-0}" == 1 ]] && flags=(-g "${flags[@]}")
    open "${flags[@]}" "$COPY"
    echo "==> Opened in $(basename "$APP" .app): $COPY"
  else
    echo "$COPY"
  fi
  exit 0
fi

PROJECT="$(write_edit)"
[[ -d "$PROJECT" ]] || { echo "!! No project at $PROJECT" >&2; exit 1; }

if (( OPEN )); then
  if (( BUILD )); then
    Scripts/probe-app.sh "$PROJECT"
  else
    Scripts/probe-app.sh --no-build "$PROJECT"
  fi
fi
