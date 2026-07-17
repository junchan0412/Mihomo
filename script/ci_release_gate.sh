#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Mihomo.app"
ZIP_PATH="$ROOT_DIR/dist/ci/Mihomo-ci.zip"
EXPECTED_BUNDLE_ID="dev.codex.Mihomo"

MIHOMO_ALLOW_ADHOC_RELEASE=1 RELEASE_BUILD=1 SKIP_APP_LAUNCH=1 "$ROOT_DIR/script/build_and_run.sh" --verify

for path in \
  "$APP_BUNDLE/Contents/MacOS/Mihomo" \
  "$APP_BUNDLE/Contents/Library/LaunchServices/MihomoHelper" \
  "$APP_BUNDLE/Contents/Resources/MihomoJSWorker" \
  "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"; do
  [[ -e "$path" ]] || { echo "missing release bundle item: $path" >&2; exit 1; }
done

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
bundle_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist")"
[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || { echo "bundle id mismatch" >&2; exit 1; }
[[ "$bundle_executable" == "Mihomo" ]] || { echo "bundle executable mismatch" >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
"$ROOT_DIR/script/verify_release_identity.sh" "$APP_BUNDLE" >/dev/null

rm -rf "$(dirname "$ZIP_PATH")"
mkdir -p "$(dirname "$ZIP_PATH")"
(
  cd "$ROOT_DIR/dist"
  COPYFILE_DISABLE=1 /usr/bin/zip --symlinks -r -X "$ZIP_PATH" "Mihomo.app" >/dev/null
)

for entry in \
  "Mihomo.app/Contents/MacOS/Mihomo" \
  "Mihomo.app/Contents/Library/LaunchServices/MihomoHelper" \
  "Mihomo.app/Contents/Resources/MihomoJSWorker" \
  "Mihomo.app/Contents/Resources/THIRD_PARTY_NOTICES.md"; do
  /usr/bin/unzip -l "$ZIP_PATH" "$entry" >/dev/null || {
    echo "missing release zip item: $entry" >&2
    exit 1
  }
done

maintainability_report="$("$ROOT_DIR/script/maintainability_audit.sh" --output "$ROOT_DIR/dist/ci/maintainability.md" --summary "$ROOT_DIR/dist/ci/maintainability.summary.tsv")"
echo "maintainability audit report: $maintainability_report"
echo "CI release gate passed"
