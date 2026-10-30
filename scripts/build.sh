#!/bin/bash
# Builds dist/: Wine (external/wine) as dist/wine and DXMT (external/dxmt) as dist/overlays/dxmt, from whatever the
# submodules have checked out (`git submodule update` returns them to the pins). WINE_SRC / DXMT_SRC instead take a
# local checkout, a ref of the submodule's remote, or <git URL>#<ref>.
# Needs Homebrew bison, meson, ninja, cmake, mingw-w64, freetype, gnutls and sdl2 (headers), and Xcode's Metal toolchain.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/versions.env"
B="$ROOT/build"

# Source tree for submodule $1, given override $2: a local checkout is used as is; a ref, or <git URL>#<ref>,
# is checked out in the submodule itself, so the build stays incremental
source_tree() {
    local name=$1 spec=$2 sub="$ROOT/external/$1"
    if [ -d "$spec" ]; then (cd "$spec" && pwd); return; fi
    if [ ! -e "$sub/.git" ]; then
        git -C "$ROOT" submodule update -q --init --recursive "external/$name" >&2 || return 1
    fi
    if [ -n "$spec" ]; then
        local remote=origin ref=$spec
        case $spec in *#*) remote=${spec%#*} ref=${spec##*#} ;; esac
        git -C "$sub" fetch -q "$remote" "$ref" >&2 || return 1
        git -C "$sub" checkout -q --detach FETCH_HEAD >&2 || return 1
        git -C "$sub" submodule update -q --init --recursive >&2 || return 1
    fi
    echo "$sub"
}
WINE_SRC=$(source_tree wine "${WINE_SRC:-}")
DXMT_SRC=$(source_tree dxmt "${DXMT_SRC:-}")
echo "wine: $WINE_SRC ($(git -C "$WINE_SRC" rev-parse --short HEAD))"
echo "dxmt: $DXMT_SRC ($(git -C "$DXMT_SRC" rev-parse --short HEAD))"
DIST="$ROOT/dist"
JOBS=$(sysctl -n hw.ncpu)
BREW=$(brew --prefix)
export PATH="$BREW/opt/bison/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0

fetch() {
    local url=$1 sha=$2 out=$3
    mkdir -p "$(dirname "$out")"
    [ -f "$out" ] || { curl -fL --retry 3 -o "$out.part" "$url" && mv "$out.part" "$out"; }
    echo "$sha  $out" | shasum -a 256 -c - >/dev/null
}

xcrun -sdk macosx -f metal >/dev/null || { echo "install Xcode's Metal toolchain: xcodebuild -downloadComponent MetalToolchain"; exit 1; }

fetch "$HOSTLIBS_URL" "$HOSTLIBS_SHA256" "$B/dl/$(basename "$HOSTLIBS_URL")"
fetch "$WINE_MONO_URL" "$WINE_MONO_SHA256" "$B/dl/addons/$(basename "$WINE_MONO_URL")"
fetch "$WINE_GECKO32_URL" "$WINE_GECKO32_SHA256" "$B/dl/addons/$(basename "$WINE_GECKO32_URL")"
fetch "$WINE_GECKO64_URL" "$WINE_GECKO64_SHA256" "$B/dl/addons/$(basename "$WINE_GECKO64_URL")"

# Host libraries; the build's copies get absolute install names so tools run during the build find them
HOSTLIBS="$B/hostlibs"
if [ ! -f "$HOSTLIBS/.done" ]; then
    rm -rf "$HOSTLIBS" "$B/unpack" && mkdir -p "$HOSTLIBS" "$B/unpack"
    tar -xJf "$B/dl/$(basename "$HOSTLIBS_URL")" -C "$B/unpack"
    ditto "$B/unpack/"*.app/Contents/Resources/wine/lib "$HOSTLIBS/lib"
    rm -rf "$HOSTLIBS/lib/wine" "$B/unpack"
    rm -rf "$HOSTLIBS/build" && ditto "$HOSTLIBS/lib" "$HOSTLIBS/build"
    for lib in freetype gnutls SDL2; do
        real=$(readlink -f "$HOSTLIBS/build/lib$lib.dylib")
        install_name_tool -id "$real" "$real" 2>/dev/null
        codesign -f -s - "$real" 2>/dev/null
    done
    touch "$HOSTLIBS/.done"
fi

# Wine, with one object directory per source tree so switching trees stays incremental
OBJ="$B/wine-obj"
[ "$WINE_SRC" = "$ROOT/external/wine" ] || OBJ="$B/wine-obj-$(echo "$WINE_SRC" | shasum | cut -c1-8)"
WINE_INSTALL="$B/wine-install"
if [ ! -f "$OBJ/Makefile" ] || [ "$WINE_SRC/wine/configure" -nt "$OBJ/Makefile" ] \
    || ! grep -qx "srcdir = $WINE_SRC/wine" "$OBJ/Makefile"; then
    rm -rf "$OBJ" && mkdir -p "$OBJ"
    (cd "$OBJ" && "$WINE_SRC/wine/configure" -q CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
        --host=x86_64-apple-darwin --enable-archs=i386,x86_64 --with-mingw --prefix="$WINE_INSTALL" \
        --without-x --without-alsa --without-capi --with-coreaudio --without-cups --without-dbus --without-fontconfig \
        --without-gphoto --without-gstreamer --without-krb5 --without-netapi --without-oss --without-pulse --without-sane \
        --without-udev --without-usb --without-v4l2 --without-pcap --without-opencl --without-inotify --without-ffmpeg \
        --with-freetype --with-gnutls --with-sdl --with-vulkan \
        ac_cv_lib_soname_SDL2=libSDL2-2.0.0.dylib ac_cv_lib_soname_freetype=libfreetype.6.dylib \
        ac_cv_lib_soname_gnutls=libgnutls.30.dylib ac_cv_lib_soname_vulkan=libvulkan.1.dylib \
        FREETYPE_CFLAGS="-I$BREW/include/freetype2" FREETYPE_LIBS="-L$HOSTLIBS/build -lfreetype" \
        GNUTLS_CFLAGS="-I$BREW/include" GNUTLS_LIBS="-L$HOSTLIBS/build -lgnutls" \
        SDL2_CFLAGS="-I$BREW/include/SDL2" SDL2_LIBS="-L$HOSTLIBS/build -lSDL2" > configure.log)
fi
make -C "$OBJ" -j"$JOBS" -s
rm -rf "$WINE_INSTALL"
make -C "$OBJ" -s install-lib >/dev/null

# LLVM 15 for DXMT's shader compiler, built once
LLVM="$B/llvm"
if [ ! -f "$LLVM/lib/libLLVMCore.a" ]; then
    [ -d "$B/llvm-project" ] || git clone -q --depth 1 --branch "$DXMT_LLVM_VERSION" https://github.com/llvm/llvm-project.git "$B/llvm-project"
    cmake -B "$B/llvm-build" -S "$B/llvm-project/llvm" -G Ninja -DCMAKE_INSTALL_PREFIX="$LLVM" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 -DLLVM_HOST_TRIPLE=x86_64-apple-darwin -DLLVM_ENABLE_ASSERTIONS=On \
        -DLLVM_ENABLE_ZSTD=Off -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23" \
        -DLLVM_TARGETS_TO_BUILD="" -DLLVM_BUILD_TOOLS=Off -DLLVM_INCLUDE_BENCHMARKS=Off \
        -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off >/dev/null
    cmake --build "$B/llvm-build"
    cmake --install "$B/llvm-build" >/dev/null
fi

# DXMT against this Wine build, 64- and 32-bit
DX="$DXMT_SRC"
DXMT_OPTIONS=()
grep -q "'enable_d3d9'" "$DX/meson.options" 2>/dev/null && DXMT_OPTIONS+=(-Denable_d3d9=true)
rm -rf "$B/dxmt-install"
DXMT_KEY="$DX $OBJ ${DXMT_OPTIONS[*]:-}"
for arch in 64 32; do
    if [ "$(cat "$B/dxmt-build$arch/.neutron-source" 2>/dev/null)" != "$DXMT_KEY" ]; then
        rm -rf "$B/dxmt-build$arch"
        meson setup --cross-file "$DX/build-win$arch.txt" -Dnative_llvm_path="$LLVM" -Dwine_build_path="$OBJ" \
            ${DXMT_OPTIONS[@]+"${DXMT_OPTIONS[@]}"} --buildtype release --prefix "$B/dxmt-install" \
            "$B/dxmt-build$arch" "$DX" >/dev/null
        echo "$DXMT_KEY" > "$B/dxmt-build$arch/.neutron-source"
    fi
    meson compile -C "$B/dxmt-build$arch" >/dev/null
    meson install -C "$B/dxmt-build$arch" >/dev/null
done

# dist/wine: Wine plus host libraries and add-ons; dist/overlays/dxmt replaces and adds to it
rm -rf "$DIST"
mkdir -p "$DIST"
ditto "$WINE_INSTALL" "$DIST/wine"
rm -rf "$DIST/wine/include" "$DIST/wine/share/man" "$DIST/wine/share/applications"
ditto "$HOSTLIBS/lib" "$DIST/wine/lib"
mkdir -p "$DIST/wine/share/wine/mono" "$DIST/wine/share/wine/gecko"
tar -xJf "$B/dl/addons/$(basename "$WINE_MONO_URL")" -C "$DIST/wine/share/wine/mono"
tar -xJf "$B/dl/addons/$(basename "$WINE_GECKO32_URL")" -C "$DIST/wine/share/wine/gecko"
tar -xJf "$B/dl/addons/$(basename "$WINE_GECKO64_URL")" -C "$DIST/wine/share/wine/gecko"
find "$DIST/wine/lib/wine" -name '*.so' -exec strip -x {} + 2>/dev/null
find "$DIST/wine/lib/wine" \( -name '*.dll' -o -name '*.exe' -o -name '*.drv' -o -name '*.sys' \) -print0 \
    | xargs -0 -n 200 x86_64-w64-mingw32-strip --strip-debug 2>/dev/null || true

DXMT="$DIST/overlays/dxmt/lib/wine"
mkdir -p "$DXMT"
cp -R "$B/dxmt-install/"*-windows "$B/dxmt-install/x86_64-unix" "$DXMT/"
rm -f "$DXMT"/*/*.dll.a
strip -x "$DXMT/x86_64-unix/winemetal.so"
x86_64-w64-mingw32-strip --strip-debug "$DXMT"/*-windows/*.dll

echo "built $DIST"
