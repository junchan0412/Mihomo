#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <version> <zip-path> [download-url] [release-notes-file]" >&2
  exit 2
fi

VERSION="$1"
ZIP_PATH="$2"
DOWNLOAD_URL="${3:-$(basename "$ZIP_PATH")}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_NOTES_FILE="${4:-$ROOT_DIR/docs/releases/v$VERSION.md}"
BUNDLE_ID="dev.codex.Mihomo"
MIN_SYSTEM_VERSION="14.0"
EXPECTED_UPDATE_PUBLIC_KEY="V4ac9RiJwSRBGJG/mD7xM2D40VB5feBCin6gCm8Cu3E="
MANIFEST_PATH="$(dirname "$ZIP_PATH")/Mihomo-$VERSION-update.json"
LATEST_PATH="$(dirname "$ZIP_PATH")/mihomo-update.json"
BUILD="${APP_BUILD:-${GITHUB_RUN_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || printf '1')}}"
if [[ ! "$BUILD" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "manifest build must contain one to three numeric components (got: $BUILD)" >&2
  exit 1
fi
APP_BUNDLE="$ROOT_DIR/dist/Mihomo.app"
HELPER_BINARY="$APP_BUNDLE/Contents/Library/LaunchServices/MihomoHelper"
SIGNATURE_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 || true)"
HELPER_SIGNATURE_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$HELPER_BINARY" 2>&1 || true)"
TEAM_IDENTIFIER="${MIHOMO_EXPECTED_TEAM_ID:-$(awk -F= '$1 == "TeamIdentifier" { print substr($0, length("TeamIdentifier") + 2); exit }' <<<"$SIGNATURE_DETAILS")}"
SIGNING_MODE="${MIHOMO_RELEASE_SIGNING_MODE:-}"
if [[ -z "$SIGNING_MODE" ]]; then
  if [[ "$TEAM_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]] && grep -q '^Authority=Developer ID Application:' <<<"$SIGNATURE_DETAILS"; then
    SIGNING_MODE="developer-id"
  else
    SIGNING_MODE="adhoc"
  fi
fi

APP_CDHASH=""
HELPER_CDHASH=""
case "$SIGNING_MODE" in
  developer-id)
    if [[ ! "$TEAM_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]]; then
      echo "a 10-character Developer ID TeamIdentifier is required to generate a developer-id manifest" >&2
      exit 1
    fi
    grep -q '^Authority=Developer ID Application:' <<<"$SIGNATURE_DETAILS" || {
      echo "App is not signed by Developer ID Application" >&2
      exit 1
    }
    grep -q '^Authority=Developer ID Application:' <<<"$HELPER_SIGNATURE_DETAILS" || {
      echo "Helper is not signed by Developer ID Application" >&2
      exit 1
    }
    ;;
  adhoc)
    if [[ "${MIHOMO_ALLOW_UNNOTARIZED_RELEASE:-0}" != "1" ]]; then
      echo "refusing ad-hoc update manifest without MIHOMO_ALLOW_UNNOTARIZED_RELEASE=1" >&2
      exit 1
    fi
    grep -q '^Signature=adhoc$' <<<"$SIGNATURE_DETAILS" || { echo "App is not ad-hoc signed" >&2; exit 1; }
    grep -q '^Signature=adhoc$' <<<"$HELPER_SIGNATURE_DETAILS" || { echo "Helper is not ad-hoc signed" >&2; exit 1; }
    APP_CDHASH="$(awk -F= '$1 == "CDHash" { print tolower(substr($0, length("CDHash") + 2)); exit }' <<<"$SIGNATURE_DETAILS")"
    HELPER_CDHASH="$(awk -F= '$1 == "CDHash" { print tolower(substr($0, length("CDHash") + 2)); exit }' <<<"$HELPER_SIGNATURE_DETAILS")"
    [[ "$APP_CDHASH" =~ ^[a-f0-9]{40}$|^[a-f0-9]{64}$ ]] || { echo "invalid App CDHash" >&2; exit 1; }
    [[ "$HELPER_CDHASH" =~ ^[a-f0-9]{40}$|^[a-f0-9]{64}$ ]] || { echo "invalid Helper CDHash" >&2; exit 1; }
    ;;
  *)
    echo "unsupported MIHOMO_RELEASE_SIGNING_MODE: $SIGNING_MODE" >&2
    exit 1
    ;;
esac
SHA256="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
if [[ -f "$RELEASE_NOTES_FILE" ]]; then
  NOTES="$(awk 'NR == 1 && /^# / { next } { print }' "$RELEASE_NOTES_FILE" | sed '/./,$!d')"
else
  NOTES="Mihomo $VERSION"
fi

jq -n \
  --arg version "$VERSION" \
  --arg build "$BUILD" \
  --arg url "$DOWNLOAD_URL" \
  --arg sha256 "$SHA256" \
  --arg minimumSystemVersion "$MIN_SYSTEM_VERSION" \
  --arg bundleIdentifier "$BUNDLE_ID" \
  --arg signingIdentifier "$BUNDLE_ID" \
  --arg helperSigningIdentifier "dev.codex.Mihomo.Helper" \
  --arg signingMode "$SIGNING_MODE" \
  --arg teamIdentifier "$TEAM_IDENTIFIER" \
  --arg appCDHash "$APP_CDHASH" \
  --arg helperCDHash "$HELPER_CDHASH" \
  --arg publishedAt "$PUBLISHED_AT" \
  --arg notes "$NOTES" \
  '({version: $version, build: $build, url: $url, sha256: $sha256, minimumSystemVersion: $minimumSystemVersion, bundleIdentifier: $bundleIdentifier, signingIdentifier: $signingIdentifier, helperSigningIdentifier: $helperSigningIdentifier, signingMode: $signingMode, publishedAt: $publishedAt, notes: $notes}
    + if $signingMode == "developer-id" then {teamIdentifier: $teamIdentifier}
      else {appCDHash: $appCDHash, helperCDHash: $helperCDHash}
      end)' \
  >"$MANIFEST_PATH"

PUBLIC_KEY="$("$ROOT_DIR/script/sign_update_manifest.swift" "$MANIFEST_PATH")"
if [[ "$PUBLIC_KEY" != "$EXPECTED_UPDATE_PUBLIC_KEY" ]]; then
  echo "update signing key mismatch: expected $EXPECTED_UPDATE_PUBLIC_KEY, got $PUBLIC_KEY" >&2
  exit 1
fi

cp "$MANIFEST_PATH" "$LATEST_PATH"
echo "$MANIFEST_PATH"
