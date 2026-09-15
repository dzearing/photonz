#!/bin/bash
# Re-vendors libwebp into Vendor/libwebp from the pinned upstream release.
#
# This is the whole update story for Photonz's only third-party dependency:
# bump LIBWEBP_VERSION and LIBWEBP_SHA256 below, run this, build, run the tests.
# Nothing else in the repo knows the version number.
#
# Only the ENCODER is vendored, because reading a WebP already works through
# ImageIO and must keep doing so. Only the generic C, NEON and SSE2 kernels come
# across: the app is arm64 (NEON is baseline there), and SSE2 is baseline on
# x86_64, so a build on either machine links without per-file compiler flags.
set -euo pipefail
cd "$(dirname "$0")/.."

LIBWEBP_VERSION="1.5.0"
LIBWEBP_SHA256="7d6fab70cf844bf6769077bd5d7a74893f8ffd4dfb42861745750c63c2a5c92c"
URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${LIBWEBP_VERSION}.tar.gz"

DEST="Vendor/libwebp"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading libwebp ${LIBWEBP_VERSION}"
curl -fsSL --max-time 300 -o "$WORK/libwebp.tar.gz" "$URL"

echo "==> Verifying checksum"
GOT="$(shasum -a 256 "$WORK/libwebp.tar.gz" | awk '{print $1}')"
if [[ "$GOT" != "$LIBWEBP_SHA256" ]]; then
  echo "checksum mismatch: expected $LIBWEBP_SHA256, got $GOT" >&2
  exit 1
fi

tar xzf "$WORK/libwebp.tar.gz" -C "$WORK"
SRC="$WORK/libwebp-${LIBWEBP_VERSION}"

echo "==> Replacing $DEST"
rm -rf "$DEST"
mkdir -p "$DEST/src/webp" "$DEST/src/dec" "$DEST/src/dsp" "$DEST/src/enc" \
         "$DEST/src/utils" "$DEST/sharpyuv"

# What the licence asks travels with the binary, plus the extra patent grant
# Google ships beside it.
cp "$SRC/COPYING" "$SRC/PATENTS" "$SRC/AUTHORS" "$DEST/"

# Public headers. These become the CWebP module, so only the ones an encoder
# caller needs are here; they include each other with ./ paths and stand alone.
for h in types.h encode.h decode.h format_constants.h mux_types.h; do
  cp "$SRC/src/webp/$h" "$DEST/src/webp/$h"
done

# Decoder headers only: the shared dsp and lossless code declares against them.
for h in common_dec.h vp8_dec.h vp8i_dec.h vp8li_dec.h webpi_dec.h; do
  cp "$SRC/src/dec/$h" "$DEST/src/dec/$h"
done

DSP_HEADERS="cpu.h dsp.h lossless.h lossless_common.h quant.h yuv.h neon.h common_sse2.h"
DSP_COMMON="alpha_processing.c cpu.c dec.c dec_clip_tables.c filters.c lossless.c \
            rescaler.c upsampling.c yuv.c"
DSP_ENC="cost.c enc.c lossless_enc.c ssim.c"
DSP_NEON="alpha_processing_neon.c dec_neon.c filters_neon.c lossless_neon.c \
          rescaler_neon.c upsampling_neon.c yuv_neon.c cost_neon.c enc_neon.c \
          lossless_enc_neon.c"
DSP_SSE2="alpha_processing_sse2.c dec_sse2.c filters_sse2.c lossless_sse2.c \
          rescaler_sse2.c upsampling_sse2.c yuv_sse2.c cost_sse2.c enc_sse2.c \
          lossless_enc_sse2.c ssim_sse2.c"
for f in $DSP_HEADERS $DSP_COMMON $DSP_ENC $DSP_NEON $DSP_SSE2; do
  cp "$SRC/src/dsp/$f" "$DEST/src/dsp/$f"
done

cp "$SRC"/src/enc/*.c "$SRC"/src/enc/*.h "$DEST/src/enc/"
cp "$SRC"/src/utils/*.c "$SRC"/src/utils/*.h "$DEST/src/utils/"
cp "$SRC"/sharpyuv/*.c "$SRC"/sharpyuv/*.h "$DEST/sharpyuv/"

cat > "$DEST/VERSION" <<EOF
libwebp ${LIBWEBP_VERSION}
$URL
sha256 ${LIBWEBP_SHA256}

Vendored by Scripts/vendor-libwebp.sh. Do not edit these files by hand: to
update, change the version and checksum in that script and run it.
EOF

# The licence asks that the notice travel with the binary, so it is compiled
# into the app rather than copied beside it: Scripts/build-app.sh assembles the
# bundle from the executable alone, and a file in Resources would never ship.
python3 Scripts/make-open-source-notices.py "$DEST" "$LIBWEBP_VERSION" \
    Sources/Photonz/OpenSourceNotices.swift

FILES="$(find "$DEST" -type f | wc -l | tr -d ' ')"
echo "==> Vendored $FILES files into $DEST"
