#!/bin/bash
# Build UxPlay with embedded mDNS (no Bonjour required)
# Requires MSYS2 with mingw-w64-x86_64 packages installed.
#
# Prerequisites (run in MSYS2 MinGW64 shell):
#   pacman -S --needed mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake \
#     mingw-w64-x86_64-gstreamer mingw-w64-x86_64-gst-plugins-base \
#     mingw-w64-x86_64-gst-plugins-good mingw-w64-x86_64-gst-plugins-bad \
#     mingw-w64-x86_64-gst-libav mingw-w64-x86_64-openssl \
#     mingw-w64-x86_64-libplist mingw-w64-x86_64-pkg-config

set -e

export PATH="/mingw64/bin:/usr/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist/UxPlayEnhanced"

if [ -f /mingw64/bin/python.exe ]; then
    BUILD_PYTHON="/mingw64/bin/python.exe"
elif [ -f /c/Python311/python.exe ]; then
    BUILD_PYTHON="/c/Python311/python.exe"
else
    BUILD_PYTHON="$(command -v python || command -v python.exe || true)"
fi
if [ -z "$BUILD_PYTHON" ]; then
    echo "ERROR: Python is required to apply the source patch"
    exit 1
fi

echo "=== Copying embedded mDNS source ==="
cp "$SCRIPT_DIR/src/dnssd_embedded.c" "$SCRIPT_DIR/lib/uxplay/lib/dnssd_embedded.c"

echo "=== Patching CMakeLists.txt for embedded mDNS ==="
"$BUILD_PYTHON" "$SCRIPT_DIR/patch_cmake.py"

echo "=== Configuring build ==="
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake "$SCRIPT_DIR/lib/uxplay" \
    -G "MinGW Makefiles" \
    -DUSE_EMBEDDED_MDNS=ON \
    -DNO_MARCH_NATIVE=ON \
    -DCMAKE_BUILD_TYPE=Release

echo "=== Building ==="
mingw32-make -j$(nproc)

echo "=== Packaging ==="
if [ "$DIST_DIR" != "$SCRIPT_DIR/dist/UxPlayEnhanced" ]; then
    echo "ERROR: refusing to clean unexpected package path: $DIST_DIR"
    exit 1
fi
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/lib/gstreamer-1.0"

cp "$BUILD_DIR/uxplay.exe" "$DIST_DIR/"
cp "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/LICENSE" "$DIST_DIR/"

for lib in libgstvideo-1.0-0 libgstsdp-1.0-0 libgstpbutils-1.0-0 \
           libgstaudio-1.0-0 libgsttag-1.0-0 libgstrtp-1.0-0 \
           libgstgl-1.0-0 libgstcodecparsers-1.0-0 liborc-0.4-0; do
    cp /mingw64/bin/${lib}.dll "$DIST_DIR/"
done

cp /mingw64/bin/xvidcore.dll "$DIST_DIR/"

for plugin in libgstcoreelements libgstplayback libgstvideoconvertscale \
              libgstautodetect libgstaudioconvert libgstaudioresample \
              libgstvolume libgsttypefindfunctions libgstapp \
              libgstvideoparsersbad libgstisomp4 libgstrtp libgstrtpmanager \
              libgstudp libgstopengl libgstrtsp libgstlibav \
              libgstlevel libgstaudioparsers libgstvideofilter \
              libgstd3d11 libgstwasapi2 libgstd3d12 \
              libgstdirectsound libgstwasapi \
              libgstalaw libgstmulaw libgstsubparse libgstencoding; do
    cp /mingw64/lib/gstreamer-1.0/${plugin}.dll "$DIST_DIR/lib/gstreamer-1.0/"
done

# CI can provide TRAY_PYTHON explicitly. Otherwise retain the local-build fallback.
if [ -z "${TRAY_PYTHON:-}" ]; then
    TRAY_PYTHON="/c/Python311/python.exe"
    if [ ! -f "$TRAY_PYTHON" ]; then
        TRAY_PYTHON="$(command -v python.exe || true)"
    fi
fi

echo "Tray Python: ${TRAY_PYTHON:-<none>}"
if [ -n "$TRAY_PYTHON" ] && "$TRAY_PYTHON" -m PyInstaller --version >/dev/null 2>&1; then
    echo "=== Building standalone tray launcher ==="
    ICON_ICO_WIN="$(cygpath -w "$SCRIPT_DIR/assets/UxPlayEnhanced.ico")"
    ICON_PNG_WIN="$(cygpath -w "$SCRIPT_DIR/assets/UxPlayEnhanced-icon.png")"
    "$TRAY_PYTHON" -m PyInstaller --noconfirm --clean --onefile --noconsole \
        --name UxPlayEnhanced \
        --icon "$ICON_ICO_WIN" \
        --add-data "$ICON_PNG_WIN;assets" \
        --distpath "$BUILD_DIR/tray-dist" \
        --workpath "$BUILD_DIR/tray-work" \
        --specpath "$BUILD_DIR/tray-spec" \
        "$SCRIPT_DIR/launcher/uxplay_tray.pyw"
    cp "$BUILD_DIR/tray-dist/UxPlayEnhanced.exe" "$DIST_DIR/"
else
    echo "ERROR: Windows Python with PyInstaller is required to build UxPlayEnhanced.exe"
    exit 1
fi

for launcher_file in "$SCRIPT_DIR"/launcher/*; do
    [ -f "$launcher_file" ] || continue
    cp "$launcher_file" "$DIST_DIR/"
done

"$TRAY_PYTHON" "$SCRIPT_DIR/scripts/verify_package.py" "$(cygpath -w "$DIST_DIR")" \
    --runtime-dir "$(cygpath -w /mingw64/bin)"

echo ""
echo "=== Build complete ==="
echo "Output: $DIST_DIR"
echo "Files: $(find "$DIST_DIR" -name '*.dll' | wc -l) DLLs, $(find "$DIST_DIR" -name '*.exe' | wc -l) EXE"
echo ""
echo "To use:"
echo "  1. Run setup-firewall.ps1 once; it requests Administrator access"
echo "  2. Double-click UxPlayEnhanced.bat (starts the standalone tray launcher)"
