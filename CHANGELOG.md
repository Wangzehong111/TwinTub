# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-02-17

### Added

- Initial public release of TwinTub
- Menu bar app for monitoring Claude Code CLI multi-session status
- Real-time session status tracking (idle, processing, waiting, completed)
- Session liveness monitoring with dual-source truth (hook events + process/TTY validation)
- Terminal jump functionality - click to jump back to the original terminal tab
- Support for multiple terminal emulators:
  - Terminal.app, iTerm2, Warp, Ghostty, WezTerm, Kitty, Alacritty, Tabby, Hyper, Rio, Kaku
  - IDE terminals: Cursor, VS Code, Zed
- System notifications for session state changes
- Dark/Light theme support with automatic system detection
- Context window usage visualization (10-segment progress bar)
- Hook-based event bridge with 100ms flush interval for high-frequency events
- Automatic session cleanup with configurable grace periods
- Single instance enforcement to prevent duplicate menu bar apps

### Technical

- HTTP server listening on port 55771 (configurable via `TWINTUB_PORT` environment variable)
- Redux-like state management pattern (Event → Reducer → Store → View)
- Swift Package Manager support
- Comprehensive test suite

### Configuration

- Offline grace period: 20 seconds
- Terminated session retention: 300 seconds
- Hard expiry: 1800 seconds
- Notification silence window: 120 seconds
- Notification escalation window: 180 seconds

[1.0.0]: https://github.com/YOUR_USERNAME/TwinTub/releases/tag/v1.0.0
