#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <version> [--keep-workdir]" >&2
  exit 2
fi

VERSION="$1"
shift
KEEP_WORKDIR=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-workdir)
      KEEP_WORKDIR=1
      shift
      ;;
    *)
      echo "usage: $0 <version> [--keep-workdir]" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Mihomo.app"
RELEASE_DIR="$ROOT_DIR/dist/releases"
ZIP_PATH="$RELEASE_DIR/Mihomo-$VERSION-macOS-arm64.zip"
MANIFEST_PATH="$RELEASE_DIR/Mihomo-$VERSION-update.json"
EXPECTED_BUNDLE_ID="dev.codex.Mihomo"
EXPECTED_SIGNING_ID="dev.codex.Mihomo"
EXPECTED_HELPER_ID="dev.codex.Mihomo.Helper"
EXPECTED_JS_WORKER_ID="dev.codex.Mihomo.js-worker"
EXPECTED_TEAM_ID="${MIHOMO_EXPECTED_TEAM_ID:-}"

for path in "$APP_BUNDLE" "$ZIP_PATH" "$MANIFEST_PATH"; do
  [[ -e "$path" ]] || { echo "missing artifact: $path" >&2; exit 1; }
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for update replacement smoke" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mihomo-update-smoke.XXXXXX")"
if [[ "$KEEP_WORKDIR" != "1" ]]; then
  trap 'rm -rf "$WORK_DIR"' EXIT
else
  echo "keeping smoke workdir: $WORK_DIR" >&2
fi

current="$WORK_DIR/Applications/Mihomo.app"
candidate_root="$WORK_DIR/candidate"
candidate="$candidate_root/Mihomo.app"
bad_candidate="$WORK_DIR/bad-candidate/Mihomo.app"
backup="${current}.previous-update"

fail() {
  echo "$1" >&2
  exit 1
}

plist_value() {
  local key="$1"
  local plist="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

signature_identifier() {
  local path="$1"
  local details
  details="$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1 || true)"
  awk -F= '$1 == "Identifier" { print substr($0, length("Identifier") + 2); exit }' <<<"$details"
}

signature_value() {
  local name="$1"
  local path="$2"
  local details
  details="$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1 || true)"
  awk -F= -v key="$name" '$1 == key { print tolower(substr($0, length(key) + 2)); exit }' <<<"$details"
}

verify_signed_item() {
  local title="$1"
  local path="$2"
  local expected_identifier="$3"
  [[ -e "$path" ]] || fail "missing $title: $path"
  /usr/bin/codesign --verify --strict "$path" >/dev/null 2>&1 || fail "$title codesign verify failed"
  [[ "$(signature_identifier "$path")" == "$expected_identifier" ]] || fail "$title signing identifier mismatch"
  if [[ -n "$EXPECTED_TEAM_ID" ]]; then
    local details
    details="$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1 || true)"
    grep -q "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$details" || fail "$title TeamIdentifier mismatch"
    grep -q '^Authority=Developer ID Application:' <<<"$details" || fail "$title Developer ID authority missing"
  fi
  if [[ "${manifest_mode:-}" == "adhoc" ]]; then
    local details
    details="$(/usr/bin/codesign -dv --verbose=4 "$path" 2>&1 || true)"
    grep -q '^Signature=adhoc$' <<<"$details" || fail "$title is not ad-hoc signed"
    if [[ "$title" == "Helper" ]]; then
      [[ "$(signature_value CDHash "$path")" == "$manifest_helper_cdhash" ]] || fail "Helper CDHash mismatch"
    fi
  fi
}

verify_app_identity() {
  local app="$1"
  local expected_version="$2"
  local expected_build="$3"
  local info="$app/Contents/Info.plist"
  local bundle_id version build details

  [[ -d "$app" ]] || fail "missing app bundle: $app"
  bundle_id="$(plist_value "CFBundleIdentifier" "$info")"
  version="$(plist_value "CFBundleShortVersionString" "$info")"
  build="$(plist_value "CFBundleVersion" "$info")"
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || fail "bundle id mismatch for $app"
  [[ "$version" == "$expected_version" ]] || fail "version mismatch for $app: expected $expected_version, got ${version:-missing}"
  [[ -z "$expected_build" || "$build" == "$expected_build" ]] || fail "build mismatch for $app: expected $expected_build, got ${build:-missing}"
  /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 || fail "codesign verify failed for $app"
  details="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 || true)"
  grep -q "Identifier=$EXPECTED_SIGNING_ID" <<<"$details" || fail "signing identifier mismatch for $app"
  if [[ -n "$EXPECTED_TEAM_ID" ]]; then
    grep -q "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$details" || fail "TeamIdentifier mismatch for $app"
    grep -q '^Authority=Developer ID Application:' <<<"$details" || fail "Developer ID authority missing for $app"
  fi
  if [[ "${manifest_mode:-}" == "adhoc" ]]; then
    grep -q '^Signature=adhoc$' <<<"$details" || fail "App is not ad-hoc signed"
    [[ "$(signature_value CDHash "$app")" == "$manifest_app_cdhash" ]] || fail "App CDHash mismatch"
  fi
  verify_signed_item "Helper" "$app/Contents/Library/LaunchServices/MihomoHelper" "$EXPECTED_HELPER_ID"
  verify_signed_item "JS worker" "$app/Contents/Resources/MihomoJSWorker" "$EXPECTED_JS_WORKER_ID"
}

restore_backup() {
  /bin/rm -rf "$current"
  if [[ -e "$backup" ]]; then
    /bin/mv "$backup" "$current"
  fi
}

replace_with_candidate() {
  local source="$1"
  /bin/rm -rf "$backup"
  if [[ -e "$current" ]]; then
    /bin/mv "$current" "$backup"
  fi

  if ! /usr/bin/ditto "$source" "$current"; then
    restore_backup
    return 1
  fi
  /usr/bin/xattr -dr com.apple.quarantine "$current" >/dev/null 2>&1 || true

  if ! /usr/bin/codesign --verify --deep --strict "$current" >/dev/null 2>&1; then
    restore_backup
    return 1
  fi

  /bin/rm -rf "$backup"
  return 0
}

manifest_version="$(jq -r '.version' "$MANIFEST_PATH")"
manifest_build="$(jq -r '.build // ""' "$MANIFEST_PATH")"
manifest_sha="$(jq -r '.sha256' "$MANIFEST_PATH")"
manifest_bundle="$(jq -r '.bundleIdentifier' "$MANIFEST_PATH")"
manifest_signing="$(jq -r '.signingIdentifier' "$MANIFEST_PATH")"
manifest_helper_signing="$(jq -r '.helperSigningIdentifier' "$MANIFEST_PATH")"
manifest_mode="$(jq -r '.signingMode // ""' "$MANIFEST_PATH")"
manifest_team="$(jq -r '.teamIdentifier // ""' "$MANIFEST_PATH")"
manifest_app_cdhash="$(jq -r '.appCDHash // ""' "$MANIFEST_PATH")"
manifest_helper_cdhash="$(jq -r '.helperCDHash // ""' "$MANIFEST_PATH")"
zip_sha="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

[[ "$manifest_version" == "$VERSION" ]] || fail "manifest version mismatch"
[[ "$manifest_sha" == "$zip_sha" ]] || fail "manifest sha256 mismatch"
[[ "$manifest_bundle" == "$EXPECTED_BUNDLE_ID" ]] || fail "manifest bundle id mismatch"
[[ "$manifest_signing" == "$EXPECTED_SIGNING_ID" ]] || fail "manifest signing id mismatch"
[[ "$manifest_helper_signing" == "$EXPECTED_HELPER_ID" ]] || fail "manifest helper signing id mismatch"
case "$manifest_mode" in
  developer-id)
    [[ "$manifest_team" =~ ^[A-Z0-9]{10}$ ]] || fail "manifest TeamIdentifier missing"
    if [[ -n "$EXPECTED_TEAM_ID" ]]; then
      [[ "$manifest_team" == "$EXPECTED_TEAM_ID" ]] || fail "manifest TeamIdentifier mismatch"
    fi
    ;;
  adhoc)
    [[ "$manifest_app_cdhash" =~ ^[a-f0-9]{40}$|^[a-f0-9]{64}$ ]] || fail "manifest App CDHash invalid"
    [[ "$manifest_helper_cdhash" =~ ^[a-f0-9]{40}$|^[a-f0-9]{64}$ ]] || fail "manifest Helper CDHash invalid"
    ;;
  *) fail "unsupported manifest signingMode" ;;
esac

mkdir -p "$(dirname "$current")" "$candidate_root"
/usr/bin/ditto "$APP_BUNDLE" "$current"
verify_app_identity "$current" "$VERSION" "$manifest_build"

/usr/bin/unzip -q "$ZIP_PATH" -d "$candidate_root"
verify_app_identity "$candidate" "$VERSION" "$manifest_build"

replace_with_candidate "$candidate" || fail "valid candidate replacement failed"
verify_app_identity "$current" "$VERSION" "$manifest_build"
[[ ! -e "$backup" ]] || fail "backup was not removed after successful replacement"

mkdir -p "$bad_candidate/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' >"$bad_candidate/Contents/MacOS/Mihomo"
chmod +x "$bad_candidate/Contents/MacOS/Mihomo"

if replace_with_candidate "$bad_candidate"; then
  fail "invalid candidate unexpectedly replaced current app"
fi

verify_app_identity "$current" "$VERSION" "$manifest_build"
[[ ! -e "$backup" ]] || fail "backup was not removed after failed replacement rollback"

echo "update replacement smoke passed for $VERSION"
