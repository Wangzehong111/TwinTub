# Beacon

Menu bar app for Claude Code multi-session monitoring.

## Run (recommended)

```bash
cd /Users/wangzehong/PycharmProjects/Beacon
./scripts/run_beacon_app.sh
```

This builds `Beacon`, packages it as `dist/Beacon.app`, and launches it so `mainBundle` is valid.

## Build

```bash
xcodebuild -scheme Beacon -destination 'platform=macOS' build
```

## Test

```bash
xcodebuild -scheme Beacon -destination 'platform=macOS' test
```

## Hook install

```bash
./hooks/install_hooks.sh
```

## Simulate events

```bash
./scripts/simulate_events.sh
```

## Jump behavior

Beacon now follows source terminal per session:

1. Hook bridge detects source terminal/IDE and also sends terminal context (`terminal_tty`, `shell_pid`, `terminal_session_id`).
2. Clicking `Jump` first tries to focus the exact original Terminal/iTerm tab by tty.
3. If exact match is unavailable, Beacon falls back to opening the source app at `cwd`.
4. If source is unknown or jump fails, a per-card terminal picker is shown.

### Supported targets (auto-detect + manual fallback)

- Terminals: `Terminal.app`, `iTerm2`, `Warp`, `Ghostty`, `WezTerm`, `Kitty`, `Alacritty`, `Tabby`, `Hyper`, `Rio`, `Kaku`
- IDE terminals: `Cursor`, `VS Code`, `Zed`

Compatibility baseline:

1. Prefer focusing existing session (when terminal exposes stable tab/TTY context).
2. Fallback to opening target app at `cwd`.
3. Final fallback to just activating/opening the target app.

## Session auto-cleanup

Beacon now uses dual-source session truth:

1. Hook events drive session creation and status updates.
2. A background liveness monitor reconciles sessions by local process/TTY state every 5 seconds.

Default lifecycle policy:

- Offline grace window: 20 seconds (prevents false cleanup during short terminal jitter).
- Missing process/TTY beyond grace: session is auto-terminated.
- Hard expiry: sessions without updates and without liveness evidence are removed after 30 minutes.
- `SessionEnd` has highest priority and immediately terminates the session state.

If stale sessions remain, re-run hook installation to verify required event mappings:

```bash
./hooks/install_hooks.sh
```

You can also toggle panel theme quickly:
- Click the sun/moon icon in panel controls to switch dark/light.
