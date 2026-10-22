#!/bin/bash
# The picture-model try (queue task try-drawing-with-a-local-picture-model-then-turn):
# sets up a Python environment with mflux (MIT) and vtracer (MIT) once, then
# serves Z-Image Turbo (Apache 2.0, about 11 GB, downloaded on first use) on
# 127.0.0.1:8793 for Ask to draw with when "Ask paints its drawings" is on.
#
#   Scripts/picture-model/serve.sh            # serve until stopped
#   Scripts/picture-model/serve.sh --remove   # delete the environment and the model
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$HOME/.cache/photonz-picture-model"
VENV="$HOME_DIR/venv"
MODEL="${PHOTONZ_PICTURE_MODEL:-mflux-community/z-image-turbo-mflux-q8}"

if [[ "${1:-}" == "--remove" ]]; then
  rm -rf "$HOME_DIR" "$HOME/.cache/huggingface/hub/models--${MODEL//\//--}"
  echo "Removed the picture model and its environment."
  exit 0
fi

if [[ ! -x "$VENV/bin/python" ]]; then
  command -v uv >/dev/null || { echo "Needs uv: brew install uv" >&2; exit 1; }
  mkdir -p "$HOME_DIR"
  uv venv --python 3.12 "$VENV"
  # Pillow 13 needs a newer Python than 3.12 for its typing module.
  VIRTUAL_ENV="$VENV" uv pip install mflux vtracer numpy "pillow<13"
fi

exec "$VENV/bin/python" -I "$HERE/server.py"
