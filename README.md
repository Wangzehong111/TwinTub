# Beacon

Menu bar app for Claude Code multi-session monitoring.

## Run (recommended)

```bash
cd /Users/wangzehong/PycharmProjects/Beacon
./scripts/run_beacon_app.sh
```

This builds `Beacon`, packages it as `.build/Beacon.app`, and launches it so `mainBundle` is valid.

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
