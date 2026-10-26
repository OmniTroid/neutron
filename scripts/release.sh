#!/bin/bash
# Publishes Neutron <version>: the DMG to release v<version>, and the Sparkle archive, deltas and appcast
# to the rolling "updates" release that the app's feed URL points at.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?usage: scripts/release.sh <version>}
REPO=OmniTroid/neutron
UPDATES="$ROOT/build/updates"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
APP="$ROOT/build/Neutron.app"

[ -z "$(git -C "$ROOT" status --porcelain)" ] || { echo "commit your changes first" >&2; exit 1; }
git -C "$ROOT" fetch -q origin
[ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse @{u})" ] || { echo "push main first" >&2; exit 1; }

NEUTRON_VERSION="$VERSION" "$ROOT/scripts/bundle-app.sh"
xcrun stapler validate "$APP" >/dev/null || { echo "Neutron.app is not notarized, refusing to publish" >&2; exit 1; }
BUILD=$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)

gh release view updates --repo "$REPO" >/dev/null 2>&1 || \
    gh release create updates --repo "$REPO" --prerelease --title "Update feed" \
        --notes "Sparkle update feed for Neutron.app. Download the app from the versioned releases."

# the newest archives let generate_appcast build deltas from the versions most users are on
rm -rf "$UPDATES"
mkdir -p "$UPDATES"
for asset in $(gh release view updates --repo "$REPO" --json assets --jq '.assets[].name' \
        | grep '^Neutron-.*\.zip$' | sort -t- -k3 -n | tail -3); do
    gh release download updates --repo "$REPO" --dir "$UPDATES" --pattern "$asset"
done

ARCHIVE="$UPDATES/Neutron-$VERSION-$BUILD.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
"$SPARKLE_BIN/generate_appcast" --maximum-deltas 3 \
    --download-url-prefix "https://github.com/$REPO/releases/download/updates/" "$UPDATES"

NEW_DELTAS=$(find "$UPDATES" -name "*.delta" -newer "$ARCHIVE")
gh release upload updates --repo "$REPO" --clobber "$ARCHIVE" $NEW_DELTAS "$UPDATES/appcast.xml"

cp "$ROOT/build/Neutron.dmg" "$ROOT/build/Neutron-$VERSION.dmg"
gh release create "v$VERSION" --repo "$REPO" --target "$(git -C "$ROOT" rev-parse HEAD)" \
    --title "Neutron $VERSION" --generate-notes "$ROOT/build/Neutron-$VERSION.dmg"
echo "released Neutron $VERSION (build $BUILD)"
