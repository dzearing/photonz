#!/bin/bash
# Builds the Photonz app bundle (arm64 release) into dist/.
#
# Usage: Scripts/build-app.sh [--probe|--dmg|--dmg-only]
#   --probe     build the task loop's own bundle instead of the dev one
#   --dmg       also produce dist/Photonz.dmg
#   --dmg-only  skip the build and package the EXISTING dist/Photonz.app into
#               the DMG — the release pipeline uses this after notarizing and
#               stapling the app, so the DMG contains the stapled bundle
#
# Variants — three bundles must coexist on one machine, each with its own
# bundle id so each holds its own TCC grants / defaults / LaunchServices
# identity:
#   dev (default)        → "dist/Photonz Dev.app", bundle id
#                          com.dzearing.photonz.dev, display name "Photonz (Dev)".
#                          Runs side by side with the installed release app, and
#                          a release re-sign can never invalidate the dev Screen
#                          Recording grant again (the 2026-07-07 prompt-loop bug).
#                          This is the app a PERSON uses; see the playtest guard
#                          below for why it is not always rebuildable.
#   probe (--probe)      → "dist/Photonz Probe.app", com.dzearing.photonz.probe,
#                          display name "Photonz (Probe)". The unmanned task loop
#                          builds and relaunches THIS one to check its own work,
#                          as often as it likes, because nobody is using it.
#                          Prefer Scripts/probe-app.sh, which builds, relaunches
#                          and reports in one step.
#   release              → dist/Photonz.app, com.dzearing.photonz. Chosen when
#                          CODESIGN_IDENTITY is set (CI) or a DMG is requested
#                          (a DMG is always a release artifact; the local release
#                          preflight runs `--dmg` without the identity).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
DIST="dist"

if [[ -n "${CODESIGN_IDENTITY:-}" || "${1:-}" == "--dmg" || "${1:-}" == "--dmg-only" ]]; then
  VARIANT="release"
  APP_NAME="Photonz"
  DISPLAY_NAME="Photonz"
  BUNDLE_ID="com.dzearing.photonz"
elif [[ "${1:-}" == "--probe" ]]; then
  VARIANT="probe"
  APP_NAME="Photonz Probe"
  DISPLAY_NAME="Photonz (Probe)"
  BUNDLE_ID="com.dzearing.photonz.probe"
else
  VARIANT="dev"
  APP_NAME="Photonz Dev"
  DISPLAY_NAME="Photonz (Dev)"
  BUNDLE_ID="com.dzearing.photonz.dev"
fi
APP="$DIST/$APP_NAME.app"

# Playtest guard. While queue/playtest.lock exists someone is using
# "dist/Photonz Dev.app" right now, and rebuilding it under them ends their
# session AND makes macOS re-ask for Screen Recording, because a screen-capture
# client whose binary changed has to be re-authorized. This has bitten a real
# session, so it is enforced here rather than left to whoever remembers.
# The probe and release variants are untouched by this: they are different
# bundles that nobody is playtesting.
LOCK="queue/playtest.lock"
if [[ "$VARIANT" == "dev" && -f "$LOCK" && -z "${PHOTONZ_ALLOW_DEV_BUILD:-}" ]]; then
  cat >&2 <<GUARD
!! Refusing to rebuild "$APP": a playtest is in progress ($LOCK).

   Someone is using that exact app. Replacing its binary quits it under them
   and re-triggers the Screen Recording prompt.

   If you are the task loop and need a running app to check your work:
       Scripts/probe-app.sh              # builds + launches "Photonz Probe.app"
       Scripts/probe-app.sh <file>       # ...and opens a file in it

   If you are the person playtesting and you DO want your app rebuilt:
       rm $LOCK                          # ends the playtest, or
       PHOTONZ_ALLOW_DEV_BUILD=1 Scripts/build-app.sh
GUARD
  exit 2
fi

make_dmg() {
  echo "==> Creating dist/Photonz.dmg"
  STAGING="$DIST/dmg-staging"
  rm -rf "$STAGING" "$DIST/Photonz.dmg"
  mkdir -p "$STAGING"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "Photonz $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DIST/Photonz.dmg"
  rm -rf "$STAGING"
}

if [[ "${1:-}" == "--dmg-only" ]]; then
  [[ -d "$APP" ]] || { echo "--dmg-only: $APP does not exist; build first" >&2; exit 1; }
  make_dmg
  echo "==> Done: $DIST/Photonz.dmg"
  exit 0
fi

echo "==> Building Photonz $VERSION ($VARIANT, arm64)"
swift build -c release --arch arm64

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# The executable carries the variant name too, so `ps`/Activity Monitor make
# unmistakable which build is running.
cp .build/arm64-apple-macosx/release/Photonz "$APP/Contents/MacOS/$APP_NAME"

# Only the shipping and dev bundles EXPORT the .photonz type. The probe is a
# throwaway the loop rebuilds all day; letting a third claimant into the
# default-handler race could hand a person's own files to it. It still DECLARES
# the document types, which is what `open -a "Photonz Probe.app" <file>` needs.
if [[ "$VARIANT" == "probe" ]]; then
  EXPORTED_TYPES=""
else
  EXPORTED_TYPES=$(cat <<'TYPES'
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>com.photonz.document</string>
            <key>UTTypeDescription</key><string>Photonz Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>com.apple.package</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>photonz</string>
                </array>
            </dict>
        </dict>
    </array>
TYPES
)
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 David Zearing. MIT License.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <!-- Screen recording (phase 12): TCC requires a microphone usage string when
         the user opts to record mic audio, or the app is killed on first access. -->
    <key>NSMicrophoneUsageDescription</key><string>Photonz records microphone audio when you include it in a screen recording.</string>
    <!-- Resident menu-bar agent (phase 11): no Dock icon; stays alive with no
         editor window open. AppCoordinator also sets .accessory at runtime so
         plain `swift build` dev runs behave the same. -->
    <key>LSUIElement</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Image</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.png</string>
                <string>public.jpeg</string>
                <string>public.tiff</string>
                <string>public.heic</string>
                <string>com.compuserve.gif</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Photonz Document</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSTypeIsPackage</key><true/>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.photonz.document</string>
            </array>
        </dict>
    </array>
${EXPORTED_TYPES}
</dict>
</plist>
PLIST

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Signing priority:
#  1. Developer ID (CODESIGN_IDENTITY set) — CI/release. Hardened runtime +
#     secure timestamp are notarization requirements.
#  2. "Photonz Dev" self-signed identity — stable local signature so TCC
#     permissions (Screen Recording) survive rebuilds. Auto-created on the first
#     dev build (keychain-wide, shared by every worktree). See
#     Scripts/dev-codesign-setup.sh.
#  3. Ad-hoc — last resort only if the identity can't be created (e.g. no
#     openssl@3); permissions reset every rebuild.
DEV_IDENTITY="Photonz Dev"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> Codesigning (Developer ID)"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  # Self-heal: a fresh machine/worktree won't have the stable dev cert yet.
  # Create it once rather than ad-hoc signing (which changes the code identity
  # every build and forces re-granting Screen Recording). The cert lives in the
  # login keychain, so all worktrees on this machine share it thereafter.
  if ! security find-identity -p codesigning 2>/dev/null | grep -q "$DEV_IDENTITY"; then
    echo "==> '$DEV_IDENTITY' signing identity missing — creating it once…"
    "$(dirname "$0")/dev-codesign-setup.sh" || echo "    (setup failed — ad-hoc signing this build)"
  fi
  if security find-identity -p codesigning 2>/dev/null | grep -q "$DEV_IDENTITY"; then
    echo "==> Codesigning (stable self-signed: $DEV_IDENTITY)"
    codesign --force --deep --sign "$DEV_IDENTITY" "$APP"
  else
    echo "==> Codesigning (ad-hoc — stable identity unavailable; Screen Recording resets each build)"
    codesign --force --deep --sign - "$APP"
  fi
fi

if [[ "${1:-}" == "--dmg" ]]; then
  make_dmg
fi

echo "==> Done: $APP"
