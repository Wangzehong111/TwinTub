#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode-derived"
APP_NAME="Beacon"
EXECUTABLE_NAME="BeaconApp"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
APP_ICON_SOURCE="/Users/wangzehong/Documents/icons/com.unofficial.smartisan.iconpack/bubei_tingshu.png"
APP_ICON_NAME="BeaconIcon"
APP_ICON_ICNS="$APP_BUNDLE/Contents/Resources/${APP_ICON_NAME}.icns"
SHOULD_OPEN=1

if [ "${1:-}" = "--no-run" ]; then
  SHOULD_OPEN=0
fi

generate_icon_icns() {
  local source_png="$1"
  local target_icns="$2"
  local iconset_dir
  iconset_dir="$(mktemp -d)"
  iconset_dir="${iconset_dir}.iconset"
  mkdir -p "$iconset_dir"

  local sizes=(16 32 64 128 256 512 1024)
  for size in "${sizes[@]}"; do
    local out_file
    case "$size" in
      16) out_file="$iconset_dir/icon_16x16.png" ;;
      32) out_file="$iconset_dir/icon_16x16@2x.png" ;;
      64) out_file="$iconset_dir/icon_32x32@2x.png" ;;
      128) out_file="$iconset_dir/icon_128x128.png" ;;
      256) out_file="$iconset_dir/icon_128x128@2x.png" ;;
      512) out_file="$iconset_dir/icon_256x256@2x.png" ;;
      1024) out_file="$iconset_dir/icon_512x512@2x.png" ;;
      *) continue ;;
    esac
    sips -s format png -z "$size" "$size" "$source_png" --out "$out_file" >/dev/null
  done

  cp "$iconset_dir/icon_16x16@2x.png" "$iconset_dir/icon_32x32.png"
  cp "$iconset_dir/icon_128x128@2x.png" "$iconset_dir/icon_256x256.png"
  cp "$iconset_dir/icon_256x256@2x.png" "$iconset_dir/icon_512x512.png"

  iconutil -c icns "$iconset_dir" -o "$target_icns"
  rm -rf "$iconset_dir"
}

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

if [ -f "$APP_ICON_SOURCE" ]; then
  generate_icon_icns "$APP_ICON_SOURCE" "$APP_ICON_ICNS"
else
  echo "Warning: app icon source not found, packaging without custom icon: $APP_ICON_SOURCE" >&2
fi

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
  <key>CFBundleIconFile</key>
  <string>${APP_ICON_NAME}</string>
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
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

if [ "$SHOULD_OPEN" -eq 1 ]; then
  open "$APP_BUNDLE"
fi

echo "Packaged: $APP_BUNDLE"
echo "Health check: curl -i http://127.0.0.1:55771/health"
