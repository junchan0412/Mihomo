#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Mihomo"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
RELEASE_DIR="$ROOT_DIR/dist/releases"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-macOS-arm64.zip"
NOTARY_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-notary.zip"
APP_BUILD="${APP_BUILD:-${GITHUB_RUN_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD)}}"

if [[ -z "${MIHOMO_CODESIGN_IDENTITY:-}" || "${MIHOMO_CODESIGN_IDENTITY}" == "-" ]]; then
  echo "MIHOMO_CODESIGN_IDENTITY must be a Developer ID Application identity." >&2
  exit 1
fi
if [[ -z "${MIHOMO_EXPECTED_TEAM_ID:-}" ]]; then
  echo "MIHOMO_EXPECTED_TEAM_ID is required." >&2
  exit 1
fi
if [[ ! "$MIHOMO_EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "MIHOMO_EXPECTED_TEAM_ID must be a 10-character Apple Team ID." >&2
  exit 1
fi
if [[ -z "${MIHOMO_NOTARY_PROFILE:-}" ]]; then
  echo "MIHOMO_NOTARY_PROFILE is required because SMAppService LaunchDaemons need notarization." >&2
  exit 1
fi

"$ROOT_DIR/script/prepare_core_bundle.sh" >/dev/null
APP_VERSION="$VERSION" APP_BUILD="$APP_BUILD" RELEASE_BUILD=1 "$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

MIHOMO_REQUIRE_DEVELOPER_ID=1 MIHOMO_REQUIRE_TEAM_ID=1 \
  "$ROOT_DIR/script/verify_release_identity.sh" "$APP_BUNDLE" >/dev/null

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH" "$NOTARY_ZIP"
(
  cd "$ROOT_DIR/dist"
  COPYFILE_DISABLE=1 zip --symlinks -r -X "$NOTARY_ZIP" "$APP_NAME.app" >/dev/null
)

/usr/bin/xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$MIHOMO_NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"

(
  cd "$ROOT_DIR/dist"
  COPYFILE_DISABLE=1 zip --symlinks -r -X "$ZIP_PATH" "$APP_NAME.app" >/dev/null
)

APP_BUILD="$APP_BUILD" "$ROOT_DIR/script/generate_update_manifest.sh" "$VERSION" "$ZIP_PATH" >/dev/null
MIHOMO_REQUIRE_DEVELOPER_ID=1 MIHOMO_REQUIRE_TEAM_ID=1 MIHOMO_REQUIRE_NOTARIZATION=1 MIHOMO_REQUIRE_STAPLED_TICKET=1 \
  "$ROOT_DIR/script/verify_release_identity.sh" "$APP_BUNDLE" >/dev/null
rm -f "$NOTARY_ZIP"
echo "$ZIP_PATH"
