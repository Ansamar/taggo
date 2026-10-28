#!/bin/zsh
# Crea la release distribuibile: app universale (Apple Silicon + Intel) con TagLib inclusa,
# DMG, ZIP e checksum in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(cat VERSION)"
DIST="$ROOT/dist"
TAGLIB="$ROOT/.vendor/taglib/lib"

scripts/build-taglib.sh
export PKG_CONFIG_PATH="$ROOT/.vendor/taglib/lib/pkgconfig"

for arch in arm64 x86_64; do
    echo "==> Compilo per $arch"
    swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path ".build/release-$arch" \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks
done

rm -rf "$DIST"
mkdir -p "$DIST"
APP="$DIST/Taggo.app"
lipo -create -output "$DIST/Taggo" \
    .build/release-arm64/arm64-apple-macosx/release/Taggo \
    .build/release-x86_64/x86_64-apple-macosx/release/Taggo
scripts/make-app.sh "$DIST/Taggo" "$APP" "$VERSION"
rm "$DIST/Taggo"

echo "==> Includo TagLib"
FW="$APP/Contents/Frameworks"
mkdir -p "$FW"
cp "$TAGLIB/libtag.2.dylib" "$TAGLIB/libtag_c.2.dylib" "$FW/"
chmod u+w "$FW"/*.dylib
install_name_tool -id @rpath/libtag.2.dylib "$FW/libtag.2.dylib"
install_name_tool -id @rpath/libtag_c.2.dylib "$FW/libtag_c.2.dylib"
for lib in libtag.2.dylib libtag_c.2.dylib; do
    for target in "$APP/Contents/MacOS/Taggo" "$FW/libtag_c.2.dylib"; do
        old="$(otool -L "$target" | awk -v l="$lib" '$1 ~ l"$" {print $1}')"
        [[ -n "$old" && "$old" != "@rpath/$lib" ]] && install_name_tool -change "$old" "@rpath/$lib" "$target"
    done
done

# Nessun percorso di questo Mac deve restare nei binari.
if otool -L "$APP/Contents/MacOS/Taggo" "$FW"/*.dylib | grep -E "^\s" | grep -E "/Volumes/|/usr/local/|/opt/homebrew/"; then
    echo "ERRORE: riferimenti a librerie locali rimasti" >&2
    exit 1
fi

mkdir -p "$APP/Contents/Resources/Licenses"
cp .vendor/src/taglib-*/COPYING.LGPL .vendor/src/taglib-*/COPYING.MPL "$APP/Contents/Resources/Licenses/"

echo "==> Firma ad-hoc"
codesign --force --sign - "$FW"/*.dylib
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Pacchetti"
STAGE="$(mktemp -d)/Taggo"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Taggo.app"
ln -s /Applications "$STAGE/Applicazioni"
cp HOW_TO_USE.md "$STAGE/Come usare Taggo.txt"
hdiutil create -volname "Taggo $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Taggo-$VERSION.dmg" >/dev/null
ditto -c -k --keepParent "$APP" "$DIST/Taggo-$VERSION.zip"
(cd "$DIST" && shasum -a 256 "Taggo-$VERSION.dmg" "Taggo-$VERSION.zip" > SHA256SUMS.txt)

lipo -info "$APP/Contents/MacOS/Taggo"
ls -lh "$DIST"
