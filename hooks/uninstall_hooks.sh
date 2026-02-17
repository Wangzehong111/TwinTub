#!/usr/bin/env bash
set -euo pipefail

TARGET_SCRIPT="$HOME/.claude/hooks/twintub_hook_bridge.sh"

if [ -f "$TARGET_SCRIPT" ]; then
  rm -f "$TARGET_SCRIPT"
  echo "Removed $TARGET_SCRIPT"
else
  echo "No installed TwinTub hook bridge found."
fi
