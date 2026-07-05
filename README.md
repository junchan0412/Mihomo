# Mihomo

Mihomo is a macOS-native SwiftUI-first controller for the mihomo core. This repository contains the MVP described in `Mihomo-macOS-development-report.md`: a professional desktop shell inspired by Surge's information architecture, while using mihomo as the runtime engine.

## Sixth MVP Scope

- SwiftUI-first macOS app with a native sidebar, toolbar, Settings scene, and Menu Bar Extra.
- AppKit-backed `NSTableView` and `NSTextView` bridges for dense connection/policy/profile tables and high-volume log scrolling.
- Simplified Chinese UI across the main window, Settings, diagnostics, logs, profile workflows, and menu bar actions.
- Runtime config dry-run with `mihomo -t`, candidate config promotion, previous config rollback, structured top-level YAML merge/cleanup, YAML fragments, JavaScript transform fragments, preview, and line diff.
- XPC Helper architecture: the main app handles UI/state and calls `dev.codex.Mihomo.Helper`; the helper performs privileged runtime validation, core start/stop, DNS/proxy changes, TUN snapshots/restores, permission checks, and LaunchDaemon management.
- Core start, stop, restart, and crash recovery routed through the Helper API with configurable retry limits.
- Bundled mihomo core support in release packages, managed core download/update from the Advanced page, and effective-core fallback between managed, configured, and bundled binaries.
- LaunchDaemon core management is retained for long-running, KeepAlive, boot-time startup, but install/uninstall/start/stop is now owned by the XPC Helper.
- System proxy snapshots and restoration through macOS `networksetup`, including repair from saved proxy/DNS state, are executed by the Helper.
- Optional automatic system DNS assignment on core start, with snapshot-based restoration on stop or app quit, is executed by the Helper.
- Launch-at-login registration through `SMAppService.mainApp`, designed to pair with "start core when Mihomo opens" for boot-time core startup.
- TUN recovery snapshots for DNS, proxy, route table, and default route state, plus administrator-authorized route rollback when privileged repair is needed.
- Local, remote, drag-and-drop, and `mihomo://` deep-link Profile import, queued remote subscription refresh, automatic refresh interval, failure notifications, certificate fingerprint pinning, and a built-in YAML editor.
- Policy search, sort, proxy selection, configurable single-node/group/all-node concurrent delay testing, and menu bar policy quick switching.
- Connection list filtering, process/rule/chain/network grouping, single-connection close, all-connection close, and a SwiftUI inspector.
- Rule table with persisted disabled-rule filtering for generated runtime config.
- Rule Provider and Proxy Provider views with local YAML parsing, Controller reads, and update actions.
- Advanced DNS and Sniffer settings written into generated mihomo runtime config.
- External UI management for zashboard/metacubexd-style zip packages, with generated `external-ui` config.
- GeoIP/GeoSite download/update workflow.
- Local zip backup/restore, WebDAV upload/download restore, and Gist JSON sync for settings, profiles, fragments, and disabled rules.
- Remote HTTP API is local-only by default and only binds remotely when explicitly enabled; Controller requests support Bearer secret.
- Realtime traffic sampling with a lightweight native graph.
- Log filtering, pause/resume, retention days, rolling file size, persistent app log output, and separate core log output under `~/Library/Logs/Mihomo/`.
- Expanded diagnostics for binary, Helper health, version, runtime dry-run, Controller, TUN status, system proxy snapshots, logs, subscription queues, advanced fragments, managed core, remote API, external UI, Geo data, and refresh failures.

This MVP adds the XPC Helper boundary and app-bundled launch daemon plist. Production signing, notarization, and Sub-Store remain future hardening work.

## Requirements

- macOS 14 or later.
- Swift 5.9+ toolchain.
- Xcode 27 beta is supported through `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer"`. The build script uses that path automatically when present.
- A mihomo binary installed locally, the bundled release core, or a managed core installed from the Advanced page.

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
./script/package_release.sh 0.6.0
```

This downloads a release mihomo core into `vendor/mihomo` when needed, stages it inside `Mihomo.app/Contents/Resources/Core/`, stages `MihomoHelper` under `Contents/Library/LaunchServices/`, includes the Helper daemon plist under `Contents/Library/LaunchDaemons/`, and creates a zip artifact under `dist/releases/` without AppleDouble metadata.
