#!/usr/bin/env bash
set -euo pipefail

TARGET_SCRIPT="$HOME/.claude/hooks/beacon_hook_bridge.sh"

if [ -f "$TARGET_SCRIPT" ]; then
  rm -f "$TARGET_SCRIPT"
  echo "Removed $TARGET_SCRIPT"
else
  echo "No installed Beacon hook bridge found."
fi
