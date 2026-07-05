# Mihomo

Mihomo is a macOS-native SwiftUI-first controller for the mihomo core. This repository contains the MVP described in `Mihomo-macOS-development-report.md`: a professional desktop shell inspired by Surge's information architecture, while using mihomo as the runtime engine.

## Fourth MVP Scope

- SwiftUI-first macOS app with a native sidebar, toolbar, Settings scene, and Menu Bar Extra.
- AppKit-backed `NSTableView` and `NSTextView` bridges for dense connection/policy/profile tables and high-volume log scrolling.
- Simplified Chinese UI across the main window, Settings, diagnostics, logs, profile workflows, and menu bar actions.
- Runtime config dry-run with `mihomo -t`, candidate config promotion, previous config rollback, and structured top-level YAML merge/cleanup for managed mihomo keys.
- Core start, stop, restart, and crash recovery with configurable retry limits.
- System proxy snapshots and restoration through macOS `networksetup`, including repair from saved proxy/DNS state.
- Launch-at-login registration through `SMAppService.mainApp`, designed to pair with "start core when Mihomo opens" for boot-time core startup.
- TUN recovery snapshots for DNS, proxy, route table, and default route state, plus administrator-authorized route rollback when privileged repair is needed.
- Local, remote, and drag-and-drop Profile import, queued remote subscription refresh, automatic refresh interval, failure notifications, and a built-in YAML editor.
- Policy search, sort, proxy selection, configurable single-node/group/all-node concurrent delay testing, and menu bar policy quick switching.
- Connection list filtering, process/rule/chain/network grouping, single-connection close, all-connection close, and a SwiftUI inspector.
- Realtime traffic sampling with a lightweight native graph.
- Log filtering, pause/resume, retention days, rolling file size, persistent app log output, and separate core log output under `~/Library/Logs/Mihomo/`.
- Expanded diagnostics for binary, version, runtime dry-run, Controller, TUN status, system proxy snapshots, logs, subscription queues, and refresh failures.

The third MVP still keeps a dedicated privileged helper, notarized distribution, Sub-Store, WebDAV/Gist sync, and JS override scripting out of scope. A future helper can make TUN repair quieter, but this MVP already provides a real administrator-authorized recovery path.

## Requirements

- macOS 14 or later.
- Swift 5.9+ toolchain.
- Xcode 27 beta is supported through `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer"`. The build script uses that path automatically when present.
- A mihomo binary installed locally, for example `/opt/homebrew/bin/mihomo`, or a custom path set in Settings.

## Build And Run

```bash
./script/build_and_run.sh
```

The script builds with SwiftPM, stages `dist/Mihomo.app`, and launches it as a real macOS app bundle.

Useful modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

## Release Build

```bash
./script/package_release.sh 0.4.0
```

This creates a zip artifact under `dist/releases/` without AppleDouble metadata.
