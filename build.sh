#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="/Users/hosseinsamani/Applications/Aether.app"

cd "$DIR"
swiftc -O -o AetherGUI main.swift

mkdir -p "$APP/Contents/MacOS"
cp AetherGUI "$APP/Contents/MacOS/Aether"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Aether</string>
    <key>CFBundleDisplayName</key><string>Aether</string>
    <key>CFBundleIdentifier</key><string>com.cluvex.aethergui</string>
    <key>CFBundleExecutable</key><string>Aether</string>
    <key>CFBundleVersion</key><string>2.3.0</string>
    <key>CFBundleShortVersionString</key><string>2.3.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# ad-hoc sign so it doesn't get killed on first launch
codesign --force --sign - "$APP" 2>/dev/null || true

echo "built: $APP"
