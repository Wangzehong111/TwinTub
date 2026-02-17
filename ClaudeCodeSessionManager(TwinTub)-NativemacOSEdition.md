
# 1. 产品愿景与设计哲学

### 1.1 核心痛点回顾

开发者在使用 Claude Code CLI 时，面临“任务黑盒化”的三大挑战：

1. **注意力碎片化**：任务执行耗时，用户切换窗口后遗忘任务，导致 CPU 时间浪费。
    
2. **关键阻塞无感知**：Agent 卡在 `PermissionRequest`（权限确认）环节，因无系统通知而白白等待。
    
3. **多线程管理混乱**：多个终端 Tab 同时运行，无法快速定位哪个 Tab 跑了哪个任务。
    

### 1.2 设计哲学：Native & Retro

为了解决上述问题，CCSM Native 版遵循以下设计原则：

- **零干扰 (Silent)**：在不需要用户时彻底隐形，不抢占 Dock 栏，仅驻留 Menu Bar。
    
- **复古未来 (Retro Lab)**：结合像素风、单宽字体与高对比度色彩，致敬终端美学，提供沉浸式的 "Hacker" 体验。
    
- **松耦合 (Decoupled)**：监控端（CLI）与展示端（App）物理隔离，互不影响稳定性。
    

## 2. 交互体验设计 (UX Specification)

得益于 SwiftUI 的灵活性，我们摒弃标准控件，构建高度定制的 **Beacon System** 面板。

### 2.1 视觉主题 (Theming)

支持两套硬编码主题，自动跟随系统或手动切换：

- **🌑 Dark Theme (Native Retro)**：
    
    - 背景：深空灰黑 (#1A1A1A)
        
    - 强调色：琥珀橙 (#FF9F0A) / 终端绿 (#32D74B)
        
    - 质感：微噪点背景，高对比度描边。
        
- **🌕 Light Theme (Retro Lab)**：
    
    - 背景：复古米白 (#F2F0E6)
        
    - 强调色：国际橙 (#FF453A) / 墨绿 (#004D40)
        
    - 质感：纸质感，类似旧式打印机输出。
        

### 2.2 状态可视化 (Menu Bar Icon)

菜单栏图标需精简，采用 **Pill (胶囊)** 形态展示核心状态：

- **⚪️ 空闲态 (Idle)**：单色 `BEACON` 文字或简单图标。
    
- **🔴 阻塞态 (Waiting)**：左侧显示红点🔴 + 文字 `WAITING`。
    
- **🔵 工作态 (Processing)**：左侧显示黄/橙点🟠 + 文字 `PROCESSING`。
    
- **🟢 完成态 (Done)**：绿点🟢 + 文字 `DONE` (显示 5s 后消失)。
    

### 2.3 仪表盘面板 (Beacon Panel)

点击图标展开悬浮面板（320x450pt），UI 布局如下：

#### A. 头部 (Header)

- 显示系统代号：`BEACON_SYSTEM_v1.0`
    
- 右侧显示活跃会话数：`[ ACTIVE_SESSIONS: 02 ]`
    

#### B. 会话卡片 (Session Card)

每个会话为一个独立卡片，包含：

1. **标题区**：
    
    - 大字号单宽字体显示项目名（如 `CLI_CORE_DEBUG`）。
        
    - 下方小字显示当前行为状态（如 `> RUNNING_TESTS...`）。
        
2. **状态指示**：
    
    - 左侧边缘高亮条：
        
        - **Processing**: 琥珀色呼吸灯
            
        - **Waiting**: 红色闪烁 (不仅颜色变化，卡片背景可有微弱红色脉冲)
            
        - **Done**: 绿色常亮
            
3. **容量感知 (Segmented Context Bar)**：
    
    - **设计**：**10 段式**离散能量条（类似电池电量格）。
        
    - **逻辑**：
        
        - 1-5 格：低占用 (灰色/暗色)
            
        - 6-8 格：中占用 (琥珀色) - **Warn at 60%**
            
        - 9-10 格：高危 (红色) - **Critical at 90%**
            
4. **操作区**：
    
    - 右侧常驻 `Jump` (跳转) 按钮，图标为 `box.arrow.up.right`。
        

#### C. 空状态 (Standby Mode)

当无活跃会话时，显示终端风格的占位符：

- 居中显示：`> STANDBY_MODE`
    
- 副标题：`Waiting for neural initialization...`
    
- 底部按钮：`OPEN LAST ACTIVE SESSION` (快速恢复最近的工作区)
    

### 2.4 排序与展示规则 (Interaction Rules)

严格遵循 **Attention-First** 原则，列表排序逻辑如下：

1. **🔴 WAITING (最高优)**：需要用户干预的任务强制置顶。
    
2. **🔵 PROCESSING**：正在运行的任务随后。
    
3. **🟢 DONE**：已完成的任务沉底（按完成时间倒序）。
    

**辅助规则**：

- **Decay (衰减)**：同一会话在 2 分钟内重复触发的相同 Notification 需静音，避免刷屏。
    
- **Auto Target**：跳转终端时，优先匹配 `cwd`，若失败则回退到模糊搜索。
    

## 3. 技术架构方案

### 3.1 总体架构：Local Client-Server

采用 **Sidecar 模式**。App 作为 Sidecar 伴随终端运行，通过本地回环网络通信。

```
sequenceDiagram
    autonumber
    
    box "用户环境" #f9f9f9
        actor User as User (Terminal)
        participant CC as Claude Code (CLI)
    end
    
    box "Hook 机制层" #eaeaea
        participant Hook as Internal Hook System
        participant Script as hooks_bridge.py
    end
    
    box "产品应用层 (你的 App)" #e1f5fe
        participant App as Menu Bar App (Server)
        participant UI as GUI / Notification
    end

    Note over User, UI: === 阶段 1: 任务启动 (状态: Processing) ===

    User->>CC: 输入 Prompt 并回车
    CC->>Hook: 触发事件: UserPromptSubmit
    Hook->>Script: 注入 JSON (prompt, session_id)
    activate Script
    Script->>Script: 解析 Prompt 生成标题建议
    Script->>App: HTTP POST /update<br/>{status: "processing", title: "..."}
    deactivate Script
    activate App
    App->>UI: 顶部 Icon 变为 [处理中/转圈]
    App->>UI: 更新面板会话列表 & 标题
    deactivate App

    Note over User, UI: === 阶段 2: 执行与监控 (Context 更新) ===

    loop Agent 执行循环
        CC->>CC: 思考 / 调用工具 (Tool Use)
        CC->>Hook: 触发事件: PostToolUse
        Hook->>Script: 注入 JSON (transcript_path)
        activate Script
        Script->>Script: 读取 transcript 文件大小<br/>计算 Context 占用比
        Script->>App: HTTP POST /update<br/>{context_usage: 45%}
        deactivate Script
        App->>UI: 更新面板中的 [容量进度条]
    end

    Note over User, UI: === 阶段 3: 需要人工干预 (状态: Waiting) ===

    rect rgb(255, 240, 240)
        CC->>CC: 遇到敏感操作 / 确认环节
        CC->>Hook: 触发事件: PermissionRequest / Notification
        Hook->>Script: 注入 JSON (type: permission_prompt)
        activate Script
        Script->>App: HTTP POST /update<br/>{status: "waiting_input"}
        deactivate Script
        activate App
        App->>UI: 顶部 Icon 变为 [待回复/红色]
        App->>User: 发送系统弹窗通知 (System Notification)
        deactivate App
    end

    User->>CC: 在终端输入 "y" (确认)
    CC->>Hook: 触发事件: UserPromptSubmit
    Hook->>Script: JSON
    Script->>App: HTTP POST {status: "processing"}
    App->>UI: Icon 恢复 [处理中]

    Note over User, UI: === 阶段 4: 任务完成 (状态: Completed) ===

    CC->>CC: 输出最终结果
    CC->>Hook: 触发事件: Stop
    Hook->>Script: 注入 JSON
    activate Script
    Script->>App: HTTP POST /update<br/>{status: "completed"}
    deactivate Script
    App->>UI: 顶部 Icon 变为 [已完成/绿色]

    Note over User, UI: === 阶段 5: 快捷交互 ===

    User->>UI: 点击菜单栏 Icon -> 点击 "跳转"
    UI->>App: 触发跳转事件 (session_id)
    App->>App: 查找 session 对应的 cwd
    App->>User: 执行系统命令 `open -a Terminal {cwd}`<br/>(唤起对应的终端窗口)
```

### 3.2 模块详细设计

#### A. 采集端 (Hook Bridge)

- **技术选型**：Pure Bash + cURL + jq。
    
- **设计理由**：
    
    - **零依赖**：Python 环境在不同用户机器上千差万别（版本、路径、依赖库），Bash 是 macOS 的标配。
        
    - **原子性**：脚本执行时间需控制在 10ms 级，避免阻塞 Claude 的主线程。cURL 的 `--max-time` 参数至关重要。
        
    - **容错性**：如果 App 未启动（端口未监听），Hook 必须**静默失败**，绝不能向终端 stderr 输出报错信息，否则会干扰 LLM 的上下文读取。
        

#### B. 服务端 (Swift Native App)

- **网络层**：使用 `Network.framework` 或轻量级 `Swifter`。只需处理一个 `/event` POST 路由。
    
- **数据层 (Session Store)**：
    
    - 维护一个 `Dictionary<SessionID, SessionModel>`。
        
    - **TTL 机制**：由于 `SessionEnd` 事件可能丢失（如终端崩溃），需引入心跳或 TTL（Time To Live）机制。如果一个 Session 超过 30 分钟无更新且处于 Processing 状态，标记为“僵尸会话”或自动移除。
        

#### C. 状态机逻辑 (State Machine)

App 内部需维护严格的状态流转，以修正可能的乱序事件：

- `PermissionRequest` 事件将状态置为 **Waiting**。
    
- 随后的 `UserPromptSubmit` 事件（代表用户输入了 'y'）将状态重置为 **Processing**。
    
- 这是一个典型的**乐观更新**策略：假设用户输入就是为了解决阻塞。
    

### 3.3 状态映射全景表 (State Mapping Matrix)

Hook 事件与 App 状态的严格映射关系如下表所示：

|App 状态|触发 Hook 事件|条件 / Matcher|携带数据 (Payload)|UI 响应行为|
|---|---|---|---|---|
|**🔵 Processing**|`UserPromptSubmit`|用户按下回车|`status: "processing"`<br><br>`title: prompt[:50]`|1. 列表重排序<br><br>2. 呼吸灯激活<br><br>3. 更新状态文案|
|**🔵 Processing**|`PostToolUse`|任意工具执行完毕|`status: "processing"`<br><br>`usage: filesize`|1. 更新 **10段式能量条**<br><br>2. 若 >90% 变红预警|
|**🔴 Waiting**|`PermissionRequest`|任意工具请求权限|`status: "waiting"`<br><br>`reason: tool_name`|1. **强制置顶**<br><br>2. 卡片红光脉冲<br><br>3. 发送 macOS 通知|
|**🔴 Waiting**|`Notification`|`permission_prompt`<br><br>`idle_prompt`|`status: "waiting"`<br><br>`reason: message`|同上|
|**🟢 Completed**|`Stop`|任务正常结束|`status: "completed"`|1. 列表沉底<br><br>2. 状态条变绿<br><br>3. 发送完成通知|
|**⚪️ Destroyed**|`SessionEnd`|会话终止/退出|`status: "destroyed"`|1. 从列表中移除<br><br>2. 若列表为空，显示 **Standby Mode**|

## 4. 关键技术难点与解决方案

### 4.1 上下文容量映射 (Segment Calculation)

**逻辑**：将连续的文件大小映射为离散的 10 段。

```
// Swift 伪代码
let maxContextBytes = 1_000_000 // 1MB 基准
let currentBytes = payload.usage
let percentage = min(Double(currentBytes) / Double(maxContextBytes), 1.0)
let segmentsFilled = Int(ceil(percentage * 10)) // 1-10 格

// 颜色映射
func segmentColor(index: Int) -> Color {
    if index <= 5 { return .themeGray }
    if index <= 8 { return .themeAmber }
    return .themeRed
}
```

### 4.2 字体加载与适配

Beacon System 依赖单宽字体（Monospaced）传达复古感。

- **方案**：内嵌开源字体 **JetBrains Mono** 或 **SF Mono**。
    
- **回退**：若加载失败，回退至 `Font.system(.body, design: .monospaced)`。
    

### 4.3 性能控制

**问题**：高频的 `PostToolUse` 事件可能导致 UI 刷新闪烁或 CPU 占用。 **方案**：

- **Swift 端**：使用 `Combine` 的 `throttle` 操作符，限制 UI 刷新频率（如每 500ms 刷新一次）。
    
- **Hook 端**：仅发送必要的增量数据，不发送完整的 Transcript 内容。
    

## 5. 实施路线图 (Roadmap)

### Phase 1: 核心链路打通 (MVP)

- 完成 SwiftUI 基础框架搭建（MenuBarExtra）。
    
- 实现 Bash Hook 脚本，跑通 HTTP 通信。
    
- 实现基础状态（Icon 变色）与列表展示。
    

### Phase 2: UI 视觉重构 (Beacon System)

- 实现 **Session Card** 自定义 View。
    
- 实现 **Segmented Bar** 组件。
    
- 导入双主题配色 (Assets.xcassets) 与字体。
    
- 实现 **Priority Sorting** 算法。
    

### Phase 3: 智能化与高级功能

- **智能标题**：在 App 端集成小型 NLP 逻辑（或简单的正则），更精准地从 Prompt 提取标题。
    
- **VS Code 集成**：识别 IDE 环境并做差异化跳转。
    
- **一键 Kill**：在 App 端通过 `pkill` 或 session id 反向终止终端进程（需探索权限边界）。