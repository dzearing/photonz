#!/bin/bash
# Fetches uv (MIT), the one program Photonz ships to set up the picture model
# Ask paints with (docs/design/ask.md, "The picture model"): Settings > Ask runs
# it to build a private Python environment in Application Support, so nobody
# installs Python or anything else. From the release pinned in
# Vendor/uv/VERSION, checked against its sha256. Scripts/build-app.sh copies it
# into Contents/Helpers/PictureModel/.
#
#   Scripts/vendor-uv.sh          # prints the folder, fetching once
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PIN="$REPO/Vendor/uv/VERSION"
BUILD=$(sed -n 1p "$PIN")
URL=$(sed -n 2p "$PIN")
SUM=$(sed -n 3p "$PIN" | awk '{print $2}')
OUT="$REPO/Vendor/uv/$BUILD"

if [[ ! -x "$OUT/uv" ]]; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  echo "==> Fetching uv $BUILD" >&2
  curl -fsSL --max-time 300 -o "$WORK/uv.tar.gz" "$URL"
  GOT=$(shasum -a 256 "$WORK/uv.tar.gz" | awk '{print $1}')
  if [[ "$GOT" != "$SUM" ]]; then
    echo "!! uv $BUILD: sha256 $GOT, expected $SUM" >&2
    exit 1
  fi
  mkdir -p "$WORK/x"
  tar xzf "$WORK/uv.tar.gz" -C "$WORK/x"
  SRC=$(find "$WORK/x" -name uv -type f | head -1)
  rm -rf "$OUT"
  mkdir -p "$OUT"
  cp "$SRC" "$OUT/uv"
  chmod +x "$OUT/uv"
fi
echo "$OUT"
