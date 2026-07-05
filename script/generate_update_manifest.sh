#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <version> <zip-path> [download-url]" >&2
  exit 2
fi

VERSION="$1"
ZIP_PATH="$2"
DOWNLOAD_URL="${3:-$(basename "$ZIP_PATH")}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="dev.codex.Mihomo"
MIN_SYSTEM_VERSION="14.0"
EXPECTED_UPDATE_PUBLIC_KEY="V4ac9RiJwSRBGJG/mD7xM2D40VB5feBCin6gCm8Cu3E="
MANIFEST_PATH="$(dirname "$ZIP_PATH")/Mihomo-$VERSION-update.json"
LATEST_PATH="$(dirname "$ZIP_PATH")/mihomo-update.json"
BUILD="${APP_BUILD:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)}"
SHA256="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat >"$MANIFEST_PATH" <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD",
  "url": "$DOWNLOAD_URL",
  "sha256": "$SHA256",
  "minimumSystemVersion": "$MIN_SYSTEM_VERSION",
  "bundleIdentifier": "$BUNDLE_ID",
  "signingIdentifier": "$BUNDLE_ID",
  "publishedAt": "$PUBLISHED_AT",
  "notes": "Mihomo $VERSION"
}
JSON

PUBLIC_KEY="$("$ROOT_DIR/script/sign_update_manifest.swift" "$MANIFEST_PATH")"
if [[ "$PUBLIC_KEY" != "$EXPECTED_UPDATE_PUBLIC_KEY" ]]; then
  echo "update signing key mismatch: expected $EXPECTED_UPDATE_PUBLIC_KEY, got $PUBLIC_KEY" >&2
  exit 1
fi

cp "$MANIFEST_PATH" "$LATEST_PATH"
echo "$MANIFEST_PATH"
