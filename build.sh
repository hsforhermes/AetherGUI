#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="/Users/hosseinsamani/Applications/Aether.app"
VERSION="0.1.1"

cd "$DIR"
swiftc -O -o AetherGUI main.swift

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AetherGUI "$APP/Contents/MacOS/Aether"

# Dock / Finder icon. Generated from assets/icon_pack/icon_color.svg by
# ./make-app-icon.sh, which round-trips the result through iconutil to verify
# all 10 resolutions are present. Re-run it if you change the source artwork.
if [ -f assets/AppIcon.icns ]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Menu-bar glyph. Generated from assets/icon_pack/icon_template.svg by
# ./make-menubar-icon.sh at 54px, so macOS never upscales it on a Retina
# display; main.swift declares it as 18x18 POINTS. Read at runtime from the
# bundle so the app falls back to the SF Symbol if the file is missing.
if [ -f assets/menubar_18.png ]; then
  cp assets/menubar_18.png "$APP/Contents/Resources/MenuBarIcon.png"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Aether</string>
    <key>CFBundleDisplayName</key><string>Aether</string>
    <key>CFBundleIdentifier</key><string>com.cluvex.aethergui</string>
    <key>CFBundleExecutable</key><string>Aether</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# ad-hoc sign so it doesn't get killed on first launch
codesign --force --sign - "$APP" 2>/dev/null || true

echo "built: $APP (v$VERSION)"
