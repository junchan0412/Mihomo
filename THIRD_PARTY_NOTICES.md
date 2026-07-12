# Mihomo Third-Party Notices

This document is a lightweight release SBOM and license notice for bundled or configured third-party components.

| Component | Use | Source | License / Notes |
| --- | --- | --- | --- |
| mihomo | Network proxy core bundled under `Contents/Resources/Core/mihomo` when packaging succeeds. | https://github.com/MetaCubeX/mihomo | GPL-3.0-or-later. Verify the exact bundled binary version during release packaging. |
| Yams | YAML parsing and emitting in profile editing and runtime config generation. | https://github.com/jpsim/Yams | MIT License. Managed by Swift Package Manager. |
| Swift CryptoKit | Ed25519 update manifest signatures, SHA-256, AES-GCM and HKDF local secret vault operations. | Apple platform SDK | Apple platform framework; no vendored source. |
| age | Optional profile encryption helper configured by download URL. Not bundled by default. | https://github.com/FiloSottile/age | BSD-3-Clause. Downloaded only when the user enables/install profile encryption tooling. |
| zashboard | Optional external controller UI configured by download URL. Not bundled by default. | https://github.com/Zephyruso/zashboard | Check upstream license before redistributing a bundled copy. |
| MetaCubeX meta-rules-dat | Optional GeoIP/GeoSite data source configured by URL. Not bundled by default. | https://github.com/MetaCubeX/meta-rules-dat | Check upstream release terms before redistributing cached data. |

Release smoke checks:

- `script/release_smoke_test.sh <version>` validates the packaged app signature, bundle identifier, update manifest, Ed25519 metadata, latest manifest parity, and zip SHA-256.
- Release app bundles include this file at `Mihomo.app/Contents/Resources/THIRD_PARTY_NOTICES.md`; smoke tests fail if it is missing from the bundle or zip.
- GitHub Release assets should include `Mihomo-<version>-macOS-arm64.zip`, `Mihomo-<version>-update.json`, and `mihomo-update.json`.
