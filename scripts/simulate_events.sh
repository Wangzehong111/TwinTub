#!/usr/bin/env bash
set -euo pipefail

HOST="127.0.0.1"
PORT="${TWINTUB_PORT:-55771}"
URL="http://${HOST}:${PORT}/event"
SESSION_ID="demo-session"

send() {
  local payload="$1"
  curl --silent --show-error -H "Content-Type: application/json" -X POST "$URL" -d "$payload"
  echo
}

echo "Sending UserPromptSubmit"
send '{"event":"UserPromptSubmit","session_id":"'"$SESSION_ID"'","cwd":"'"$PWD"'","prompt":"run tests"}'

sleep 1
echo "Sending PostToolUse"
send '{"event":"PostToolUse","session_id":"'"$SESSION_ID"'","usage_bytes":680000}'

sleep 1
echo "Sending PermissionRequest"
send '{"event":"PermissionRequest","session_id":"'"$SESSION_ID"'","tool_name":"bash"}'

sleep 1
echo "Sending UserPromptSubmit (resume)"
send '{"event":"UserPromptSubmit","session_id":"'"$SESSION_ID"'","prompt":"yes"}'

sleep 1
echo "Sending Stop"
send '{"event":"Stop","session_id":"'"$SESSION_ID"'"}'
