#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SCRIPT="$ROOT_DIR/hooks/twintub_hook_bridge.sh"
TARGET_DIR="$HOME/.claude/hooks"
TARGET_SCRIPT="$TARGET_DIR/twintub_hook_bridge.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

mkdir -p "$TARGET_DIR"
cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"

echo "TwinTub hook bridge installed: $TARGET_SCRIPT"

echo ""
echo "If you manage Claude hooks via JSON, add this command for each needed hook event:"
echo "  $TARGET_SCRIPT"
echo ""
echo "Validation command:"
echo "  echo '{"event":"UserPromptSubmit","session_id":"demo","cwd":"$PWD"}' | $TARGET_SCRIPT"

if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
  TMP_FILE="$(mktemp)"
  jq '. as $root | if ($root.hooks // null) == null then . + {hooks: {}} else . end' "$SETTINGS_FILE" > "$TMP_FILE"
  mv "$TMP_FILE" "$SETTINGS_FILE"
  echo "Normalized hooks root in $SETTINGS_FILE"

  REQUIRED_EVENTS=(UserPromptSubmit PostToolUse PermissionRequest Notification Stop SessionEnd)
  MISSING_EVENTS=()
  for event in "${REQUIRED_EVENTS[@]}"; do
    if ! jq -e --arg event "$event" '.hooks[$event] // empty' "$SETTINGS_FILE" >/dev/null; then
      MISSING_EVENTS+=("$event")
    fi
  done

  if [ "${#MISSING_EVENTS[@]}" -gt 0 ]; then
    echo ""
    echo "Warning: missing hook event mappings in $SETTINGS_FILE:"
    printf '  - %s\n' "${MISSING_EVENTS[@]}"
    echo "Please ensure these events call:"
    echo "  $TARGET_SCRIPT"
  fi
fi
