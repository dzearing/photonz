#!/bin/bash
# Fetches the model server Ask runs inside Photonz (docs/design/ask.md, "The
# model"): llama.cpp's llama-server and the libraries it loads, from the
# release pinned in Vendor/llama-server/VERSION, checked against its sha256.
# Scripts/build-app.sh copies the result into Contents/Helpers/AskModel/.
#
#   Scripts/vendor-llama-server.sh          # prints the folder, fetching once
#
# The binaries are not committed (about 30 MB that changes with every bump);
# the pin is, so every build ships the same bytes. To move to a newer release,
# change the three lines of VERSION and run this.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PIN="$REPO/Vendor/llama-server/VERSION"
BUILD=$(sed -n 1p "$PIN")
URL=$(sed -n 2p "$PIN")
SUM=$(sed -n 3p "$PIN" | awk '{print $2}')
OUT="$REPO/Vendor/llama-server/$BUILD"

# What llama-server loads (otool -L), and nothing else from the release.
FILES=(llama-server libllama-server-impl.dylib libllama-common.0.dylib libmtmd.0.dylib libllama.0.dylib
       libggml.0.dylib libggml-base.0.dylib libggml-cpu.0.dylib libggml-blas.0.dylib libggml-metal.0.dylib
       libggml-rpc.0.dylib)

complete() {
  for f in "${FILES[@]}"; do [[ -f "$OUT/$f" ]] || return 1; done
}

if ! complete; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  echo "==> Fetching llama-server $BUILD" >&2
  curl -fsSL --max-time 300 -o "$WORK/llama.tar.gz" "$URL"
  GOT=$(shasum -a 256 "$WORK/llama.tar.gz" | awk '{print $1}')
  if [[ "$GOT" != "$SUM" ]]; then
    echo "!! llama-server $BUILD: sha256 $GOT, expected $SUM" >&2
    exit 1
  fi
  mkdir -p "$WORK/x"
  tar xzf "$WORK/llama.tar.gz" -C "$WORK/x"
  SRC=$(find "$WORK/x" -maxdepth 2 -name llama-server -type f -exec dirname {} \; | head -1)
  rm -rf "$OUT"
  mkdir -p "$OUT"
  # -L: the release's .0.dylib names are links to the versioned files, and the
  # load commands name the .0 ones, so each is copied as the real file.
  for f in "${FILES[@]}"; do cp -L "$SRC/$f" "$OUT/$f"; done
fi
echo "$OUT"
