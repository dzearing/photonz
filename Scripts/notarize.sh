#!/bin/bash
# Notarizes and staples one artifact — an .app bundle (zipped automatically
# for submission) or a .dmg. Used twice per release: first the app (so the
# bundle users copy to /Applications carries its own ticket and launches
# clean even fully offline), then the DMG built from the stapled app.
#
# Usage: Scripts/notarize.sh <dist/Photonz.app | dist/Photonz.dmg>
# Env:   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
# Exits non-zero when notarization did not complete (caller decides policy).
set -euo pipefail
TARGET="$1"

SUBMIT="$TARGET"
CLEANUP=""
if [[ "$TARGET" == *.app ]]; then
  SUBMIT="${TARGET%.app}-notarize.zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
  CLEANUP="$SUBMIT"
fi

ok=0
for attempt in 1 2 3; do
  echo "==> Notarizing $TARGET (attempt $attempt)"
  # A perl alarm hard-kills a stalled upload after 720s (notarytool's own
  # --timeout only bounds the post-upload wait). NOT GNU `timeout`: macOS
  # runners don't have it on PATH — that's how v0.3.0 shipped unnotarized.
  if perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!"' 720 \
       xcrun notarytool submit "$SUBMIT" \
       --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
       --password "$APPLE_APP_PASSWORD" --wait --timeout 10m --verbose; then
    ok=1
    break
  fi
  echo "attempt $attempt did not complete (upload stall or timeout)"
  sleep 20
done

if [[ -n "$CLEANUP" ]]; then rm -f "$CLEANUP"; fi
if [[ "$ok" != 1 ]]; then
  echo "notarization did not complete for $TARGET" >&2
  exit 1
fi

xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
