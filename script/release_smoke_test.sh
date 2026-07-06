#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <version>" >&2
  exit 2
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Mihomo.app"
RELEASE_DIR="$ROOT_DIR/dist/releases"
ZIP_PATH="$RELEASE_DIR/Mihomo-$VERSION-macOS-arm64.zip"
MANIFEST_PATH="$RELEASE_DIR/Mihomo-$VERSION-update.json"
LATEST_PATH="$RELEASE_DIR/mihomo-update.json"
EXPECTED_BUNDLE_ID="dev.codex.Mihomo"
EXPECTED_PUBLIC_KEY="V4ac9RiJwSRBGJG/mD7xM2D40VB5feBCin6gCm8Cu3E="

for path in "$APP_BUNDLE" "$ZIP_PATH" "$MANIFEST_PATH" "$LATEST_PATH"; do
  if [[ ! -e "$path" ]]; then
    echo "missing artifact: $path" >&2
    exit 1
  fi
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for release smoke test" >&2
  exit 1
fi

manifest_version="$(jq -r '.version' "$MANIFEST_PATH")"
manifest_sha="$(jq -r '.sha256' "$MANIFEST_PATH")"
manifest_bundle="$(jq -r '.bundleIdentifier' "$MANIFEST_PATH")"
manifest_signing="$(jq -r '.signingIdentifier' "$MANIFEST_PATH")"
manifest_public_key="$(jq -r '.signature.publicKey' "$MANIFEST_PATH")"
manifest_algorithm="$(jq -r '.signature.algorithm' "$MANIFEST_PATH")"
zip_sha="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

[[ "$manifest_version" == "$VERSION" ]] || { echo "manifest version mismatch" >&2; exit 1; }
[[ "$manifest_sha" == "$zip_sha" ]] || { echo "manifest sha256 mismatch" >&2; exit 1; }
[[ "$manifest_bundle" == "$EXPECTED_BUNDLE_ID" ]] || { echo "bundle id mismatch" >&2; exit 1; }
[[ "$manifest_signing" == "$EXPECTED_BUNDLE_ID" ]] || { echo "signing id mismatch" >&2; exit 1; }
[[ "$manifest_public_key" == "$EXPECTED_PUBLIC_KEY" ]] || { echo "update public key mismatch" >&2; exit 1; }
[[ "$manifest_algorithm" == "Ed25519" ]] || { echo "signature algorithm mismatch" >&2; exit 1; }

cmp -s "$MANIFEST_PATH" "$LATEST_PATH" || { echo "latest manifest differs from version manifest" >&2; exit 1; }

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
signature_details="$(/usr/bin/codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 || true)"
echo "$signature_details" | grep -q "Identifier=$EXPECTED_BUNDLE_ID" || {
  echo "codesign identifier mismatch" >&2
  exit 1
}

echo "release smoke test passed for $VERSION"
