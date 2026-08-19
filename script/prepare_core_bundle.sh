#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
CORE_PATH="$VENDOR_DIR/mihomo"
CORE_VERSION="${MIHOMO_CORE_VERSION:-1.19.29}"
CORE_URL="${MIHOMO_CORE_URL:-https://github.com/MetaCubeX/mihomo/releases/download/v1.19.29/mihomo-darwin-arm64-v1.19.29.gz}"
CORE_ARCHIVE_SHA256="${MIHOMO_CORE_ARCHIVE_SHA256:-4dc25df9e899f14161911302a8ee5fc9e202ed9c976fc405bf82c50ff27466ca}"
CORE_SHA256="${MIHOMO_CORE_SHA256:-ec66e3e883bdc3fca06753784e324e08921e13239f8e945587cb1bfbf4c6b936}"

verify_core() {
  local actual_sha version_output
  actual_sha="$(/usr/bin/shasum -a 256 "$CORE_PATH" | /usr/bin/awk '{print $1}')"
  [[ "$actual_sha" == "$CORE_SHA256" ]] || {
    echo "mihomo core SHA-256 mismatch: expected $CORE_SHA256, got $actual_sha" >&2
    return 1
  }
  version_output="$("$CORE_PATH" -v 2>&1 || true)"
  [[ "$version_output" == *"Mihomo Meta v$CORE_VERSION"* ]] || {
    echo "mihomo core version mismatch: expected v$CORE_VERSION" >&2
    return 1
  }
}

if [[ -x "$CORE_PATH" ]]; then
  verify_core
  echo "$CORE_PATH"
  exit 0
fi

mkdir -p "$VENDOR_DIR"
TMP_GZ="$(mktemp "$VENDOR_DIR/mihomo.XXXXXX.gz")"
trap 'rm -f "$TMP_GZ"' EXIT

curl_args=(--fail --location --retry 3 --connect-timeout 20 --max-time 180 --output "$TMP_GZ" "$CORE_URL")
if ! /usr/bin/curl "${curl_args[@]}"; then
  if /usr/bin/nc -z 127.0.0.1 6152 >/dev/null 2>&1; then
    /usr/bin/curl --proxy http://127.0.0.1:6152 "${curl_args[@]}"
  else
    exit 1
  fi
fi
/usr/bin/shasum -a 256 -c <(printf '%s  %s\n' "$CORE_ARCHIVE_SHA256" "$TMP_GZ") >/dev/null
/usr/bin/gzip -dc "$TMP_GZ" >"$CORE_PATH"
/bin/chmod +x "$CORE_PATH"
verify_core

echo "$CORE_PATH"
