#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist/release-checks"
OUTPUT_PATH=""
SCENARIO_NAME="protected-release-readiness"
SCENARIO_NOTES=()
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
VERSION="${MIHOMO_RELEASE_VERSION:-}"

usage() {
  cat >&2 <<USAGE
usage: $0 [--version <version>] [--output <path>] [--scenario <name>] [--note <text>]

Writes a read-only Markdown checklist for protected Developer ID release readiness.
It records tool availability, required Mihomo release environment variables,
and the command sequence that should be run on the protected release machine.
--version sets the release version used in command examples.
--scenario names the manual pass, such as developer-id-notarization-dry-run.
--note appends an operator note to the report; repeat it for multiple steps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --scenario)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SCENARIO_NAME="$2"
      shift 2
      ;;
    --note)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SCENARIO_NOTES+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="$OUTPUT_DIR/protected-release-$TIMESTAMP.md"
fi
mkdir -p "$(dirname "$OUTPUT_PATH")"

env_status() {
  local name="$1"
  local value="${!name:-}"
  if [[ -n "$value" ]]; then
    printf 'set'
  else
    printf 'missing'
  fi
}

tool_status() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    printf '`%s`' "$(command -v "$tool")"
  else
    printf 'missing'
  fi
}

xcrun_tool_status() {
  local tool="$1"
  if /usr/bin/xcrun -f "$tool" >/dev/null 2>&1; then
    printf '`%s`' "$(/usr/bin/xcrun -f "$tool")"
  else
    printf 'missing'
  fi
}

identity_status() {
  local identity="${MIHOMO_CODESIGN_IDENTITY:-}"
  if [[ -z "$identity" ]]; then
    printf 'not requested'
    return
  fi
  if ! command -v security >/dev/null 2>&1; then
    printf 'security tool missing'
    return
  fi
  if /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -F "$identity" >/dev/null 2>&1; then
    printf 'found'
  else
    printf 'missing'
  fi
}

append_notes() {
  printf '## Scenario Notes\n\n' >>"$OUTPUT_PATH"
  printf -- '- Scenario: %s\n' "$SCENARIO_NAME" >>"$OUTPUT_PATH"
  if [[ "${#SCENARIO_NOTES[@]}" -eq 0 ]]; then
    printf -- '- Operator notes: none supplied\n\n' >>"$OUTPUT_PATH"
    return
  fi

  local index=1
  local note
  for note in "${SCENARIO_NOTES[@]}"; do
    printf -- '- Note %s: %s\n' "$index" "$note" >>"$OUTPUT_PATH"
    index=$((index + 1))
  done
  printf '\n' >>"$OUTPUT_PATH"
}

cat >"$OUTPUT_PATH" <<HEADER
# Mihomo Protected Release Checklist

- Timestamp UTC: $TIMESTAMP
- Mode: read-only checklist
- Scenario: $SCENARIO_NAME
- Version: ${VERSION:-unspecified}
- Host: $(/bin/hostname)

HEADER

append_notes

cat >>"$OUTPUT_PATH" <<TOOLS
## Tool Readiness

| Tool | Status |
| --- | --- |
| codesign | $(tool_status codesign) |
| security | $(tool_status security) |
| spctl | $(tool_status spctl) |
| xcrun notarytool | $(xcrun_tool_status notarytool) |
| xcrun stapler | $(xcrun_tool_status stapler) |
| jq | $(tool_status jq) |

## Mihomo Release Environment

| Variable | Status |
| --- | --- |
| MIHOMO_CODESIGN_IDENTITY | $(env_status MIHOMO_CODESIGN_IDENTITY) |
| MIHOMO_EXPECTED_TEAM_ID | $(env_status MIHOMO_EXPECTED_TEAM_ID) |
| MIHOMO_REQUIRE_DEVELOPER_ID | ${MIHOMO_REQUIRE_DEVELOPER_ID:-missing} |
| MIHOMO_REQUIRE_NOTARIZATION | ${MIHOMO_REQUIRE_NOTARIZATION:-missing} |
| MIHOMO_REQUIRE_STAPLED_TICKET | ${MIHOMO_REQUIRE_STAPLED_TICKET:-missing} |
| MIHOMO_UPDATE_PRIVATE_KEY | $(env_status MIHOMO_UPDATE_PRIVATE_KEY) |
| Codesign identity lookup | $(identity_status) |

TOOLS

cat >>"$OUTPUT_PATH" <<'CHECKS'
## Protected Release Checks

- [ ] `MIHOMO_CODESIGN_IDENTITY` points to a Developer ID Application certificate in the release keychain.
- [ ] `MIHOMO_EXPECTED_TEAM_ID` matches the Apple Developer Team ID for the certificate.
- [ ] `MIHOMO_REQUIRE_DEVELOPER_ID=1`, `MIHOMO_REQUIRE_NOTARIZATION=1`, and `MIHOMO_REQUIRE_STAPLED_TICKET=1` are enabled for protected release verification.
- [ ] The Ed25519 update manifest private key is present only on the protected release machine.
- [ ] The release zip has been submitted to Apple notarization and accepted.
- [ ] The notarization ticket has been stapled to `dist/Mihomo.app`.
- [ ] `script/release_smoke_test.sh` passes with Developer ID, Team ID, Gatekeeper, and stapled ticket checks enabled.
- [ ] The final zip and `mihomo-update.json` are uploaded together to the GitHub Release.

CHECKS

if [[ -n "$VERSION" ]]; then
  cat >>"$OUTPUT_PATH" <<COMMANDS
## Command Template

\`\`\`bash
export MIHOMO_CODESIGN_IDENTITY="Developer ID Application: ..."
export MIHOMO_EXPECTED_TEAM_ID="TEAMID1234"
export MIHOMO_REQUIRE_DEVELOPER_ID=1
export MIHOMO_REQUIRE_NOTARIZATION=1
export MIHOMO_REQUIRE_STAPLED_TICKET=1
./script/package_release.sh $VERSION
xcrun notarytool submit dist/releases/Mihomo-$VERSION-macOS-arm64.zip --wait
xcrun stapler staple dist/Mihomo.app
./script/release_smoke_test.sh $VERSION
./script/update_replacement_smoke.sh $VERSION
shasum -a 256 dist/releases/Mihomo-$VERSION-macOS-arm64.zip
\`\`\`
COMMANDS
else
  cat >>"$OUTPUT_PATH" <<'COMMANDS'
## Command Template

Run this script with `--version <version>` to include the protected release command template.
COMMANDS
fi

echo "$OUTPUT_PATH"
