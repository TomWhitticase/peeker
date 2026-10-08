#!/bin/zsh
# Builds Peeker.app into ./build. Camera access needs a real bundle with a usage string.
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP=build/Peeker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Peeker "$APP/Contents/MacOS/Peeker"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tomwhitticase.peeker</string>
    <key>CFBundleName</key><string>Peeker</string>
    <key>CFBundleDisplayName</key><string>Peeker</string>
    <key>CFBundleExecutable</key><string>Peeker</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCameraUsageDescription</key>
    <string>Peeker watches whether you're looking at the screen. Nothing is recorded and nothing leaves your Mac. He's the only one watching.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
