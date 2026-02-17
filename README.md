# TwinTub

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)
[![macOS](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos)

**TwinTub** is a macOS Menu Bar application for monitoring Claude Code CLI multi-session status. It provides a "Native & Retro" design experience with immersive terminal aesthetics.

![TwinTub Screenshot](docs/screenshot.png)

## Features

- **Real-time Status Monitoring**: Track idle, processing, waiting, and completed states
- **Multi-session Support**: Monitor multiple Claude Code sessions simultaneously
- **Terminal Jump**: Click to jump back to the original terminal tab
- **System Notifications**: Get notified when sessions need attention or complete
- **Dark/Light Theme**: Automatic system detection with manual override
- **Context Usage Visualization**: 10-segment progress bar for context window usage

### Supported Terminals

- **Terminals**: Terminal.app, iTerm2, Warp, Ghostty, WezTerm, Kitty, Alacritty, Tabby, Hyper, Rio, Kaku
- **IDE Terminals**: Cursor, VS Code, Zed

## Installation

### Homebrew (Recommended)

```bash
brew tap twintub/tap
brew install twintub
```

### Manual Installation

1. Download the latest release from [Releases](https://github.com/YOUR_USERNAME/TwinTub/releases)
2. Extract `TwinTub.app` to `/Applications`
3. First launch: Right-click → Open (required for unsigned apps)

### From Source

```bash
git clone https://github.com/YOUR_USERNAME/TwinTub.git
cd TwinTub
./scripts/run_twintub_app.sh
```

## Quick Start

1. **Launch TwinTub** - The app appears in your menu bar

2. **Install Hooks** (required for monitoring):
   ```bash
   ./hooks/install_hooks.sh
   ```

3. **Start using Claude Code** - Sessions appear automatically

4. **Click to Jump** - Click the Jump button to return to the terminal

## Development

### Build

```bash
# Using the build script (recommended)
./scripts/run_twintub_app.sh --no-run

# Using xcodebuild directly
xcodebuild -scheme TwinTub -destination 'platform=macOS' build
```

### Test

```bash
xcodebuild -scheme TwinTub -destination 'platform=macOS' test
```

### Health Check

```bash
curl -i http://127.0.0.1:55771/health
```

### Simulate Events

```bash
./scripts/simulate_events.sh
```

## Architecture

TwinTub uses a **Sidecar Pattern** for Claude Code CLI integration:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Claude Code CLI │────▶│  Hook Bridge    │────▶│  SwiftUI App    │
│   (Terminal)    │     │  (Bash/cURL)    │     │  (Menu Bar)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

Internal architecture follows **Redux-like Pattern**:

```
TwinTubEvent → EventBridge → SessionStore → SwiftUI Views
                  │              │
                  │              ├─→ SessionReducer (pure)
                  │              ├─→ SessionLivenessMonitor
                  │              └─→ NotificationService
                  │
                  └─→ Coalesce by session, 100ms flush
```

### Key Files

| File | Purpose |
|------|---------|
| `TwinTubApp/App/TwinTubApp.swift` | App entry point, EventBridge, AppDelegate |
| `TwinTubApp/Core/Configuration/TwinTubConfig.swift` | Global configuration constants |
| `TwinTubApp/Core/State/SessionReducer.swift` | Pure function for state mutations |
| `TwinTubApp/Core/Store/SessionStore.swift` | State management |
| `TwinTubApp/Core/Services/SessionLivenessMonitor.swift` | Process/TTY validation |

## Session Lifecycle

Sessions are managed through dual-source truth:

1. **Hook Events**: Drive session creation and status updates
2. **Liveness Monitor**: Background validation via `ps` snapshots every 5 seconds

State transitions:
```
alive → suspectOffline (first miss) → offline (grace exceeded) → terminated
```

Default configuration:
- **Offline grace period**: 20 seconds
- **Terminated retention**: 300 seconds
- **Hard expiry**: 1800 seconds

## Terminal Jump Behavior

1. Try exact TTY match (Terminal/iTerm2)
2. Fallback to opening source app at `cwd`
3. Final fallback to terminal picker

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Acknowledgments

- Built with SwiftUI and AppKit
- Inspired by the "Native & Retro" design philosophy
- Thanks to all contributors
