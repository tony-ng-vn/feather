#!/usr/bin/env bash
# Build a real Feather.app bundle you can keep and launch like any Mac app.
# Locally compiled and unsigned is fine: Gatekeeper only quarantines downloaded apps.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP="Feather.app"
BIN=".build/${CONFIG}/Feather"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Feather"

# FeatherCore ships the LeetCode snapshot in a SwiftPM resource bundle. Inside an app,
# Bundle.module looks under Bundle.main.resourceURL, so the bundle has to travel along
# or every problem reference resolves as unknown.
RESOURCE_BUNDLE=".build/${CONFIG}/Feather_FeatherCore.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
  echo "error: $RESOURCE_BUNDLE is missing; FeatherCore resources would not ship" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Feather</string>
  <key>CFBundleDisplayName</key><string>Feather</string>
  <key>CFBundleIdentifier</key><string>dev.twango.feather</string>
  <key>CFBundleVersion</key><string>2.0.0</string>
  <key>CFBundleShortVersionString</key><string>2.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Feather</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHumanReadableCopyright</key><string>Feather</string>
</dict>
</plist>
PLIST

echo "Built $APP"
