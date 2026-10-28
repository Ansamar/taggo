#!/bin/zsh
# Compila TagLib come libreria universale (arm64 + x86_64) per la release.
# Risultato in .vendor/taglib (header in include/, dylib in lib/).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=2.3.2
VENDOR="$PWD/.vendor"
PREFIX="$VENDOR/taglib"
[[ -f "$PREFIX/lib/libtag_c.dylib" ]] && { echo "TagLib già compilata in $PREFIX"; exit 0; }

mkdir -p "$VENDOR/src"
TARBALL="$VENDOR/src/taglib-$VERSION.tar.gz"
if [[ ! -f "$TARBALL" ]]; then
    curl -L -o "$TARBALL" "https://taglib.org/releases/taglib-$VERSION.tar.gz"
fi
rm -rf "$VENDOR/src/taglib-$VERSION" "$VENDOR/build"
tar -xzf "$TARBALL" -C "$VENDOR/src"

UTFCPP="$(brew --prefix utf8cpp 2>/dev/null || true)"
cmake -S "$VENDOR/src/taglib-$VERSION" -B "$VENDOR/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_INSTALL_NAME_DIR="@rpath" \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_BINDINGS=ON \
    -DWITH_ZLIB=ON \
    ${UTFCPP:+-DCMAKE_PREFIX_PATH="$UTFCPP"}
cmake --build "$VENDOR/build" -j "$(sysctl -n hw.ncpu)"
cmake --install "$VENDOR/build"
lipo -info "$PREFIX/lib/libtag_c.dylib"
