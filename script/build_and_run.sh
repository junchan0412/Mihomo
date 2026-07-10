#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Mihomo"
HELPER_NAME="MihomoHelper"
JS_WORKER_NAME="MihomoJSWorker"
BUNDLE_ID="dev.codex.Mihomo"
HELPER_LABEL="dev.codex.Mihomo.Helper"
MIN_SYSTEM_VERSION="14.0"
DEFAULT_DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer"

if [[ -z "${DEVELOPER_DIR:-}" && -d "$DEFAULT_DEVELOPER_DIR" ]]; then
  export DEVELOPER_DIR="$DEFAULT_DEVELOPER_DIR"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="${APP_VERSION:-0.7.0-dev}"
APP_BUILD="${APP_BUILD:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)}"
CODESIGN_IDENTITY="${MIHOMO_CODESIGN_IDENTITY:--}"
CODESIGN_OPTIONS="${MIHOMO_CODESIGN_OPTIONS:-}"
if [[ "$CODESIGN_IDENTITY" != "-" && -z "$CODESIGN_OPTIONS" ]]; then
  CODESIGN_OPTIONS="runtime"
fi
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_LIBRARY="$APP_CONTENTS/Library"
APP_LAUNCH_SERVICES="$APP_LIBRARY/LaunchServices"
APP_LAUNCH_DAEMONS="$APP_LIBRARY/LaunchDaemons"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_CORE="$APP_RESOURCES/Core"
APP_BINARY="$APP_MACOS/$APP_NAME"
HELPER_BINARY="$APP_LAUNCH_SERVICES/$HELPER_NAME"
HELPER_PLIST="$APP_LAUNCH_DAEMONS/$HELPER_LABEL.plist"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "$HELPER_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
if [[ "${RELEASE_BUILD:-0}" == "1" ]]; then
  swift build -c release --product "$APP_NAME"
  swift build -c release --product "$HELPER_NAME"
  swift build -c release --product "$JS_WORKER_NAME"
  BUILD_DIR="$(swift build -c release --show-bin-path)"
else
  swift build --product "$APP_NAME"
  swift build --product "$HELPER_NAME"
  swift build --product "$JS_WORKER_NAME"
  BUILD_DIR="$(swift build --show-bin-path)"
fi
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
BUILD_HELPER="$BUILD_DIR/$HELPER_NAME"
BUILD_JS_WORKER="$BUILD_DIR/$JS_WORKER_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_LAUNCH_SERVICES" "$APP_LAUNCH_DAEMONS" "$APP_CORE"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$BUILD_HELPER" "$HELPER_BINARY"
chmod +x "$HELPER_BINARY"
cp "$BUILD_JS_WORKER" "$APP_RESOURCES/$JS_WORKER_NAME"
chmod +x "$APP_RESOURCES/$JS_WORKER_NAME"

if [[ -x "$ROOT_DIR/vendor/mihomo" ]]; then
  cp "$ROOT_DIR/vendor/mihomo" "$APP_CORE/mihomo"
  chmod +x "$APP_CORE/mihomo"
elif [[ -f "$ROOT_DIR/vendor/mihomo.gz" ]]; then
  /usr/bin/gzip -dc "$ROOT_DIR/vendor/mihomo.gz" >"$APP_CORE/mihomo"
  chmod +x "$APP_CORE/mihomo"
fi

if [[ -f "$ROOT_DIR/THIRD_PARTY_NOTICES.md" ]]; then
  cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
fi

cat >"$HELPER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$HELPER_LABEL</string>
  <key>BundleProgram</key>
  <string>Contents/Library/LaunchServices/$HELPER_NAME</string>
  <key>MachServices</key>
  <dict>
    <key>$HELPER_LABEL</key>
    <true/>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
PLIST

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$BUNDLE_ID.deeplink</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>mihomo</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  sign_item() {
    local identifier="$1"
    local path="$2"
    [[ -e "$path" ]] || return 0
    local args=(--force --sign "$CODESIGN_IDENTITY" --identifier "$identifier")
    if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
      args+=(--timestamp=none)
    else
      args+=(--timestamp)
    fi
    if [[ -n "$CODESIGN_OPTIONS" ]]; then
      args+=(--options "$CODESIGN_OPTIONS")
    fi
    /usr/bin/codesign "${args[@]}" "$path" >/dev/null
  }

  if [[ -x "$APP_CORE/mihomo" ]]; then
    sign_item "$BUNDLE_ID.core.mihomo" "$APP_CORE/mihomo"
  fi
  sign_item "$BUNDLE_ID.js-worker" "$APP_RESOURCES/$JS_WORKER_NAME"
  sign_item "$HELPER_LABEL" "$HELPER_BINARY"
  sign_item "$BUNDLE_ID" "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n -F -a "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    if [[ "${SKIP_APP_LAUNCH:-0}" == "1" ]]; then
      /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
    else
      open_app
      sleep 1
      pgrep -x "$APP_NAME" >/dev/null
    fi
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
