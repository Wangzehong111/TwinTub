# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Beacon** 是一个 macOS Menu Bar 应用程序，用于监控 Claude Code CLI 的多会话状态。产品遵循 "Native & Retro" 设计哲学，提供沉浸式的终端美学体验。

## Architecture

### System Architecture (Sidecar Pattern)

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Claude Code CLI │────▶│  Hook Bridge    │────▶│  SwiftUI App    │
│   (Terminal)    │     │  (Bash/cURL)    │     │  (Menu Bar)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                        │
   Hook Events            HTTP POST /event       UI + Notifications
```

Hooks Reference: https://code.claude.com/docs/en/hooks
Automate with hooks: https://code.claude.com/docs/en/hooks-guide

### Components

1. **Hook Bridge** (`hooks/beacon_hook_bridge.sh`): Bash 脚本监听 Claude Code 生命周期事件，通过 HTTP POST 发送给 App
2. **LocalEventServer**: 使用 Network.framework 的 TCP 服务器，监听端口 55771，接收 `/event` 和 `/health` 端点
3. **SwiftUI Menu Bar App**: 接收事件并更新 UI，支持状态显示、会话列表、跳转功能

### Code Architecture (Redux-like Pattern)

```
BeaconEvent ──▶ SessionReducer ──▶ Mutation ──▶ SessionStore ──▶ SwiftUI Views
                                    │
                                    └─▶ NotificationDecision ──▶ NotificationService
```

核心文件：
- `BeaconApp/App/BeaconApp.swift`: App 入口，初始化依赖
- `BeaconApp/Core/Model/BeaconEvent.swift`: 事件模型（来自 hooks）
- `BeaconApp/Core/Model/SessionModel.swift`: 会话状态模型
- `BeaconApp/Core/State/SessionReducer.swift`: 纯函数 reducer，处理事件逻辑
- `BeaconApp/Core/Store/SessionStore.swift`: 状态管理，Combine throttle 500ms
- `BeaconApp/Core/EventServer/LocalEventServer.swift`: HTTP 服务器（端口 55771）
- `BeaconApp/Core/Services/NotificationService.swift`: 系统通知
- `BeaconApp/Core/Services/TerminalJumpService.swift`: 跳转到终端会话

### Communication Protocol

- App 监听本地端口 **55771**（可通过 `BEACON_PORT` 环境变量覆盖）
- Hook Bridge 使用 `curl` 发送 JSON 数据到 `POST /event`
- 健康检查：`GET /health`
- 事件类型映射：
  - `UserPromptSubmit` → `processing`
  - `PostToolUse` → `processing` + context_usage
  - `PermissionRequest` → `waiting`
  - `Notification` → `waiting` (permission_prompt/idle_prompt)
  - `Stop` → `completed`
  - `SessionEnd` → `destroyed` (从列表中移除)

## Key Hook Events for This Project

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "matcher": "", "hooks": [{"type": "command", "command": "..."}] }],
    "PostToolUse": [{ "matcher": ".*", "hooks": [{"type": "command", "command": "..."}] }],
    "PermissionRequest": [{ "matcher": ".*", "hooks": [{"type": "command", "command": "..."}] }],
    "Notification": [{ "matcher": "permission_prompt|idle_prompt", "hooks": [{"type": "command", "command": "..."}] }],
    "Stop": [{ "hooks": [{"type": "command", "command": "..."}] }],
    "SessionEnd": [{ "matcher": ".*", "hooks": [{"type": "command", "command": "..."}] }]
  }
}
```

## UI/UX Specification

请严格参考 `beacon.pen` 设计稿，包含：

- **Dark Theme**: 背景 #1A1A1A，强调色琥珀橙 #FF9F0A / 终端绿 #32D74B
- **Light Theme**: 背景 #F7F3E0，强调色国际橙 #FF453A / 墨绿 #004D40
- **Menu Bar Icon**: 胶囊形态，显示状态（Idle/Waiting/Processing/Done）
- **Session Card**: 项目名、当前行为、10段式容量条、跳转按钮
- **排序规则**: Waiting > Processing > Completed

## Development Notes

- 使用 SwiftUI `MenuBarExtra` 构建 Menu Bar 应用
- 字体建议使用 Space Mono 或 SF Mono（单宽字体）
- 状态机需处理乱序事件（如先收到 Stop 再收到 PermissionRequest）
- TTL 机制：超过 30 分钟无更新的 Processing 会话视为僵尸会话
- 使用 Combine 的 `throttle` 限制 UI 刷新频率（500ms）
- 通知策略：等待状态静默窗口 120 秒，升级窗口 180 秒

## Common Commands

### Build & Run (Recommended)

```bash
./scripts/run_beacon_app.sh
```

构建 `Beacon`，打包为 `.build/Beacon.app` 并启动。

### Build

```bash
# Using script (app bundle)
./scripts/run_beacon_app.sh --no-run

# Using xcodebuild
xcodebuild -scheme Beacon -destination 'platform=macOS' build

# Using swift package
swift build
```

### Test

```bash
# All tests
xcodebuild -scheme Beacon -destination 'platform=macOS' test

# Swift Package tests
swift test
```

### Hook Management

```bash
# Install hooks
./hooks/install_hooks.sh

# Uninstall hooks
./hooks/uninstall_hooks.sh
```

### Simulate Events

```bash
# Send test events to running app
./scripts/simulate_events.sh
```

### Health Check

```bash
curl -i http://127.0.0.1:55771/health
```

### Manual Event Sending

```bash
curl -X POST http://127.0.0.1:55771/event \
  -H "Content-Type: application/json" \
  -d '{"event":"UserPromptSubmit","session_id":"test-session","cwd":"'$PWD'","prompt":"hello"}'
```
