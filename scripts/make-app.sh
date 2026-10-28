#!/bin/zsh
# Crea il bundle .app a partire da un eseguibile.
# Uso: scripts/make-app.sh <eseguibile> <percorso.app> <versione>
set -euo pipefail
BIN="$1"; APP="$2"; VERSION="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Taggo"
cp "$ROOT/HOW_TO_USE.md" "$APP/Contents/Resources/"

# Icona: Resources/AppIcon.icns, oppure Resources/AppIcon.png (1024×1024) convertita al volo.
ICON_KEY=""
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
elif [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
    SET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$SET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ROOT/Resources/AppIcon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ROOT/Resources/AppIcon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] && ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Taggo</string>
    <key>CFBundleDisplayName</key><string>Taggo</string>
    <key>CFBundleIdentifier</key><string>com.marioansaldi.taggo</string>
    <key>CFBundleExecutable</key><string>Taggo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Taggo usa TagLib (LGPL 2.1 / MPL 1.1).</string>
    $ICON_KEY
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.audio</string><string>public.folder</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
