#!/bin/bash
# Builds build/Neutron.app (with the Wine runtime) and build/Neutron.dmg.
# Signs with the "Developer ID Application" certificate of $NEUTRON_TEAM_ID when it is in the keychain
# (ad-hoc otherwise), and notarizes when the notarytool keychain profile $NEUTRON_NOTARY_PROFILE exists.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEAM_ID=${NEUTRON_TEAM_ID:-YNRVHH9NWL}
NOTARY_PROFILE=${NEUTRON_NOTARY_PROFILE:-neutron}
APP="$ROOT/build/Neutron.app"
DMG="$ROOT/build/Neutron.dmg"
ICONSET="$ROOT/build/AppIcon.iconset"
ENTITLEMENTS="$ROOT/scripts/Neutron.entitlements"

[ -x "$ROOT/dist/wine/bin/wine" ] || { echo "dist/ missing, run scripts/build.sh first" >&2; exit 1; }
swift build -c release --product NeutronApp --package-path "$ROOT"
swift build -c release --product neutron --package-path "$ROOT"

rm -rf "$APP" "$ICONSET" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$APP/Contents/SharedSupport" "$ICONSET"
cp "$ROOT/.build/release/NeutronApp" "$APP/Contents/MacOS/Neutron"
cp "$ROOT/.build/release/neutron" "$APP/Contents/Helpers/neutron"
ditto "$ROOT/dist" "$APP/Contents/SharedSupport/dist"

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
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application: .*($TEAM_ID)" | head -1 | awk -F'"' '{print $2}' || true)
SIGN=(codesign --force --options runtime --entitlements "$ENTITLEMENTS")
if [ -n "$IDENTITY" ]; then
    SIGN+=(--timestamp --sign "$IDENTITY")
    echo "signing as $IDENTITY"
else
    SIGN+=(--sign -)
    echo "no Developer ID Application certificate for team $TEAM_ID in the keychain, signing ad-hoc"
fi

# inside-out: every nested Mach-O, then the helper, then the app
find "$APP/Contents/SharedSupport" -type f -print0 | while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q "Mach-O"; then
        "${SIGN[@]}" "$file" 2>&1 | grep -v "replacing existing signature" || true
    fi
done
"${SIGN[@]}" "$APP/Contents/Helpers/neutron"
"${SIGN[@]}" "$APP"
codesign --verify --strict --deep "$APP"

if [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    ZIP="$ROOT/build/Neutron-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$ZIP"
elif [ -n "$IDENTITY" ]; then
    echo "not notarized: create the profile once with"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id $TEAM_ID"
fi

hdiutil create -volname Neutron -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo "built $APP and $DMG"
