#!/usr/bin/env bash
# Build a real Qnote.app bundle you can keep and launch like any Mac app.
# Locally compiled and unsigned is fine: Gatekeeper only quarantines downloaded apps.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP="Qnote.app"
BIN=".build/${CONFIG}/Qnote"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Qnote"

# QnoteCore ships the LeetCode snapshot in a SwiftPM resource bundle. Inside an app,
# Bundle.module looks under Bundle.main.resourceURL, so the bundle has to travel along
# or every problem reference resolves as unknown.
RESOURCE_BUNDLE=".build/${CONFIG}/Qnote_QnoteCore.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
  echo "error: $RESOURCE_BUNDLE is missing; QnoteCore resources would not ship" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Qnote</string>
  <key>CFBundleDisplayName</key><string>Qnote</string>
  <key>CFBundleIdentifier</key><string>dev.twango.qnote</string>
  <key>CFBundleVersion</key><string>2.1.0</string>
  <key>CFBundleShortVersionString</key><string>2.1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Qnote</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHumanReadableCopyright</key><string>Qnote</string>
</dict>
</plist>
PLIST

echo "Built $APP"
