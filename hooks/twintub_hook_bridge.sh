#!/usr/bin/env bash
set -u

PORT="${TWINTUB_PORT:-55771}"
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

normalize_tty() {
  local raw="${1:-}"
  [ -z "$raw" ] && return 1
  case "$raw" in
    "not a tty"|"notatty"|"?"|"") return 1 ;;
  esac
  if [ "${raw#"/dev/"}" != "$raw" ]; then
    printf '%s' "$raw"
  else
    printf '/dev/%s' "$raw"
  fi
}

detect_source_from_env() {
  local term_program="${TERM_PROGRAM:-}"
  local term_value="${TERM:-}"
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
    ghostty|Ghostty)
      SOURCE_APP="Ghostty"
      SOURCE_BUNDLE_ID="com.mitchellh.ghostty"
      SOURCE_PID="$parent_pid"
      SOURCE_CONFIDENCE="high"
      return 0
      ;;
    WezTerm)
      SOURCE_APP="WezTerm"
      SOURCE_BUNDLE_ID="com.github.wez.wezterm"
      SOURCE_PID="$parent_pid"
      SOURCE_CONFIDENCE="high"
      return 0
      ;;
    kaku|Kaku)
      SOURCE_APP="Kaku"
      SOURCE_BUNDLE_ID="fun.tw93.kaku"
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
        SOURCE_BUNDLE_ID="com.microsoft.VSCode"
      fi
      SOURCE_PID="$parent_pid"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
  esac

  case "$term_value" in
    *ghostty*)
      SOURCE_APP="Ghostty"
      SOURCE_BUNDLE_ID="com.mitchellh.ghostty"
      SOURCE_PID="$parent_pid"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
    *kaku*)
      SOURCE_APP="Kaku"
      SOURCE_BUNDLE_ID="fun.tw93.kaku"
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
      SOURCE_BUNDLE_ID="com.microsoft.VSCode"
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
      SOURCE_BUNDLE_ID="fun.tw93.kaku"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
    *ghostty*)
      SOURCE_APP="Ghostty"
      SOURCE_BUNDLE_ID="com.mitchellh.ghostty"
      SOURCE_CONFIDENCE="medium"
      return 0
      ;;
    *wezterm*)
      SOURCE_APP="WezTerm"
      SOURCE_BUNDLE_ID="com.github.wez.wezterm"
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

detect_terminal_context() {
  SHELL_PID="${SHELL_PID:-}"
  SHELL_PPID="${SHELL_PPID:-}"
  TERMINAL_TTY="${TERMINAL_TTY:-}"
  TERMINAL_SESSION_ID="${TERMINAL_SESSION_ID:-}"

  [ -z "$SHELL_PID" ] && SHELL_PID="$$"
  [ -z "$SHELL_PPID" ] && SHELL_PPID="${PPID:-}"

  if [ -z "$TERMINAL_TTY" ]; then
    local detected_tty
    detected_tty="$(tty 2>/dev/null || true)"
    TERMINAL_TTY="$(normalize_tty "$detected_tty" || true)"
  else
    TERMINAL_TTY="$(normalize_tty "$TERMINAL_TTY" || true)"
  fi

  if [ -z "$TERMINAL_TTY" ]; then
    detect_tty_from_process_tree || true
  fi

  if [ -z "$TERMINAL_SESSION_ID" ]; then
    if [ -n "${TERM_SESSION_ID:-}" ]; then
      TERMINAL_SESSION_ID="$TERM_SESSION_ID"
    elif [ -n "${ITERM_SESSION_ID:-}" ]; then
      TERMINAL_SESSION_ID="$ITERM_SESSION_ID"
    elif [ -n "${WARP_SESSION_ID:-}" ]; then
      TERMINAL_SESSION_ID="$WARP_SESSION_ID"
    fi
  fi

  TERMINAL_WINDOW_ID="${TERMINAL_WINDOW_ID:-}"
  TERMINAL_PANE_ID="${TERMINAL_PANE_ID:-}"

  if [ -z "$TERMINAL_WINDOW_ID" ]; then
    if [ -n "${KITTY_WINDOW_ID:-}" ]; then
      TERMINAL_WINDOW_ID="$KITTY_WINDOW_ID"
    elif [ -n "${WINDOWID:-}" ]; then
      TERMINAL_WINDOW_ID="$WINDOWID"
    fi
  fi

  if [ -z "$TERMINAL_PANE_ID" ]; then
    if [ -n "${WEZTERM_PANE:-}" ]; then
      TERMINAL_PANE_ID="$WEZTERM_PANE"
    fi
  fi

  infer_source_from_terminal_context
}

detect_tty_from_process_tree() {
  local current_pid="${PPID:-}"
  local depth=0
  local max_depth=12

  while [ -n "$current_pid" ] && [ "$current_pid" -gt 1 ] 2>/dev/null && [ "$depth" -lt "$max_depth" ]; do
    local tty_value normalized_tty ppid_value
    tty_value="$(ps -p "$current_pid" -o tty= 2>/dev/null | head -n1 | sed 's/^ *//;s/ *$//')"
    normalized_tty="$(normalize_tty "$tty_value" || true)"
    if [ -n "$normalized_tty" ]; then
      TERMINAL_TTY="$normalized_tty"
      SHELL_PID="$current_pid"
      ppid_value="$(ps -p "$current_pid" -o ppid= 2>/dev/null | tr -d ' ')"
      if [ -n "$ppid_value" ]; then
        SHELL_PPID="$ppid_value"
      fi
      return 0
    fi

    current_pid="$(ps -p "$current_pid" -o ppid= 2>/dev/null | tr -d ' ')"
    depth=$((depth + 1))
  done

  return 1
}

infer_source_from_terminal_context() {
  [ -n "${SOURCE_APP:-}" ] && return 0

  if [ -n "${TERM_SESSION_ID:-}" ]; then
    SOURCE_APP="Terminal.app"
    SOURCE_BUNDLE_ID="com.apple.Terminal"
  elif [ -n "${ITERM_SESSION_ID:-}" ]; then
    SOURCE_APP="iTerm2"
    SOURCE_BUNDLE_ID="com.googlecode.iterm2"
  elif [ -n "${WARP_SESSION_ID:-}" ]; then
    SOURCE_APP="Warp"
    SOURCE_BUNDLE_ID="dev.warp.warp-stable"
  else
    return 0
  fi

  [ -z "${SOURCE_PID:-}" ] && SOURCE_PID="${SHELL_PPID:-${PPID:-}}"
  if [ "${SOURCE_CONFIDENCE:-unknown}" = "unknown" ]; then
    SOURCE_CONFIDENCE="medium"
  fi
}

# 从 transcript JSONL 文件提取 token 使用量
# transcript 文件格式: 每行一个 JSON 对象，assistant 消息包含 .message.usage 字段
# 直接使用 token 数，不转换为 bytes（因为 1 token ≈ 4 chars 只是近似值）
extract_usage_from_transcript() {
  local path="$1"
  [ -z "$path" ] || [ ! -f "$path" ] && return 1

  # 读取最后几行，找最新的 assistant 消息
  local usage_line
  usage_line=$(tail -20 "$path" 2>/dev/null | grep '"usage"' | tail -1)
  [ -z "$usage_line" ] && return 1

  # 检查是否安装了 jq
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  # 提取 usage 对象
  local usage
  usage=$(printf '%s' "$usage_line" | jq -r '.message.usage // empty' 2>/dev/null)
  [ -z "$usage" ] && return 1

  # 计算总 token 数 (input + cache_creation + cache_read)
  local input cache_creation cache_read
  input=$(printf '%s' "$usage" | jq -r '.input_tokens // 0')
  cache_creation=$(printf '%s' "$usage" | jq -r '.cache_creation_input_tokens // 0')
  cache_read=$(printf '%s' "$usage" | jq -r '.cache_read_input_tokens // 0')

  # 确保是数字
  case "$input" in
    ''|*[!0-9]*) input=0 ;;
  esac
  case "$cache_creation" in
    ''|*[!0-9]*) cache_creation=0 ;;
  esac
  case "$cache_read" in
    ''|*[!0-9]*) cache_read=0 ;;
  esac

  # 直接使用 token 数，不转换为 bytes
  USAGE_TOKENS=$((input + cache_creation + cache_read))

  # 提取模型名称
  MODEL=$(printf '%s' "$usage_line" | jq -r '.message.model // empty' 2>/dev/null)

  return 0
}

if command -v jq >/dev/null 2>&1; then
  EVENT="$(extract_with_jq '.event // .hook_event_name // .hookEventName')"
  SESSION_ID="$(extract_with_jq '.session_id // .sessionId // .session.id')"
  TIMESTAMP="$(extract_with_jq '.timestamp')"
  CWD="$(extract_with_jq '.cwd')"
  PROMPT="$(extract_with_jq '.prompt // .message.prompt')"
  TOOL_NAME="$(extract_with_jq '.tool_name // .toolName')"
  MESSAGE="$(extract_with_jq '.message // .notification.message')"
  NOTIFICATION_TYPE="$(extract_with_jq '.notification_type // .notification.type // .type')"
  USAGE_BYTES="$(extract_with_jq '.usage_bytes // .usageBytes // .context_usage_bytes')"
  USAGE_TOKENS="$(extract_with_jq '.usage_tokens // .usageTokens')"
  MAX_CONTEXT_BYTES="$(extract_with_jq '.max_context_bytes // .maxContextBytes')"
  MODEL="$(extract_with_jq '.model')"
  TRANSCRIPT_PATH="$(extract_with_jq '.transcript_path // .transcriptPath')"
  PROJECT_NAME="$(extract_with_jq '.project_name // .projectName')"
  SOURCE_APP="$(extract_with_jq '.source_app // .sourceApp')"
  SOURCE_BUNDLE_ID="$(extract_with_jq '.source_bundle_id // .sourceBundleId')"
  SOURCE_PID="$(extract_with_jq '.source_pid // .sourcePid')"
  SOURCE_CONFIDENCE="$(extract_with_jq '.source_confidence // .sourceConfidence')"
  SHELL_PID="$(extract_with_jq '.shell_pid // .shellPid')"
  SHELL_PPID="$(extract_with_jq '.shell_ppid // .shellPpid')"
  TERMINAL_TTY="$(extract_with_jq '.terminal_tty // .terminalTty // .tty')"
  TERMINAL_SESSION_ID="$(extract_with_jq '.terminal_session_id // .terminalSessionId // .term_session_id')"
  TERMINAL_WINDOW_ID="$(extract_with_jq '.terminal_window_id // .terminalWindowId')"
  TERMINAL_PANE_ID="$(extract_with_jq '.terminal_pane_id // .terminalPaneId')"
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
  USAGE_TOKENS="$(extract_int_with_sed 'usage_tokens')"
  MODEL="$(extract_with_sed 'model')"
  TRANSCRIPT_PATH="$(extract_with_sed 'transcript_path')"
  PROJECT_NAME="$(extract_with_sed 'project_name')"
  SOURCE_APP="$(extract_with_sed 'source_app')"
  SOURCE_BUNDLE_ID="$(extract_with_sed 'source_bundle_id')"
  SOURCE_PID="$(extract_int_with_sed 'source_pid')"
  SOURCE_CONFIDENCE="$(extract_with_sed 'source_confidence')"
  SHELL_PID="$(extract_int_with_sed 'shell_pid')"
  SHELL_PPID="$(extract_int_with_sed 'shell_ppid')"
  TERMINAL_TTY="$(extract_with_sed 'terminal_tty')"
  TERMINAL_SESSION_ID="$(extract_with_sed 'terminal_session_id')"
  TERMINAL_WINDOW_ID="$(extract_with_sed 'terminal_window_id')"
  TERMINAL_PANE_ID="$(extract_with_sed 'terminal_pane_id')"
fi

[ -z "$EVENT" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

detect_source || true
detect_terminal_context

# 尝试从 transcript 获取 usage（如果未直接从 hook 获取）
if [ -z "$USAGE_TOKENS" ] && [ -n "$TRANSCRIPT_PATH" ]; then
  extract_usage_from_transcript "$TRANSCRIPT_PATH" || true
fi

# Debug log (temporary)
{
  printf '%s src=%s bundle=%s conf=%s shellPID=%s shellPPID=%s tty=%s TERM_PROGRAM=%s sid=%s\n' \
    "$(date +%H:%M:%S)" "${SOURCE_APP:-nil}" "${SOURCE_BUNDLE_ID:-nil}" \
    "${SOURCE_CONFIDENCE:-nil}" "${SHELL_PID:-nil}" "${SHELL_PPID:-nil}" \
    "${TERMINAL_TTY:-nil}" "${TERM_PROGRAM:-unset}" "${SESSION_ID:-nil}"
} >> /tmp/twintub_source_debug.log 2>/dev/null || true

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
[ -n "$USAGE_TOKENS" ] && payload+=',"usage_tokens":'"$USAGE_TOKENS"
[ -n "$MAX_CONTEXT_BYTES" ] && payload+=',"max_context_bytes":'"$MAX_CONTEXT_BYTES"
[ -n "$MODEL" ] && payload+=',"model":"'"$(json_escape "$MODEL")"'"'
[ -n "$PROJECT_NAME" ] && payload+=',"project_name":"'"$(json_escape "$PROJECT_NAME")"'"'
[ -n "$SOURCE_APP" ] && payload+=',"source_app":"'"$(json_escape "$SOURCE_APP")"'"'
[ -n "$SOURCE_BUNDLE_ID" ] && payload+=',"source_bundle_id":"'"$(json_escape "$SOURCE_BUNDLE_ID")"'"'
[ -n "$SOURCE_PID" ] && payload+=',"source_pid":'"$SOURCE_PID"
[ -n "$SOURCE_CONFIDENCE" ] && payload+=',"source_confidence":"'"$(json_escape "$SOURCE_CONFIDENCE")"'"'
[ -n "$SHELL_PID" ] && payload+=',"shell_pid":'"$SHELL_PID"
[ -n "$SHELL_PPID" ] && payload+=',"shell_ppid":'"$SHELL_PPID"
[ -n "$TERMINAL_TTY" ] && payload+=',"terminal_tty":"'"$(json_escape "$TERMINAL_TTY")"'"'
[ -n "$TERMINAL_SESSION_ID" ] && payload+=',"terminal_session_id":"'"$(json_escape "$TERMINAL_SESSION_ID")"'"'
[ -n "$TERMINAL_WINDOW_ID" ] && payload+=',"terminal_window_id":"'"$(json_escape "$TERMINAL_WINDOW_ID")"'"'
[ -n "$TERMINAL_PANE_ID" ] && payload+=',"terminal_pane_id":"'"$(json_escape "$TERMINAL_PANE_ID")"'"'
[ -n "$TRANSCRIPT_PATH" ] && payload+=',"transcript_path":"'"$(json_escape "$TRANSCRIPT_PATH")"'"'

payload+='}'

curl --silent --output /dev/null --max-time 0.2 \
  -H "Content-Type: application/json" \
  -X POST "$URL" \
  -d "$payload" 2>/dev/null || true

exit 0
