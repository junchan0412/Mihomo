# Mihomo

Mihomo is a macOS-native SwiftUI-first controller for the mihomo core. This repository contains the MVP described in `Mihomo-macOS-development-report.md`: a professional desktop shell inspired by Surge's information architecture, while using mihomo as the runtime engine.

## 1.0 MVP Scope

- SwiftUI-first macOS app with a native sidebar, toolbar, Settings scene, and Menu Bar Extra.
- AppKit-backed `NSTableView` and `NSTextView` bridges for dense connection/policy/profile tables and high-volume log scrolling, with explicit VoiceOver labels, table/text-area roles, and keyboard activation for detail tables.
- Simplified Chinese UI across the main window, Settings, diagnostics, logs, profile workflows, and menu bar actions.
- Runtime config dry-run with `mihomo -t`, candidate config promotion, previous config rollback, Yams-backed YAML structure merge/cleanup, YAML fragments, JavaScript transform fragments, preview, line diff, field-source Inspector, and schema risk checks for rules/proxy-groups/DNS/TUN/Provider/Sniffer, including suspicious rule types, malformed domain/CIDR/port/network/process/GEOIP/IP-ASN rule payloads, missing policy-group members, Proxy/Rule Provider reference mismatches, suspicious DNS resolver schemes, unsupported TUN stacks, malformed Sniffer domains, and Rule Provider behavior mismatches. JavaScript transforms run in a separately signed worker with fragment/input/output budgets and a 1.5-second execution timeout.
- XPC Helper architecture: the main app handles UI/state and calls `dev.codex.Mihomo.Helper`; the helper performs privileged runtime validation, core start/stop, DNS/proxy changes, TUN snapshots/restores, permission checks, and LaunchDaemon management. The Helper rejects XPC clients outside the signed `dev.codex.Mihomo` app bundle, binds accepted clients to the Helper's containing app bundle, and validates privileged file paths against the accepted user's Mihomo App Support/Logs allowlist before touching disk or launching core.
- Configuration-fragment parsing, managed artifact installation, backup/restore, diagnostic redaction, Profile quality validation/YAML helpers, Profile quality pane UI, Profile page supporting panes, Policy page supporting views, Advanced artifact panes, Resource page supporting views, and Settings supporting views live in separate services, focused extensions, or dedicated views so their persistence, download, schema-check, presentation, and data-boundary rules can evolve independently. Settings persistence and profile/runtime presentation models are likewise separated without changing their on-disk Codable schema; the settings JSON round-trip, legacy fallback, checksum defaults, and secret redaction paths are covered by XCTest. AppStore backup/WebDAV/Gist, Profile import/refresh/edit/statistics, Provider/Geo resource coordination, network takeover coordination, core lifecycle coordination, config/rule editing coordination, diagnostics/logging coordination, policy delay-testing coordination, advanced artifact installation coordination, software-update coordination, Helper management coordination, deep-link import coordination, and settings migration coordination are isolated in dedicated extensions.
- Helper audit and repair diagnostics for bundle layout, plist contents, ad-hoc signing identifiers, SMAppService status, notarization/Gatekeeper state, and root privilege reachability.
- Core start, stop, restart, and crash recovery routed through the Helper API with configurable retry limits.
- Bundled mihomo core support in release packages, managed remote core download/update from Settings, and explicit switching between managed remote and bundled binaries. Local external core paths remain visible for diagnostics/development, but privileged Helper launch is limited to allowlisted `Core/mihomo` locations under Mihomo App Support or the app bundle.
- Managed core, Age tool, External UI, and Geo data downloads require a SHA-256 checksum before installation; a missing or mismatched checksum preserves the current executable, UI, or Geo file. Because the default External UI/Geo URLs track mutable upstream releases, users must obtain and enter the matching checksum before updating them.
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
- Connection list filtering, process/rule/chain/network grouping, single-connection close, all-connection close, Controller WebSocket event streams with polling fallback and tested reconnect backoff state, and a SwiftUI inspector.
- Surge-style rule table with ID/type/value/policy/usage/note columns, persisted disabled-rule filtering for generated runtime config, profile rule add/edit/delete actions, and live hit counts from Controller connections.
- Rule Provider and Proxy Provider views with local YAML AST parsing, Controller reads, direct download updates that work without the mihomo core running, runtime-directory path fencing for downloaded resources, concurrent one-click external resource updates, previous-version backup and rollback, persisted update history, item/reference counts, readiness filtering, and hit counts when Controller data exposes enough detail. Provider rollback tests cover preserving the current file when a backup is missing and skipping pruned history entries when selecting the latest rollback candidate.
- Provider updates, managed core downloads, Age tool installs, External UI installs, Geo updates, WebDAV/Gist backup sync, GitHub update checks, certificate-pinned profile fetches, and local Controller API calls use bounded request/resource timeouts instead of the process-wide shared session defaults.
- Advanced DNS and Sniffer settings written into generated mihomo runtime config. Profile quality checks flag suspicious rule type typos, domain rule payloads that look like URLs, CIDR address-family mismatches, invalid port/network/process/GEOIP/IP-ASN rule payloads, missing proxy-group members, Proxy/Rule Provider use mismatches, DNS resolver schemes, unsupported TUN stacks, malformed Sniffer domains, and Rule Provider behavior mismatches before running `mihomo -t`.
- External UI management for zashboard/metacubexd-style zip packages, with SHA-256 verification, symlink rejection, staged replacement, and generated `external-ui` config.
- GeoIP/GeoSite download/update workflow, with SHA-256 verification and rollback-safe replacement, runtime-directory synchronization before dry-run/start/LaunchDaemon install, and retry after Geo data failures.
- Local zip backup/restore, WebDAV upload/download restore, and Gist JSON sync for settings, profiles, fragments, and disabled rules. Zip restore preflights entries, rejects traversal/symlinks/non-allowlisted paths, restores through a temporary directory, and keeps restored files inside App Support. Controller/WebDAV/Gist secrets are stored outside `settings.json` in an AES-GCM local secret vault, not Keychain, to avoid update-time Keychain re-authorization with ad-hoc signatures. Normal backups stay redacted by default and redacted restores preserve the current local vault secrets; the Advanced backup pane exposes passphrase-encrypted portable secret bundle import/export, an explicit manual secret apply action, and redacted ready/missing indicators for restore workflows where users re-enter credentials by hand.
- Fixed ad-hoc signing identifiers for the app, Helper, and bundled mihomo core, release manifest generation, and a verified in-app updater that checks GitHub Releases for the latest signed manifest before applying Ed25519 manifest signature, SHA-256, bundle id, and signing identifier checks. Downloaded update packages are preflighted before the install script is written, so bad hashes, malformed zips, and bundle id mismatches fail before app replacement starts; installer tests cover restoring the previous app bundle when replacement copy or post-copy signature verification fails.
- Optional Age Profile encryption: the Advanced page can install managed `age`/`age-keygen`, generate an Age identity, and transparently encrypt/decrypt full Profile YAML on disk while runtime generation uses decrypted content.
- Remote HTTP API is local-only by default and only binds remotely when explicitly enabled; Controller requests support Bearer secret.
- Realtime traffic sampling with a lightweight native graph, using Controller WebSocket traffic events when available and polling as fallback.
- Log filtering, pause/resume, global recent-event toolbar menu, retention days, rolling file size, persistent app log output, and separate core log output under `~/Library/Logs/Mihomo/`.
- Expanded diagnostics for binary, Helper health, version, runtime app binding, runtime dry-run, Controller, TUN status, system proxy snapshots, redacted runtime/log exports, subscription queues, advanced fragments, managed core, remote API, external UI, Geo data, and refresh failures.

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

Pull requests and pushes to `main`/`codex/**` run GitHub Actions CI with `git diff --check`, `swift test`, and a non-interactive release-bundle gate. The test suite covers update version comparison, pre-install package validation failures for bad SHA-256, missing `Mihomo.app`, and bundle id mismatch, installer rollback when replacement copy or post-copy signature verification fails, Controller WebSocket reconnect/fallback backoff behavior, and Provider rollback history/file-preservation edges. The gate rebuilds the app bundle, verifies nested signatures, required Helper/JS worker/notices files, `Info.plist` identity, release signing identity, and the corresponding zip entries, then writes a non-blocking maintainability report for Swift files above the configured size thresholds. Release smoke cryptographically verifies the Ed25519 update manifest signature against the compiled public key and confirms a tampered manifest copy is rejected. Private-key manifest signing remains a protected release-environment step.

To run the maintainability report locally:

```bash
./script/maintainability_audit.sh
```

The v1.8.70 maintainability pass split the connection detail window out of `ActivityView.swift` into `ConnectionDetailPanelView.swift`, after v1.8.69 moved the rule editor sheet into `RuleEditorSheet.swift`; the local report now shows 110 scanned Swift files, 5 warning files, 0 over-max files, and `HelperNetworkTools.swift` as the largest file at 384 lines.

## Network Takeover Smoke

```bash
./script/network_takeover_smoke.sh
./script/network_takeover_smoke.sh --assert-clean
./script/network_takeover_smoke.sh --summary dist/smoke/network-before.tsv
./script/network_takeover_smoke.sh --baseline dist/smoke/network-before.tsv --assert-clean
./script/network_takeover_smoke.sh --scenario tun-crash-restore --phase before --note "baseline before enabling TUN"
```

The default mode is read-only and writes a Markdown report under `dist/smoke/` with network services, HTTP/HTTPS/SOCKS proxy state, DNS overrides, default routes, utun interfaces, route tables, resolver state, Mihomo recovery snapshot files, and optional manual scenario notes. It also writes a TSV summary next to the report for before/after comparisons. Use `--scenario`, `--phase` values such as `before`, `enabled`, `after-stop`, `after-quit`, `after-crash`, or `recovered`, and repeatable `--note` values to label manual proxy/DNS/TUN start-stop, quit, or crash-recovery evidence without affecting TSV baseline comparisons. Use `--assert-clean` after manual proxy/DNS/TUN start-stop testing when the system should be restored; it fails on leftover common proxy settings, recovery snapshots, TUN routes, or `--baseline` summary differences.

## Accessibility QA Checklist

```bash
./script/accessibility_qa_checklist.sh
./script/accessibility_qa_checklist.sh --scenario voiceover-main-tabs --note "VoiceOver pass on release candidate"
```

The checklist script is read-only and writes a Markdown report under `dist/accessibility/` for manual VoiceOver, keyboard-only, and Accessibility Inspector passes. It records the app bundle identity/version/build when `dist/Mihomo.app` exists, plus scenario notes and page-level checks for Overview, Profiles, Policies, Resources, Logs, Diagnostics, Advanced, and Settings.

## Release Build

```bash
./script/package_release.sh 1.0.0
```

This downloads a release mihomo core into `vendor/mihomo` when needed, stages it inside `Mihomo.app/Contents/Resources/Core/`, stages `THIRD_PARTY_NOTICES.md` and `MihomoJSWorker` under `Contents/Resources/`, stages `MihomoHelper` under `Contents/Library/LaunchServices/`, includes the Helper daemon plist under `Contents/Library/LaunchDaemons/`, signs nested code with fixed identifiers, creates a zip artifact under `dist/releases/`, and writes Ed25519-signed `Mihomo-<version>-update.json` plus `mihomo-update.json`. By default the local build uses ad-hoc signing; a protected release machine can set `MIHOMO_CODESIGN_IDENTITY`, `MIHOMO_EXPECTED_TEAM_ID`, `MIHOMO_REQUIRE_DEVELOPER_ID=1`, `MIHOMO_REQUIRE_NOTARIZATION=1`, and `MIHOMO_REQUIRE_STAPLED_TICKET=1` to require Developer ID signing, Team ID/designated requirement checks, Gatekeeper assessment, and stapled notarization validation. `script/release_smoke_test.sh` verifies manifest fields, verifies the Ed25519 signature, checks that a mutated manifest fails verification, runs `script/verify_release_identity.sh`, runs `script/update_replacement_smoke.sh` in a temporary directory to prove a release zip can replace a current app bundle, preserve the manifest version/build, keep the embedded Helper and JS worker signed with their expected identifiers, restore the app after a bad candidate, and writes `Mihomo-<version>-provenance.md` with artifact checksums, manifest fields, bundle identity, signing summaries, and required zip entries.

To regenerate only the provenance report for an already packaged release:

```bash
./script/release_provenance_report.sh 1.0.0
```

To prepare a protected Developer ID release environment without mutating signing state:

```bash
./script/protected_release_checklist.sh --version 1.0.0
./script/protected_release_checklist.sh --version 1.0.0 --scenario developer-id-notarization-dry-run --note "verify release keychain before packaging"
```

The protected release checklist is read-only and writes a Markdown report under `dist/release-checks/` with tool availability, Mihomo release environment variable readiness, Developer ID identity lookup status, notarization/stapler checks, and the command template expected on the protected release machine.

To exercise only the app replacement smoke for an already packaged release:

```bash
./script/update_replacement_smoke.sh 1.0.0
```

The update signing private key is read from `MIHOMO_UPDATE_PRIVATE_KEY` or `~/.mihomo-update-signing/ed25519.private`. The matching public key is compiled into the app; changing release keys requires shipping an app build that trusts the new public key before using it.

For first install from a downloaded zip without notarization:

```bash
xattr -dr com.apple.quarantine /Applications/Mihomo.app
```

For later in-app updates, upload the zip plus `mihomo-update.json` to the GitHub Release. Mihomo checks the latest GitHub Release directly from Settings, the app menu, or the menu bar, then verifies the manifest and package before handing off to the replacement script.
