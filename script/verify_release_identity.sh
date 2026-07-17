#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/Mihomo.app}"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Mihomo"
HELPER_BINARY="$APP_BUNDLE/Contents/Library/LaunchServices/MihomoHelper"
JS_WORKER_BINARY="$APP_BUNDLE/Contents/Resources/MihomoJSWorker"

EXPECTED_APP_IDENTIFIER="${MIHOMO_EXPECTED_APP_IDENTIFIER:-dev.codex.Mihomo}"
EXPECTED_HELPER_IDENTIFIER="${MIHOMO_EXPECTED_HELPER_IDENTIFIER:-dev.codex.Mihomo.Helper}"
EXPECTED_JS_WORKER_IDENTIFIER="${MIHOMO_EXPECTED_JS_WORKER_IDENTIFIER:-dev.codex.Mihomo.js-worker}"
EXPECTED_TEAM_ID="${MIHOMO_EXPECTED_TEAM_ID:-}"
REQUIRE_DEVELOPER_ID="${MIHOMO_REQUIRE_DEVELOPER_ID:-0}"
REQUIRE_NOTARIZATION="${MIHOMO_REQUIRE_NOTARIZATION:-0}"
REQUIRE_STAPLED_TICKET="${MIHOMO_REQUIRE_STAPLED_TICKET:-0}"
REQUIRE_TEAM_ID="${MIHOMO_REQUIRE_TEAM_ID:-0}"

fail() {
  echo "$1" >&2
  exit 1
}

signature_value() {
  local name="$1"
  local text="$2"
  awk -F= -v key="$name" '$1 == key { print substr($0, length(key) + 2); exit }' <<<"$text"
}

verify_requirement() {
  local title="$1"
  local path="$2"
  local expected_identifier="$3"
  local requirement="${4:-}"

  if [[ -z "$requirement" && -n "$EXPECTED_TEAM_ID" ]]; then
    requirement="anchor apple generic and certificate leaf[subject.OU] = \"$EXPECTED_TEAM_ID\" and identifier \"$expected_identifier\""
  fi
  [[ -n "$requirement" ]] || return 0

  /usr/bin/codesign -v -R="$requirement" "$path" >/dev/null 2>&1 || {
    fail "$title does not satisfy required signing requirement"
  }
}

verify_code_item() {
  local title="$1"
  local path="$2"
  local expected_identifier="$3"
  local deep="$4"
  local requirement="${5:-}"

  [[ -e "$path" ]] || fail "missing signed item: $path"

  if [[ "$deep" == "1" ]]; then
    /usr/bin/codesign --verify --deep --strict "$path" >/dev/null 2>&1 || fail "$title codesign verification failed"
  else
    /usr/bin/codesign --verify --strict "$path" >/dev/null 2>&1 || fail "$title codesign verification failed"
  fi

  local details
  details="$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1 || true)"
  local identifier
  identifier="$(signature_value "Identifier" "$details")"
  [[ "$identifier" == "$expected_identifier" ]] || {
    fail "$title identifier mismatch: expected $expected_identifier, got ${identifier:-missing}"
  }

  if [[ -n "$EXPECTED_TEAM_ID" ]]; then
    local team
    team="$(signature_value "TeamIdentifier" "$details")"
    [[ "$team" == "$EXPECTED_TEAM_ID" ]] || {
      fail "$title TeamIdentifier mismatch: expected $EXPECTED_TEAM_ID, got ${team:-missing}"
    }
  fi

  if [[ "$REQUIRE_TEAM_ID" == "1" ]]; then
    local team
    team="$(signature_value "TeamIdentifier" "$details")"
    [[ -n "$team" && "$team" != "not set" ]] || {
      fail "$title is ad-hoc signed; a stable TeamIdentifier is required"
    }
  fi

  if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    grep -q '^Authority=Developer ID Application:' <<<"$details" || {
      fail "$title is not signed with a Developer ID Application certificate"
    }
  fi

  verify_requirement "$title" "$path" "$expected_identifier" "$requirement"
}

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
[[ "$bundle_id" == "$EXPECTED_APP_IDENTIFIER" ]] || {
  fail "bundle id mismatch: expected $EXPECTED_APP_IDENTIFIER, got ${bundle_id:-missing}"
}

verify_code_item "App bundle" "$APP_BUNDLE" "$EXPECTED_APP_IDENTIFIER" 1 "${MIHOMO_APP_REQUIREMENT:-}"
verify_code_item "App executable" "$APP_BINARY" "$EXPECTED_APP_IDENTIFIER" 0 "${MIHOMO_APP_REQUIREMENT:-}"
verify_code_item "Helper" "$HELPER_BINARY" "$EXPECTED_HELPER_IDENTIFIER" 0 "${MIHOMO_HELPER_REQUIREMENT:-}"
verify_code_item "JS worker" "$JS_WORKER_BINARY" "$EXPECTED_JS_WORKER_IDENTIFIER" 0 "${MIHOMO_JS_WORKER_REQUIREMENT:-}"

if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
  /usr/sbin/spctl -a -vv --type execute "$APP_BUNDLE" >/dev/null 2>&1 || {
    fail "Gatekeeper assessment failed for notarized release"
  }
fi

if [[ "$REQUIRE_STAPLED_TICKET" == "1" ]]; then
  /usr/bin/xcrun stapler validate "$APP_BUNDLE" >/dev/null 2>&1 || {
    fail "stapled notarization ticket validation failed"
  }
fi

echo "release identity verification passed"
