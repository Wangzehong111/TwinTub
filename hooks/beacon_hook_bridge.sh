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

normalize_source_confidence() {
  case "${1:-}" in
    high|medium|low|unknown) printf '%s' "$1" ;;
    *) printf 'unknown' ;;
  esac
}

detect_source_from_env() {
  local term_program="${TERM_PROGRAM:-}"
  local parent_pid="${PPID:-}"
  case "$term_program" in
    Apple_Terminal)
      SOURCE_APP="Terminal.app"
      SOURCE_BUNDLE_ID="com.apple.Terminal"
      SOURCE_PID="$parent_pid"
      SOURCE_CONFIDENCE="high"
      return 0
      ;;
    iTerm.app)
      SOURCE_APP="iTerm2"
      SOURCE_BUNDLE_ID="com.googlecode.iterm2"
      SOURCE_PID="$parent_pid"
      SOURCE_CONFIDENCE="high"
      return 0
      ;;
    WarpTerminal)
      SOURCE_APP="Warp"
      SOURCE_BUNDLE_ID="dev.warp.warp-stable"
      SOURCE_PID="$parent_pid"
      SOURCE_CONFIDENCE="high"
      return 0
      ;;
    vscode)
      if [ -n "${CURSOR_TRACE_ID:-}" ] || [ -n "${CURSOR_LAUNCHED_BY_CURSOR:-}" ]; then
        SOURCE_APP="Cursor"
        SOURCE_BUNDLE_ID="com.todesktop.230313mzl4w4u92"
      else
        SOURCE_APP="Visual Studio Code"
        SOURCE_BUNDLE_ID="com.microsoft.vscode"
      fi
      SOURCE_PID="$parent_pid"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
  esac
  return 1
}

source_from_process_name() {
  local process_name="$1"
  local lower
  lower="$(printf '%s' "$process_name" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *cursor*)
      SOURCE_APP="Cursor"
      SOURCE_BUNDLE_ID="com.todesktop.230313mzl4w4u92"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
    *"visual studio code"*|*"/code"*|*" code")
      SOURCE_APP="Visual Studio Code"
      SOURCE_BUNDLE_ID="com.microsoft.vscode"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
    *iterm2*)
      SOURCE_APP="iTerm2"
      SOURCE_BUNDLE_ID="com.googlecode.iterm2"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
    *terminal*)
      SOURCE_APP="Terminal.app"
      SOURCE_BUNDLE_ID="com.apple.Terminal"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
    *warp*)
      SOURCE_APP="Warp"
      SOURCE_BUNDLE_ID="dev.warp.warp-stable"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
    *kaku*)
      SOURCE_APP="Kaku"
      SOURCE_BUNDLE_ID="com.kaku.app"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
  esac
  return 1
}

detect_source_from_process_tree() {
  local current_pid="${PPID:-}"
  local depth=0
  local max_depth=8

  while [ -n "$current_pid" ] && [ "$current_pid" -gt 1 ] 2>/dev/null && [ "$depth" -lt "$max_depth" ]; do
    local comm
    comm="$(ps -p "$current_pid" -o comm= 2>/dev/null | head -n1 | sed 's/^ *//;s/ *$//')"
    if [ -n "$comm" ] && source_from_process_name "$comm"; then
      SOURCE_PID="$current_pid"
      return 0
    fi
    current_pid="$(ps -p "$current_pid" -o ppid= 2>/dev/null | tr -d ' ')"
    depth=$((depth + 1))
  done
  return 1
}

detect_source_from_frontmost_app() {
  local front_name
  front_name="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || true)"
  if [ -n "$front_name" ] && source_from_process_name "$front_name"; then
    SOURCE_CONFIDENCE="low"
    return 0
  fi
  return 1
}

detect_source() {
  SOURCE_APP="${SOURCE_APP:-}"
  SOURCE_BUNDLE_ID="${SOURCE_BUNDLE_ID:-}"
  SOURCE_PID="${SOURCE_PID:-}"
  SOURCE_CONFIDENCE="$(normalize_source_confidence "${SOURCE_CONFIDENCE:-unknown}")"

  if [ -n "$SOURCE_APP" ]; then
    return 0
  fi

  if detect_source_from_env; then
    return 0
  fi
  if detect_source_from_process_tree; then
    return 0
  fi
  if detect_source_from_frontmost_app; then
    return 0
  fi

  SOURCE_CONFIDENCE="unknown"
  return 1
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
  SOURCE_APP="$(extract_with_jq '.source_app // .sourceApp')"
  SOURCE_BUNDLE_ID="$(extract_with_jq '.source_bundle_id // .sourceBundleId')"
  SOURCE_PID="$(extract_with_jq '.source_pid // .sourcePid')"
  SOURCE_CONFIDENCE="$(extract_with_jq '.source_confidence // .sourceConfidence')"
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
  SOURCE_APP="$(extract_with_sed 'source_app')"
  SOURCE_BUNDLE_ID="$(extract_with_sed 'source_bundle_id')"
  SOURCE_PID="$(extract_int_with_sed 'source_pid')"
  SOURCE_CONFIDENCE="$(extract_with_sed 'source_confidence')"
fi

[ -z "$EVENT" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

detect_source || true

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
[ -n "$SOURCE_APP" ] && payload+=',"source_app":"'"$(json_escape "$SOURCE_APP")"'"'
[ -n "$SOURCE_BUNDLE_ID" ] && payload+=',"source_bundle_id":"'"$(json_escape "$SOURCE_BUNDLE_ID")"'"'
[ -n "$SOURCE_PID" ] && payload+=',"source_pid":'"$SOURCE_PID"
[ -n "$SOURCE_CONFIDENCE" ] && payload+=',"source_confidence":"'"$(json_escape "$SOURCE_CONFIDENCE")"'"'

payload+='}'

curl --silent --output /dev/null --max-time 0.2 \
  -H "Content-Type: application/json" \
  -X POST "$URL" \
  -d "$payload" 2>/dev/null || true

exit 0
