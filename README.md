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

1. Hook bridge detects source terminal/IDE and sends it in event payload.
2. Clicking `Jump` tries only that source target first.
3. If source is unknown or jump fails, a per-card terminal picker is shown.

You can also toggle panel theme quickly:
- Click the sun/moon icon in panel controls to switch dark/light.
