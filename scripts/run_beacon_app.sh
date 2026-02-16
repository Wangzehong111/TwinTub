#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode-derived"
APP_NAME="Beacon"
EXECUTABLE_NAME="BeaconApp"
APP_BUNDLE="$ROOT_DIR/.build/${APP_NAME}.app"

xcodebuild \
  -scheme Beacon \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/dev/null

PRODUCT_DIR="$DERIVED_DATA_PATH/Build/Products/Debug"
BINARY_PATH="$PRODUCT_DIR/$EXECUTABLE_NAME"

if [ ! -x "$BINARY_PATH" ]; then
  echo "Build output not found: $BINARY_PATH" >&2
  exit 1
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.beacon.local.dev</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

open "$APP_BUNDLE"

echo "Launched: $APP_BUNDLE"
echo "Health check: curl -i http://127.0.0.1:55771/health"
