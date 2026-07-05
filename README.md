# Mihomo

Mihomo is a macOS-native AppKit controller for the mihomo core. This repository contains the MVP described in `Mihomo-macOS-development-report.md`: a professional desktop shell inspired by Surge's information architecture, while using mihomo as the runtime engine.

## MVP Scope

- Native macOS AppKit app with sidebar, toolbar, settings window, and menu bar status item.
- Local or remote Profile import.
- Runtime mihomo config generation.
- Start, stop, and refresh mihomo from the app.
- Controller integration for version, mode, policy groups, proxy selection, and connections.
- System proxy toggle through macOS `networksetup`.
- Logs, diagnostics, and basic activity view.

The first MVP intentionally keeps privileged helper installation, notarized distribution, Sub-Store, WebDAV/Gist sync, and JS override scripting out of scope. Those are listed as later hardening and advanced milestones in the report.

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
./script/package_release.sh
```

This creates a zip artifact under `dist/releases/` without AppleDouble metadata.
