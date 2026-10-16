#!/bin/bash
# Fails when a signed Photonz bundle cannot use the microphone.
#
# Usage: Scripts/check-entitlements.sh <path/to/Photonz.app>
#
# A hardened runtime app (every Developer ID build, since notarization requires
# the runtime) is refused the microphone by macOS unless its signature carries
# com.apple.security.device.audio-input. The refusal is silent: no prompt, and
# the app never appears under Privacy & Security > Microphone, so the person has
# nothing to turn on. v0.17.0 shipped that way and recording with sound was
# impossible for everyone who downloaded it. build-app.sh runs this after
# signing a release bundle, and the Release workflow runs it on the bundle it
# publishes.
set -euo pipefail

APP="${1:?usage: $0 <path/to/App.app>}"
KEY="com.apple.security.device.audio-input"

[[ -d "$APP" ]] || { echo "check-entitlements: $APP does not exist" >&2; exit 1; }

ENTS="$(mktemp -t photonz-entitlements)"
trap 'rm -f "$ENTS"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENTS" 2>/dev/null || true

VALUE="$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$ENTS" 2>/dev/null || true)"
if [[ "$VALUE" != "true" ]]; then
  echo "==> FAILED: $APP is not entitled to use the microphone ($KEY)." >&2
  echo "    Under the hardened runtime macOS refuses the microphone without a" >&2
  echo "    prompt and never lists the app in Privacy & Security > Microphone," >&2
  echo "    so recording with sound is impossible. Sign it with" >&2
  echo "    --entitlements Resources/Photonz.entitlements." >&2
  exit 1
fi
echo "==> Entitlements: $KEY present"
