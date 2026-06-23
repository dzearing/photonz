#!/bin/bash
# Builds Photonz.app (arm64 release) into dist/.
#
# Usage: Scripts/build-app.sh [--dmg]
#   --dmg  also produce dist/Photonz.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
DIST="dist"
APP="$DIST/Photonz.app"

echo "==> Building Photonz $VERSION (release, arm64)"
swift build -c release --arch arm64

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/Photonz "$APP/Contents/MacOS/Photonz"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Photonz</string>
    <key>CFBundleDisplayName</key><string>Photonz</string>
    <key>CFBundleIdentifier</key><string>com.dzearing.photonz</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>Photonz</string>
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
</dict>
</plist>
PLIST

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Signing priority:
#  1. Developer ID (CODESIGN_IDENTITY set) — CI/release. Hardened runtime +
#     secure timestamp are notarization requirements.
#  2. "Photonz Dev" self-signed identity, if present — stable local signature so
#     TCC permissions (Screen Recording) survive rebuilds. See
#     Scripts/dev-codesign-setup.sh.
#  3. Ad-hoc — fallback; permissions reset every rebuild.
DEV_IDENTITY="Photonz Dev"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> Codesigning (Developer ID)"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$DEV_IDENTITY"; then
  echo "==> Codesigning (stable self-signed: $DEV_IDENTITY)"
  codesign --force --deep --sign "$DEV_IDENTITY" "$APP"
else
  echo "==> Codesigning (ad-hoc — run Scripts/dev-codesign-setup.sh for stable Screen Recording permission)"
  codesign --force --deep --sign - "$APP"
fi

if [[ "${1:-}" == "--dmg" ]]; then
  echo "==> Creating dist/Photonz.dmg"
  STAGING="$DIST/dmg-staging"
  rm -rf "$STAGING" "$DIST/Photonz.dmg"
  mkdir -p "$STAGING"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "Photonz $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DIST/Photonz.dmg"
  rm -rf "$STAGING"
fi

echo "==> Done: $APP"
