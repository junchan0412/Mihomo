#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
CORE_PATH="$VENDOR_DIR/mihomo"
CORE_URL="${MIHOMO_CORE_URL:-}"

if [[ -x "$CORE_PATH" ]]; then
  echo "$CORE_PATH"
  exit 0
fi

if [[ -z "$CORE_URL" ]] && command -v gh >/dev/null 2>&1; then
  CORE_URL="$(gh release view --repo MetaCubeX/mihomo --json assets --jq '.assets[] | select(.name | test("^mihomo-darwin-arm64-v[0-9].*\\.gz$")) | .url' | head -n 1)"
fi

if [[ -z "$CORE_URL" ]]; then
  CORE_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.28/mihomo-darwin-arm64-v1.19.28.gz"
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
/usr/bin/gzip -dc "$TMP_GZ" >"$CORE_PATH"
/bin/chmod +x "$CORE_PATH"

echo "$CORE_PATH"
