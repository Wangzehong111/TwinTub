#!/usr/bin/env bash
set -u

PORT="${BEACON_PORT:-55771}"
HOST="127.0.0.1"
URL="http://${HOST}:${PORT}/event"

read_stdin_payload() {
  if [ -t 0 ]; then
    printf ""
  else
    cat
  fi
}

RAW_INPUT="${1:-}"
if [ -z "$RAW_INPUT" ]; then
  RAW_INPUT="$(read_stdin_payload)"
fi

extract_with_jq() {
  local key="$1"
  printf '%s' "$RAW_INPUT" | jq -r "$key // empty" 2>/dev/null
}

extract_with_sed() {
  local key="$1"
  printf '%s' "$RAW_INPUT" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
}

extract_int_with_sed() {
  local key="$1"
  printf '%s' "$RAW_INPUT" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n1
}

if command -v jq >/dev/null 2>&1; then
  EVENT="$(extract_with_jq '.event // .hook_event_name // .hookEventName')"
  SESSION_ID="$(extract_with_jq '.session_id // .sessionId // .session.id')"
  TIMESTAMP="$(extract_with_jq '.timestamp')"
  CWD="$(extract_with_jq '.cwd')"
  PROMPT="$(extract_with_jq '.prompt // .message.prompt')"
  TOOL_NAME="$(extract_with_jq '.tool_name // .toolName')"
  MESSAGE="$(extract_with_jq '.message // .notification.message')"
  NOTIFICATION_TYPE="$(extract_with_jq '.notification_type // .type')"
  USAGE_BYTES="$(extract_with_jq '.usage_bytes // .usageBytes // .context_usage_bytes')"
  PROJECT_NAME="$(extract_with_jq '.project_name // .projectName')"
else
  EVENT="$(extract_with_sed 'event')"
  SESSION_ID="$(extract_with_sed 'session_id')"
  TIMESTAMP="$(extract_with_sed 'timestamp')"
  CWD="$(extract_with_sed 'cwd')"
  PROMPT="$(extract_with_sed 'prompt')"
  TOOL_NAME="$(extract_with_sed 'tool_name')"
  MESSAGE="$(extract_with_sed 'message')"
  NOTIFICATION_TYPE="$(extract_with_sed 'notification_type')"
  USAGE_BYTES="$(extract_int_with_sed 'usage_bytes')"
  PROJECT_NAME="$(extract_with_sed 'project_name')"
fi

[ -z "$EVENT" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

payload='{"event":"'"$(json_escape "$EVENT")"'","session_id":"'"$(json_escape "$SESSION_ID")"'"'

[ -n "$TIMESTAMP" ] && payload+=',"timestamp":"'"$(json_escape "$TIMESTAMP")"'"'
[ -n "$CWD" ] && payload+=',"cwd":"'"$(json_escape "$CWD")"'"'
[ -n "$PROMPT" ] && payload+=',"prompt":"'"$(json_escape "$PROMPT")"'"'
[ -n "$TOOL_NAME" ] && payload+=',"tool_name":"'"$(json_escape "$TOOL_NAME")"'"'
[ -n "$MESSAGE" ] && payload+=',"message":"'"$(json_escape "$MESSAGE")"'"'
[ -n "$NOTIFICATION_TYPE" ] && payload+=',"notification_type":"'"$(json_escape "$NOTIFICATION_TYPE")"'"'
[ -n "$USAGE_BYTES" ] && payload+=',"usage_bytes":'"$USAGE_BYTES"
[ -n "$PROJECT_NAME" ] && payload+=',"project_name":"'"$(json_escape "$PROJECT_NAME")"'"'

payload+='}'

curl --silent --output /dev/null --max-time 0.2 \
  -H "Content-Type: application/json" \
  -X POST "$URL" \
  -d "$payload" 2>/dev/null || true

exit 0
