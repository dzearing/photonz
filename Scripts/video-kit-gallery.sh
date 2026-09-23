#!/bin/bash
# Draws every piece of the video kit next to nothing but itself.
#
#   Scripts/video-kit-gallery.sh [output folder]
#
# Compiles Sources/Photonz/VideoKit/*.swift with Scripts/video-kit-gallery.swift
# and NO other app source (the gallery supplies the one seam, `kitHover`), then runs it. The pictures land in
# docs/design/mocks/shared/video-kit/ by default, where index.html puts each one
# beside the same piece drawn with the mock's CSS
# (http://127.0.0.1:8791/shared/video-kit/index.html).
#
# If this stops compiling, a kit piece has started to depend on the app, which
# is the one thing the kit is not allowed to do.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-docs/design/mocks/shared/video-kit}"
bin="$(mktemp -d)/video-kit-gallery"
trap 'rm -rf "$(dirname "$bin")"' EXIT
swiftc -parse-as-library -swift-version 6 -O \
  Sources/Photonz/VideoKit/*.swift Scripts/video-kit-gallery.swift -o "$bin"
"$bin" "$out"
