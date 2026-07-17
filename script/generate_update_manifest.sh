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
TEAM_IDENTIFIER="${MIHOMO_EXPECTED_TEAM_ID:-}"
if [[ -z "$TEAM_IDENTIFIER" ]]; then
  SIGNATURE_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$ROOT_DIR/dist/Mihomo.app" 2>&1 || true)"
  TEAM_IDENTIFIER="$(awk -F= '$1 == "TeamIdentifier" { print substr($0, length("TeamIdentifier") + 2); exit }' <<<"$SIGNATURE_DETAILS")"
fi
if [[ ! "$TEAM_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "a 10-character Developer ID TeamIdentifier is required to generate an update manifest" >&2
  exit 1
fi
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
  --arg teamIdentifier "$TEAM_IDENTIFIER" \
  --arg publishedAt "$PUBLISHED_AT" \
  --arg notes "$NOTES" \
  '{version: $version, build: $build, url: $url, sha256: $sha256, minimumSystemVersion: $minimumSystemVersion, bundleIdentifier: $bundleIdentifier, signingIdentifier: $signingIdentifier, helperSigningIdentifier: $helperSigningIdentifier, teamIdentifier: $teamIdentifier, publishedAt: $publishedAt, notes: $notes}' \
  >"$MANIFEST_PATH"

PUBLIC_KEY="$("$ROOT_DIR/script/sign_update_manifest.swift" "$MANIFEST_PATH")"
if [[ "$PUBLIC_KEY" != "$EXPECTED_UPDATE_PUBLIC_KEY" ]]; then
  echo "update signing key mismatch: expected $EXPECTED_UPDATE_PUBLIC_KEY, got $PUBLIC_KEY" >&2
  exit 1
fi

cp "$MANIFEST_PATH" "$LATEST_PATH"
echo "$MANIFEST_PATH"
