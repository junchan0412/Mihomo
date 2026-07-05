#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Mihomo"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
RELEASE_DIR="$ROOT_DIR/dist/releases"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-macOS-arm64.zip"

RELEASE_BUILD=1 "$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"
(
  cd "$ROOT_DIR/dist"
  COPYFILE_DISABLE=1 zip --symlinks -r -X "$ZIP_PATH" "$APP_NAME.app" >/dev/null
)

echo "$ZIP_PATH"
