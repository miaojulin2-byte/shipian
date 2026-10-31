#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/dist/拾片.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Textline "$APP/Contents/MacOS/Shipian"
swift scripts/make-icon.swift "$PWD/.build/Textline.iconset"
iconutil -c icns "$PWD/.build/Textline.iconset" -o "$APP/Contents/Resources/Textline.icns"
cp ThirdParty/Tendedero-LICENSE.txt "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Shipian</string>
<key>CFBundleIdentifier</key><string>local.textline.app</string>
<key>CFBundleName</key><string>拾片</string>
<key>CFBundleDisplayName</key><string>拾片 侧边收纳</string>
<key>CFBundleIconFile</key><string>Textline</string>
<key>CFBundleVersion</key><string>18</string>
<key>CFBundleShortVersionString</key><string>0.9.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "$APP"
