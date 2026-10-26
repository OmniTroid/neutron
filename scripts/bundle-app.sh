#!/bin/bash
# Builds build/Neutron.app (with the Wine runtime) and build/Neutron.dmg, versioned $NEUTRON_VERSION.
# Signs with the "Developer ID Application" certificate of $NEUTRON_TEAM_ID when it is in the keychain
# (ad-hoc otherwise), and notarizes when the notarytool keychain profile $NEUTRON_NOTARY_PROFILE exists.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEAM_ID=${NEUTRON_TEAM_ID:-YNRVHH9NWL}
NOTARY_PROFILE=${NEUTRON_NOTARY_PROFILE:-neutron}
VERSION=${NEUTRON_VERSION:-0.2.1}
BUILD=${NEUTRON_BUILD:-$(git -C "$ROOT" rev-list --count HEAD)}
FEED_URL="https://github.com/OmniTroid/neutron/releases/download/updates/appcast.xml"
SPARKLE_PUBLIC_KEY="itatJhi2cn8+3UPw9dscTpQ8D84gG/65k4hGGZPet3s="
APP="$ROOT/build/Neutron.app"
DMG="$ROOT/build/Neutron.dmg"
ICONSET="$ROOT/build/AppIcon.iconset"
ENTITLEMENTS="$ROOT/scripts/Neutron.entitlements"

[ -x "$ROOT/dist/wine/bin/wine" ] || { echo "dist/ missing, run scripts/build.sh first" >&2; exit 1; }
swift build -c release --product NeutronApp --package-path "$ROOT"
swift build -c release --product neutron --package-path "$ROOT"

rm -rf "$APP" "$ICONSET" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$APP/Contents/SharedSupport" \
    "$APP/Contents/Frameworks" "$ICONSET"
cp "$ROOT/.build/release/NeutronApp" "$APP/Contents/MacOS/Neutron"
ditto "$ROOT/.build/out/Products/Release/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/.build/release/neutron" "$APP/Contents/Helpers/neutron"
ditto "$ROOT/dist" "$APP/Contents/SharedSupport/dist"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
ditto "$ROOT/licenses" "$APP/Contents/Resources/licenses"
# some upstream license files are read-only, which Sparkle flags when building updates
chmod -R u+w,a+r "$APP/Contents/Resources/LICENSE" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/licenses"

swift "$ROOT/tools/make-icon.swift" "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Neutron</string>
    <key>CFBundleDisplayName</key><string>Neutron</string>
    <key>CFBundleIdentifier</key><string>dev.neutron.Neutron</string>
    <key>CFBundleExecutable</key><string>Neutron</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application: .*($TEAM_ID)" | head -1 | awk -F'"' '{print $2}' || true)
SIGN_PLAIN=(codesign --force --options runtime)
if [ -n "$IDENTITY" ]; then
    SIGN_PLAIN+=(--timestamp --sign "$IDENTITY")
    echo "signing as $IDENTITY"
else
    SIGN_PLAIN+=(--sign -)
    echo "no Developer ID Application certificate for team $TEAM_ID in the keychain, signing ad-hoc"
fi

SIGN=("${SIGN_PLAIN[@]}" --entitlements "$ENTITLEMENTS")

# inside-out: Sparkle's helpers and framework (without Wine's entitlements), every nested Mach-O,
# then the helper, then the app
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN_PLAIN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
"${SIGN_PLAIN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
"${SIGN_PLAIN[@]}" "$SPARKLE/Autoupdate"
"${SIGN_PLAIN[@]}" "$SPARKLE/Updater.app"
"${SIGN_PLAIN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
find "$APP/Contents/SharedSupport" -type f -print0 | while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q "Mach-O"; then
        "${SIGN[@]}" "$file" 2>&1 | grep -v "replacing existing signature" || true
    fi
done
"${SIGN[@]}" "$APP/Contents/Helpers/neutron"
"${SIGN[@]}" "$APP"
codesign --verify --strict --deep "$APP"

notarize() {
    local result
    result=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
    [ "$(plutil -extract status raw - <<< "$result")" = "Accepted" ] || { echo "notarization failed: $result" >&2; exit 1; }
}

NOTARIZE=false
if [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    NOTARIZE=true
elif [ -n "$IDENTITY" ]; then
    echo "not notarized: create the profile once with"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id $TEAM_ID"
fi

# the app is stapled before it goes into the DMG so it also launches offline once copied out
if $NOTARIZE; then
    ZIP="$ROOT/build/Neutron-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    xcrun stapler staple "$APP"
    rm "$ZIP"
fi

hdiutil create -volname Neutron -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
if $NOTARIZE; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
fi
echo "built $APP and $DMG (version $VERSION, build $BUILD)"
