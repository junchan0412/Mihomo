#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <version> [--output <path>]" >&2
  exit 2
fi

VERSION="$1"
shift

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/releases"
APP_BUNDLE="$ROOT_DIR/dist/Mihomo.app"
ZIP_PATH="$RELEASE_DIR/Mihomo-$VERSION-macOS-arm64.zip"
MANIFEST_PATH="$RELEASE_DIR/Mihomo-$VERSION-update.json"
LATEST_PATH="$RELEASE_DIR/mihomo-update.json"
OUTPUT_PATH="$RELEASE_DIR/Mihomo-$VERSION-provenance.md"
EXPECTED_PUBLIC_KEY="V4ac9RiJwSRBGJG/mD7xM2D40VB5feBCin6gCm8Cu3E="
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || {
        echo "usage: $0 <version> [--output <path>]" >&2
        exit 2
      }
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      echo "usage: $0 <version> [--output <path>]" >&2
      exit 0
      ;;
    *)
      echo "usage: $0 <version> [--output <path>]" >&2
      exit 2
      ;;
  esac
done

require_file() {
  local path="$1"
  [[ -e "$path" ]] || {
    echo "missing artifact: $path" >&2
    exit 1
  }
}

json_value() {
  local query="$1"
  jq -r "$query" "$MANIFEST_PATH"
}

plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || printf 'missing'
}

signature_value() {
  local name="$1"
  local text="$2"
  awk -F= -v key="$name" '$1 == key { print substr($0, length(key) + 2); exit }' <<<"$text"
}

zip_entry_status() {
  local entry="$1"
  if /usr/bin/unzip -l "$ZIP_PATH" "$entry" >/dev/null 2>&1; then
    printf 'present'
  else
    printf 'missing'
  fi
}

file_sha() {
  local path="$1"
  if [[ -f "$path" ]]; then
    /usr/bin/shasum -a 256 "$path" | awk '{ print $1 }'
  else
    printf 'missing'
  fi
}

codesign_summary() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf 'missing | missing | missing'
    return
  fi

  local details identifier team authority
  details="$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1 || true)"
  identifier="$(signature_value "Identifier" "$details")"
  team="$(signature_value "TeamIdentifier" "$details")"
  authority="$(awk -F= '$1 == "Authority" { print substr($0, 11); exit }' <<<"$details")"
  printf '%s | %s | %s' "${identifier:-missing}" "${team:-none}" "${authority:-ad-hoc}"
}

for path in "$ZIP_PATH" "$MANIFEST_PATH" "$LATEST_PATH" "$APP_BUNDLE"; do
  require_file "$path"
done
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for release provenance report" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

zip_sha="$(file_sha "$ZIP_PATH")"
manifest_sha="$(json_value '.sha256')"
manifest_version="$(json_value '.version')"
manifest_build="$(json_value '.build // ""')"
manifest_bundle="$(json_value '.bundleIdentifier')"
manifest_signing="$(json_value '.signingIdentifier')"
manifest_helper_signing="$(json_value '.helperSigningIdentifier')"
manifest_team="$(json_value '.teamIdentifier')"
manifest_url="$(json_value '.url')"
manifest_published="$(json_value '.publishedAt')"
manifest_algorithm="$(json_value '.signature.algorithm')"
manifest_public_key="$(json_value '.signature.publicKey')"
manifest_signature_status="valid"
if ! "$ROOT_DIR/script/sign_update_manifest.swift" --verify "$MANIFEST_PATH" "$EXPECTED_PUBLIC_KEY" >/dev/null 2>&1; then
  manifest_signature_status="invalid"
fi
latest_status="matches"
if ! cmp -s "$MANIFEST_PATH" "$LATEST_PATH"; then
  latest_status="differs"
fi
package_resolved_sha="$(file_sha "$ROOT_DIR/Package.resolved")"
notices_sha="$(file_sha "$ROOT_DIR/THIRD_PARTY_NOTICES.md")"
zip_size="$(stat -f '%z' "$ZIP_PATH" 2>/dev/null || wc -c <"$ZIP_PATH" | tr -d ' ')"
zip_entry_count="$(/usr/bin/unzip -l "$ZIP_PATH" 2>/dev/null | awk '/ files?$/ { print $2; exit }')"
app_signature="$(codesign_summary "$APP_BUNDLE")"
helper_signature="$(codesign_summary "$APP_BUNDLE/Contents/Library/LaunchServices/MihomoHelper")"
js_worker_signature="$(codesign_summary "$APP_BUNDLE/Contents/Resources/MihomoJSWorker")"
core_signature="$(codesign_summary "$APP_BUNDLE/Contents/Resources/Core/mihomo")"

cat >"$OUTPUT_PATH" <<REPORT
# Mihomo Release Provenance

- Timestamp UTC: $TIMESTAMP
- Version: $VERSION
- Host: $(/bin/hostname)
- App bundle: \`$APP_BUNDLE\`
- Release zip: \`$ZIP_PATH\`

## Artifact Checksums

| Artifact | SHA-256 | Size |
| --- | --- | --- |
| Release zip | \`$zip_sha\` | $zip_size bytes |
| Version manifest | \`$(file_sha "$MANIFEST_PATH")\` | $(stat -f '%z' "$MANIFEST_PATH" 2>/dev/null || wc -c <"$MANIFEST_PATH" | tr -d ' ') bytes |
| Latest manifest | \`$(file_sha "$LATEST_PATH")\` | $(stat -f '%z' "$LATEST_PATH" 2>/dev/null || wc -c <"$LATEST_PATH" | tr -d ' ') bytes |
| Package.resolved | \`$package_resolved_sha\` | $(if [[ -f "$ROOT_DIR/Package.resolved" ]]; then stat -f '%z' "$ROOT_DIR/Package.resolved"; else printf 'missing'; fi) |
| THIRD_PARTY_NOTICES.md | \`$notices_sha\` | $(stat -f '%z' "$ROOT_DIR/THIRD_PARTY_NOTICES.md" 2>/dev/null || printf 'missing') |

## Update Manifest

| Field | Value |
| --- | --- |
| version | \`$manifest_version\` |
| build | \`$manifest_build\` |
| url | \`$manifest_url\` |
| publishedAt | \`$manifest_published\` |
| bundleIdentifier | \`$manifest_bundle\` |
| signingIdentifier | \`$manifest_signing\` |
| helperSigningIdentifier | \`$manifest_helper_signing\` |
| teamIdentifier | \`$manifest_team\` |
| sha256 matches zip | \`$([[ "$manifest_sha" == "$zip_sha" ]] && printf 'yes' || printf 'no')\` |
| signature algorithm | \`$manifest_algorithm\` |
| signature public key | \`$manifest_public_key\` |
| signature verification | \`$manifest_signature_status\` |
| latest manifest parity | \`$latest_status\` |

## Bundle Identity

| Field | Value |
| --- | --- |
| CFBundleIdentifier | \`$(plist_value CFBundleIdentifier)\` |
| CFBundleShortVersionString | \`$(plist_value CFBundleShortVersionString)\` |
| CFBundleVersion | \`$(plist_value CFBundleVersion)\` |
| Minimum system version | \`$(plist_value LSMinimumSystemVersion)\` |

## Code Signatures

| Item | Identifier | Team ID | Authority |
| --- | --- | --- | --- |
| App bundle | $app_signature |
| Helper | $helper_signature |
| JS worker | $js_worker_signature |
| mihomo core | $core_signature |

## Zip Contents

| Entry | Status |
| --- | --- |
| Mihomo.app/Contents/MacOS/Mihomo | $(zip_entry_status "Mihomo.app/Contents/MacOS/Mihomo") |
| Mihomo.app/Contents/Library/LaunchServices/MihomoHelper | $(zip_entry_status "Mihomo.app/Contents/Library/LaunchServices/MihomoHelper") |
| Mihomo.app/Contents/Resources/MihomoJSWorker | $(zip_entry_status "Mihomo.app/Contents/Resources/MihomoJSWorker") |
| Mihomo.app/Contents/Resources/Core/mihomo | $(zip_entry_status "Mihomo.app/Contents/Resources/Core/mihomo") |
| Mihomo.app/Contents/Resources/THIRD_PARTY_NOTICES.md | $(zip_entry_status "Mihomo.app/Contents/Resources/THIRD_PARTY_NOTICES.md") |

- Zip entry count: ${zip_entry_count:-unknown}

## Release Gate Evidence

- [ ] \`script/ci_release_gate.sh\` passed for this source tree.
- [ ] \`script/release_smoke_test.sh $VERSION\` passed and generated this provenance report.
- [ ] \`script/update_replacement_smoke.sh $VERSION\` passed for this release zip.
- [ ] Protected release machines also ran Developer ID, Team ID, notarization, and stapled ticket checks when required.
REPORT

echo "$OUTPUT_PATH"
