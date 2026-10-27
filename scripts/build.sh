#!/bin/bash
# Builds dist/: Wine runtimes (one per graphics backend) with the Steam bridge installed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/versions.env"
B="$ROOT/build"
DIST="$ROOT/dist"
JOBS=$(sysctl -n hw.ncpu)
export PATH="$(brew --prefix bison)/bin:$PATH"

fetch() {
    local url=$1 sha=$2 out=$3
    mkdir -p "$(dirname "$out")"
    [ -f "$out" ] || { curl -fL --retry 3 -o "$out.part" "$url" && mv "$out.part" "$out"; }
    echo "$sha  $out" | shasum -a 256 -c - >/dev/null
}

fetch "$WINE_BIN_URL" "$WINE_BIN_SHA256" "$B/dl/wine-bin/$(basename "$WINE_BIN_URL")"
fetch "$WINE_SRC_URL" "$WINE_SRC_SHA256" "$B/dl/wine-src/$(basename "$WINE_SRC_URL")"
fetch "$DXMT_URL" "$DXMT_SHA256" "$B/dl/dxmt/$(basename "$DXMT_URL")"

if [ ! -d "$B/proton" ]; then
    git clone -q --filter=blob:none --no-checkout "$PROTON_REPO" "$B/proton"
    git -C "$B/proton" sparse-checkout set --no-cone '/lsteamclient/*' '!/lsteamclient/steamworks_sdk_*' '/steam_helper/'
fi
git -C "$B/proton" cat-file -e "$PROTON_COMMIT^{commit}" 2>/dev/null || git -C "$B/proton" fetch -q origin "$PROTON_COMMIT"
git -C "$B/proton" checkout -q "$PROTON_COMMIT"

# Wine source tree with our modules added
SRC="$B/src/wine-$WINE_VERSION"
rm -rf "$SRC"
mkdir -p "$B/src"
tar -xJf "$B/dl/wine-src/$(basename "$WINE_SRC_URL")" -C "$B/src"
cp -R "$B/proton/lsteamclient" "$SRC/dlls/lsteamclient"
patch -s -d "$SRC/dlls" -p1 < "$ROOT/patches/lsteamclient-macos.patch"
patch -s -d "$SRC/dlls" -p1 < "$ROOT/patches/winemac-dxmt.patch"
mkdir -p "$SRC/programs/steam" "$SRC/dlls/steamclient"
cp "$B/proton/steam_helper/"* "$SRC/programs/steam/"
cp "$ROOT/dlls/steamclient/Makefile.in" "$SRC/dlls/steamclient/"
grep -v '^#\|^$\|-private' "$SRC/dlls/lsteamclient/lsteamclient.spec" | sed -E \
    -e 's/^([^ ]+) stub ([A-Za-z0-9_]+)$/\1 stdcall \2() lsteamclient.\2/' \
    -e 's/^([^ ]+) cdecl ([A-Za-z0-9_]+)(\(.*\))$/\1 cdecl \2\3 lsteamclient.\2/' \
    > "$SRC/dlls/steamclient/steamclient.spec"
sed -i '' \
    -e '/^wine_fn_config_makefile dlls\/lz32 enable_lz32$/a\
wine_fn_config_makefile dlls/lsteamclient enable_lsteamclient
' \
    -e '/^wine_fn_config_makefile dlls\/sti enable_sti$/a\
wine_fn_config_makefile dlls/steamclient enable_steamclient
' \
    -e '/^wine_fn_config_makefile programs\/start enable_start$/a\
wine_fn_config_makefile programs/steam enable_steam
' \
    "$SRC/configure"

OBJ="$B/wine-obj"
rm -rf "$OBJ"
mkdir -p "$OBJ"
(cd "$OBJ" && "$SRC/configure" -q CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
    --host=x86_64-apple-darwin --enable-archs=i386,x86_64 \
    --without-x --without-freetype --without-gstreamer --without-gnutls --without-sdl \
    --without-cups --without-sane --without-gphoto --without-pcap --without-usb --without-v4l2 \
    --without-krb5 --without-netapi --without-opencl --without-vulkan --without-inotify \
    --without-capi --without-ffmpeg > configure.log)
make -C "$OBJ" -j"$JOBS" -s dlls/lsteamclient/all dlls/steamclient/all programs/steam/all dlls/winemac.drv/all

# dist/wine is the base runtime (wined3d); overlays/<backend> holds files that replace or add to it
rm -rf "$DIST"
mkdir -p "$DIST/steam" "$B/unpack"
rm -rf "$B/unpack/wine"
tar -xJf "$B/dl/wine-bin/$(basename "$WINE_BIN_URL")" -C "$B/unpack"
BASE="$DIST/wine"
mv "$B/unpack/"*.app/Contents/Resources/wine "$BASE"
rm -rf "$B/unpack/"*.app
for arch in i386 x86_64; do
    cp "$OBJ/dlls/lsteamclient/$arch-windows/lsteamclient.dll" "$OBJ/programs/steam/$arch-windows/steam.exe" "$BASE/lib/wine/$arch-windows/"
done
cp "$OBJ/dlls/lsteamclient/lsteamclient.so" "$BASE/lib/wine/x86_64-unix/"
cp "$OBJ/dlls/steamclient/i386-windows/steamclient.dll" "$DIST/steam/steamclient.dll"
cp "$OBJ/dlls/steamclient/x86_64-windows/steamclient.dll" "$DIST/steam/steamclient64.dll"

DXMT="$DIST/overlays/dxmt/lib/wine"
tar -xzf "$B/dl/dxmt/$(basename "$DXMT_URL")" -C "$B/unpack"
for d in i386-windows x86_64-windows x86_64-unix; do
    mkdir -p "$DXMT/$d"
    cp "$B/unpack/$DXMT_VERSION/$d/"* "$DXMT/$d/"
done
cp "$OBJ/dlls/winemac.drv/winemac.so" "$DXMT/x86_64-unix/"

echo "built $DIST"
