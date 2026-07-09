#!/bin/bash
# Creates a stable self-signed code-signing identity ("Photonz Dev") in the
# login keychain so local/debug builds keep a CONSISTENT code signature across
# rebuilds.
#
# Why: ad-hoc signing (`codesign --sign -`) gives every build a different
# identity, so macOS TCC permissions (Screen Recording, etc.) are keyed to the
# binary's cdhash and reset on every rebuild. A stable cert makes the signature's
# *designated requirement* "identifier com.dzearing.photonz and certificate
# leaf = <this cert>", which doesn't change when the code changes — so a granted
# permission sticks build after build.
#
# Run ONCE:  Scripts/dev-codesign-setup.sh
# Then `Scripts/build-app.sh` auto-detects and uses the identity.
# To undo:   security delete-identity -c "Photonz Dev" login.keychain-db
set -euo pipefail

CERT_NAME="Photonz Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# We need a real OpenSSL 3 (Homebrew): macOS's built-in /usr/bin/openssl is
# LibreSSL, which can't do the -legacy PKCS12 export that `security import`
# requires. Prefer a Homebrew openssl@3, then any `openssl` on PATH that reports
# as OpenSSL (not LibreSSL); bail with instructions if only LibreSSL is present.
OPENSSL=""
for cand in /opt/homebrew/opt/openssl@3/bin/openssl \
            /usr/local/opt/openssl@3/bin/openssl \
            "$(command -v openssl || true)"; do
  if [[ -x "$cand" ]] && "$cand" version 2>/dev/null | grep -q "^OpenSSL"; then
    OPENSSL="$cand"; break
  fi
done
if [[ -z "$OPENSSL" ]]; then
  echo "!! Need OpenSSL 3 — the built-in LibreSSL can't export the legacy PKCS12 MAC." >&2
  echo "   Install it with:  brew install openssl@3" >&2
  exit 1
fi
echo "==> Using $("$OPENSSL" version) at $OPENSSL"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "==> '$CERT_NAME' identity already present — nothing to do."
  exit 0
fi

echo "==> Generating self-signed code-signing certificate '$CERT_NAME'"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Errors are NOT sent to /dev/null: a silent failure here is exactly what made
# this hard to diagnose. Only the RSA key-gen progress dots go to /dev/null.
"$OPENSSL" req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -subj "/CN=$CERT_NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# -legacy: macOS `security` can't read OpenSSL 3's default PKCS12 MAC.
"$OPENSSL" pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -passout pass:photonz -name "$CERT_NAME" \
  -legacy -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES

echo "==> Importing into the login keychain (codesign-only access)"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P photonz -T /usr/bin/codesign

# Let codesign use the key without a GUI prompt on every build. This needs the
# login-keychain password; if it can't be set non-interactively, codesign will
# instead ask "Always Allow" on the first build (one click, then it's fine).
echo "==> Authorizing codesign to use the key (you may be asked for your login password)"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null 2>&1 \
  || echo "    (skipped — codesign will ask 'Always Allow' on the first build)"

echo "==> Done. '$CERT_NAME' is ready; Scripts/build-app.sh will use it automatically."
