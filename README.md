# Mihomo

Mihomo is a macOS-native SwiftUI-first controller for the mihomo core. This repository contains the MVP described in `Mihomo-macOS-development-report.md`: a professional desktop shell inspired by Surge's information architecture, while using mihomo as the runtime engine.

## 1.0 MVP Scope

- SwiftUI-first macOS app with a native sidebar, toolbar, Settings scene, and Menu Bar Extra.
- AppKit-backed `NSTableView` and `NSTextView` bridges for dense connection/policy/profile tables and high-volume log scrolling.
- Simplified Chinese UI across the main window, Settings, diagnostics, logs, profile workflows, and menu bar actions.
- Runtime config dry-run with `mihomo -t`, candidate config promotion, previous config rollback, Yams-backed YAML structure merge/cleanup, YAML fragments, JavaScript transform fragments, preview, line diff, field-source Inspector, and schema risk checks for DNS/TUN/Provider/Sniffer.
- XPC Helper architecture: the main app handles UI/state and calls `dev.codex.Mihomo.Helper`; the helper performs privileged runtime validation, core start/stop, DNS/proxy changes, TUN snapshots/restores, permission checks, and LaunchDaemon management. The Helper now rejects XPC clients outside the signed `dev.codex.Mihomo` app bundle.
- Helper audit and repair diagnostics for bundle layout, plist contents, ad-hoc signing identifiers, SMAppService status, notarization/Gatekeeper state, and root privilege reachability.
- Core start, stop, restart, and crash recovery routed through the Helper API with configurable retry limits.
- Bundled mihomo core support in release packages, managed remote core download/update from Settings, and explicit switching between managed remote, bundled, and local external binaries.
- LaunchDaemon core management is retained for long-running, KeepAlive, boot-time startup, but install/uninstall/start/stop is now owned by the XPC Helper.
- System proxy snapshots and restoration through macOS `networksetup`, including repair from saved proxy/DNS state, are executed by the Helper.
- Optional automatic system DNS assignment on core start, with snapshot-based restoration on stop or app quit, is executed by the Helper.
- Network Security Center centralizes system proxy, system DNS, TUN routing, recovery snapshots, current takeover health, repair actions, diagnostics, and export.
- Launch-at-login registration through `SMAppService.mainApp`, designed to pair with "start core when Mihomo opens" for boot-time core startup.
- TUN recovery snapshots for DNS, proxy, route table, and default route state, plus administrator-authorized route rollback when privileged repair is needed.
- Local, remote, drag-and-drop, and `mihomo://` deep-link Profile import, queued remote subscription refresh, automatic refresh interval, failure notifications, certificate fingerprint pinning, scrollable Profile management, Profile statistics by default, profile delete/active-state controls, dedicated Profile editor windows, dedicated override-fragment windows, and structured UI editing for policy groups and rules.
- Policy group add/edit/delete from the Profile UI. When deleting a group used by rules, the app asks whether to replace those rules with another policy or delete the referencing rules.
- Policy search, sort, proxy selection, configurable single-node/group/all-node concurrent delay testing, and menu bar policy quick switching.
- Offline policy preview: policy groups and candidates can be browsed from the active local Profile even when the mihomo core or Controller is not running.
- Connection list filtering, process/rule/chain/network grouping, single-connection close, all-connection close, and a SwiftUI inspector.
- Surge-style rule table with ID/type/value/policy/usage/note columns, persisted disabled-rule filtering for generated runtime config, profile rule add/edit/delete actions, and live hit counts from Controller connections.
- Rule Provider and Proxy Provider views with local YAML AST parsing, Controller reads, direct download updates that work without the mihomo core running, concurrent one-click external resource updates, previous-version backup and rollback, persisted update history, item/reference counts, readiness filtering, and hit counts when Controller data exposes enough detail.
- Advanced DNS and Sniffer settings written into generated mihomo runtime config.
- External UI management for zashboard/metacubexd-style zip packages, with generated `external-ui` config.
- GeoIP/GeoSite download/update workflow, including runtime-directory synchronization before dry-run/start/LaunchDaemon install and retry after Geo data failures.
- Local zip backup/restore, WebDAV upload/download restore, and Gist JSON sync for settings, profiles, fragments, and disabled rules. Controller/WebDAV/Gist secrets are stored outside `settings.json` in an AES-GCM local secret vault, not Keychain, to avoid update-time Keychain re-authorization with ad-hoc signatures.
- Fixed ad-hoc signing identifiers for the app, Helper, and bundled mihomo core, release manifest generation, and a verified in-app updater that checks GitHub Releases for the latest signed manifest before applying Ed25519 manifest signature, SHA-256, bundle id, and signing identifier checks.
- Optional Age Profile encryption: the Advanced page can install managed `age`/`age-keygen`, generate an Age identity, and transparently encrypt/decrypt full Profile YAML on disk while runtime generation uses decrypted content.
- Remote HTTP API is local-only by default and only binds remotely when explicitly enabled; Controller requests support Bearer secret.
- Realtime traffic sampling with a lightweight native graph.
- Log filtering, pause/resume, global recent-event overlay, retention days, rolling file size, persistent app log output, and separate core log output under `~/Library/Logs/Mihomo/`.
- Expanded diagnostics for binary, Helper health, version, runtime dry-run, Controller, TUN status, system proxy snapshots, logs, subscription queues, advanced fragments, managed core, remote API, external UI, Geo data, and refresh failures.

This MVP targets distribution without an Apple Developer account: releases are not notarized, so the first downloaded install still needs quarantine removal. Later updates can be installed from inside the app after Ed25519 manifest verification and signature-identifier verification. Sub-Store remains deferred until the core app shape is stable.

## Requirements

- macOS 14 or later.
- Swift 5.9+ toolchain.
- Xcode 27 beta is supported through `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer"`. The build script uses that path automatically when present.
- A mihomo binary installed locally, the bundled release core, or a managed core installed from Settings.

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
./script/package_release.sh 1.0.0
```

This downloads a release mihomo core into `vendor/mihomo` when needed, stages it inside `Mihomo.app/Contents/Resources/Core/`, stages `MihomoHelper` under `Contents/Library/LaunchServices/`, includes the Helper daemon plist under `Contents/Library/LaunchDaemons/`, signs nested code with fixed ad-hoc identifiers, creates a zip artifact under `dist/releases/`, and writes Ed25519-signed `Mihomo-<version>-update.json` plus `mihomo-update.json`.

The update signing private key is read from `MIHOMO_UPDATE_PRIVATE_KEY` or `~/.mihomo-update-signing/ed25519.private`. The matching public key is compiled into the app; changing release keys requires shipping an app build that trusts the new public key before using it.

For first install from a downloaded zip without notarization:

```bash
xattr -dr com.apple.quarantine /Applications/Mihomo.app
```

For later in-app updates, upload the zip plus `mihomo-update.json` to the GitHub Release. Mihomo checks the latest GitHub Release directly from Settings, the app menu, or the menu bar.
