#!/usr/bin/env bash
# Build a real TonyNote.app bundle you can keep and launch like any Mac app.
# Locally compiled and unsigned is fine: Gatekeeper only quarantines downloaded apps.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP="TonyNote.app"
BIN=".build/${CONFIG}/TonyNote"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TonyNote"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TonyNote</string>
  <key>CFBundleDisplayName</key><string>TonyNote</string>
  <key>CFBundleIdentifier</key><string>dev.twango.tonynote</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>TonyNote</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHumanReadableCopyright</key><string>TonyNote</string>
</dict>
</plist>
PLIST

echo "Built $APP"
