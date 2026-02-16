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

kill_existing_instances() {
  local pids=()
  local helper_pids=()
  local seen=" "

  # Collect running BeaconApp instances from both derived data and dist bundles.
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    if [[ "$seen" != *" $pid "* ]]; then
      pids+=("$pid")
      seen="$seen$pid "
    fi

    # Include debugger parents that can respawn BeaconApp immediately.
    local parent
    parent="$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')"
    if [ -n "$parent" ] && [ "$parent" -gt 1 ] 2>/dev/null; then
      if [[ "$seen" != *" $parent "* ]]; then
        helper_pids+=("$parent")
        seen="$seen$parent "
      fi
      local grandparent
      grandparent="$(ps -p "$parent" -o ppid= 2>/dev/null | tr -d ' ')"
      if [ -n "$grandparent" ] && [ "$grandparent" -gt 1 ] 2>/dev/null; then
        if [[ "$seen" != *" $grandparent "* ]]; then
          helper_pids+=("$grandparent")
          seen="$seen$grandparent "
        fi
      fi
    fi
  done < <(pgrep -f "/(DerivedData|dist)/.*/BeaconApp" || true)

  # Explicitly collect debugserver processes attached to Beacon debug builds.
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    if [[ "$seen" != *" $pid "* ]]; then
      helper_pids+=("$pid")
      seen="$seen$pid "
    fi
  done < <(pgrep -f "debugserver.*Beacon.*/Build/Products/Debug/BeaconApp" || true)

  if [ "${#pids[@]}" -eq 0 ] && [ "${#helper_pids[@]}" -eq 0 ]; then
    return
  fi

  if [ "${#pids[@]}" -gt 0 ]; then
    echo "Stopping existing BeaconApp instances: ${pids[*]}"
    kill "${pids[@]}" 2>/dev/null || true
  fi
  if [ "${#helper_pids[@]}" -gt 0 ]; then
    echo "Stopping debugger helper processes: ${helper_pids[*]}"
    kill "${helper_pids[@]}" 2>/dev/null || true
  fi
  sleep 0.4

  # Force kill any stragglers to avoid launching stale menu bar instances.
  while IFS= read -r pid; do
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
  done < <(pgrep -f "/(DerivedData|dist)/.*/BeaconApp" || true)
  while IFS= read -r pid; do
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
  done < <(pgrep -f "debugserver.*Beacon.*/Build/Products/Debug/BeaconApp" || true)
}

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

kill_existing_instances

# Sync hook bridge to ~/.claude/hooks/
if [ -f "$ROOT_DIR/hooks/beacon_hook_bridge.sh" ]; then
  mkdir -p "$HOME/.claude/hooks"
  cp "$ROOT_DIR/hooks/beacon_hook_bridge.sh" "$HOME/.claude/hooks/beacon_hook_bridge.sh"
  chmod +x "$HOME/.claude/hooks/beacon_hook_bridge.sh"
fi

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
  kill_existing_instances
  open "$APP_BUNDLE"
fi

echo "Packaged: $APP_BUNDLE"
echo "Health check: curl -i http://127.0.0.1:55771/health"
