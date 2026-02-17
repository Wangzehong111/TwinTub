# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TwinTub** 是一个 macOS Menu Bar 应用程序，用于监控 Claude Code CLI 的多会话状态。产品遵循 "Native & Retro" 设计哲学，提供沉浸式的终端美学体验。

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

### Code Architecture (Redux-like Pattern)

```
TwinTubEvent ──▶ EventBridge ──▶ SessionStore ──▶ SwiftUI Views
                    │                │
                    │                ├─▶ SessionReducer (pure)
                    │                ├─▶ SessionLivenessMonitor
                    │                └─▶ NotificationService
                    │
                    └─▶ Coalesce by session, 100ms flush
```

核心文件：
- `TwinTubApp/App/TwinTubApp.swift`: App 入口，包含 `EventBridge`（事件合并/flush）、`AppDelegate`
- `TwinTubApp/Core/Model/TwinTubEvent.swift`: 事件模型（来自 hooks）
- `TwinTubApp/Core/Model/SessionModel.swift`: 会话状态模型（含 liveness 字段）
- `TwinTubApp/Core/State/SessionReducer.swift`: 纯函数 reducer，处理事件逻辑
- `TwinTubApp/Core/Store/SessionStore.swift`: 状态管理，Combine throttle 500ms，后台 liveness 检查
- `TwinTubApp/Core/EventServer/LocalEventServer.swift`: HTTP 服务器（端口 55771）
- `TwinTubApp/Core/Services/NotificationService.swift`: 系统通知
- `TwinTubApp/Core/Services/TerminalJumpService.swift`: 跳转到终端会话
- `TwinTubApp/Core/Services/SessionLivenessMonitor.swift`: 会话存活监控（进程/TTY 验证）
- `TwinTubApp/Core/Services/ProcessSnapshotProvider.swift`: 系统 ps 快照提供者
- `TwinTubApp/Core/Services/HookConfigValidator.swift`: Hook 配置验证与自动修复

### Session Liveness (Dual-Source Truth)

会话存活状态由两种来源共同决定：

1. **Hook Events**: 驱动会话创建和状态更新
2. **Liveness Monitor**: 每 5 秒通过 `ps` 快照验证进程/TTY 存活

Liveness 状态流转：
```
alive → suspectOffline (首次检测不到) → offline (超过 grace period) → terminated
```

配置参数（`SessionLivenessMonitor.Config`）：
- `offlineGracePeriod`: 20 秒（防止终端抖动误杀）
- `terminatedHistoryRetention`: 300 秒（已终止会话保留时间）
- `hardExpiry`: 1800 秒（无心跳强制过期）

### Terminal Jump Behavior

点击 Jump 按钮的跳转策略：
1. 优先通过 TTY 精确匹配原始终端 Tab（Terminal/iTerm2 支持）
2. 回退到打开源 App 并 `cd cwd`
3. 最终回退到显示终端选择器

支持的终端（自动检测 + 手动选择）：
- Terminals: `Terminal.app`, `iTerm2`, `Warp`, `Ghostty`, `WezTerm`, `Kitty`, `Alacritty`, `Tabby`, `Hyper`, `Rio`, `Kaku`
- IDE terminals: `Cursor`, `VS Code`, `Zed`

### Communication Protocol

- App 监听本地端口 **55771**（可通过 `TWINTUB_PORT` 环境变量覆盖）
- Hook Bridge 使用 `curl` 发送 JSON 数据到 `POST /event`
- 健康检查：`GET /health`
- 事件类型映射：
  - `UserPromptSubmit` → `processing`
  - `PostToolUse` → `processing` + context_usage
  - `PermissionRequest` → `waiting`
  - `Notification` → `waiting` (permission_prompt/idle_prompt)
  - `Stop` → `completed`
  - `SessionEnd` → `destroyed` (从列表中移除)

Hook Bridge 额外字段：
- `source_app`, `source_bundle_id`, `source_pid`, `source_confidence`: 来源终端检测
- `shell_pid`, `shell_ppid`: Shell 进程信息
- `terminal_tty`, `terminal_session_id`, `terminal_window_id`, `terminal_pane_id`: 终端上下文

### Event Bridge Coalescing

`EventBridge` 执行事件合并逻辑：
- 同一 session 的连续事件只保留最新
- `SessionEnd` 优先级最高，始终覆盖其他事件
- `Stop` 次之，覆盖非 `SessionEnd` 事件
- 100ms flush 间隔，防止高频事件阻塞 UI

## Key Hook Events

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

## UI/UX

设计稿位于 `twintub.pen`。

- **Dark Theme**: 背景 #050607，强调色琥珀橙 #FFB347 / 终端绿 #7CFC00
- **Light Theme**: 背景 #F7F3E0，强调色国际橙 #D97706 / 墨绿 #059669
- **Menu Bar Icon**: 胶囊形态，显示状态（Idle/Waiting/Processing/Done）
- **Session Card**: 项目名、当前行为、10段式容量条、跳转按钮
- **排序规则**: Waiting > Processing > Completed

UI 组件：
- `TwinTubPanelView`: 主面板，包含 header、controls、session 列表
- `SessionCardView`: 会话卡片
- `PillStatusView`: Menu Bar 状态图标
- `ThemeTokens`: 主题颜色/字体 token

## Common Commands

### Build & Run (Recommended)

```bash
./scripts/run_twintub_app.sh
```

构建并打包为 `dist/TwinTub.app`，然后启动。

### Build Only

```bash
./scripts/run_twintub_app.sh --no-run

# 或 xcodebuild
xcodebuild -scheme TwinTub -destination 'platform=macOS' build
```

### Test

```bash
# All tests
xcodebuild -scheme TwinTub -destination 'platform=macOS' test

# 或 Swift Package
swift test

# 单个测试
swift test --filter SessionLivenessMonitorTests
swift test --filter SessionReducerTests
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

### Debug Source Detection

```bash
# 查看来源检测日志
tail -f /tmp/twintub_source_debug.log
```

## Development Notes

- 使用 SwiftUI `MenuBarExtra` 构建 Menu Bar 应用
- 字体使用 `Font.system(.monospaced)` 单宽字体
- 状态机需处理乱序事件（如先收到 Stop 再收到 PermissionRequest）
- Liveness 检查在后台队列 `twintub.liveness.queue` 执行，避免阻塞主线程
- 通知策略：等待状态静默窗口 120 秒，升级窗口 180 秒
- App 启动时自动验证 hooks 配置，如有问题尝试自动修复
- 单例检查：`AppDelegate.applicationDidFinishLaunching` 中检查重复实例并退出
