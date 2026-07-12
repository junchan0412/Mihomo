#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist/smoke"
ASSERT_CLEAN=0
OUTPUT_PATH=""
SUMMARY_PATH=""
BASELINE_PATH=""
SCENARIO_NAME="unspecified"
SCENARIO_PHASE="unspecified"
SCENARIO_NOTES=()
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
APP_SUPPORT_DIR="${MIHOMO_APP_SUPPORT_DIR:-$HOME/Library/Application Support/Mihomo}"

usage() {
  cat >&2 <<USAGE
usage: $0 [--assert-clean] [--output <path>] [--summary <path>] [--baseline <path>] [--scenario <name>] [--phase <name>] [--note <text>]

Collects a read-only real-system network takeover smoke report.
--assert-clean fails when common proxy settings or Mihomo recovery snapshots
are still present after a test that should have restored the system.
--summary writes a machine-readable TSV summary for before/after comparisons.
--baseline compares the generated summary against a previous summary.
--scenario names the manual scenario being captured, such as proxy-toggle or tun-crash-restore.
--phase labels the scenario phase, such as before, enabled, after-stop, after-quit, after-crash, or recovered.
--note appends an operator note to the Markdown report; repeat it for multiple steps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assert-clean)
      ASSERT_CLEAN=1
      shift
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --summary)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SUMMARY_PATH="$2"
      shift 2
      ;;
    --baseline)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      BASELINE_PATH="$2"
      shift 2
      ;;
    --scenario)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SCENARIO_NAME="$2"
      shift 2
      ;;
    --phase)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SCENARIO_PHASE="$2"
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
  OUTPUT_PATH="$OUTPUT_DIR/network-takeover-$TIMESTAMP.md"
fi
if [[ -z "$SUMMARY_PATH" ]]; then
  SUMMARY_PATH="${OUTPUT_PATH%.md}.summary.tsv"
fi
mkdir -p "$(dirname "$SUMMARY_PATH")"
: >"$SUMMARY_PATH"

failures=()
warnings=()

append_summary() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$SUMMARY_PATH"
}

run_capture() {
  local title="$1"
  shift
  {
    printf '### %s\n\n' "$title"
    printf '```text\n'
    if "$@" 2>&1; then
      :
    else
      local status=$?
      printf '\n(command exited with status %s)\n' "$status"
      warnings+=("$title command exited with status $status")
    fi
    printf '```\n\n'
  } >>"$OUTPUT_PATH"
}

list_services() {
  /usr/sbin/networksetup -listallnetworkservices 2>/dev/null \
    | sed '1d' \
    | sed 's/^\*//'
}

read_services() {
  NETWORK_SERVICES=()
  local service
  while IFS= read -r service; do
    [[ -n "$service" ]] || continue
    NETWORK_SERVICES+=("$service")
  done < <(list_services | awk 'NF { print }')
}

proxy_enabled_value() {
  local text="$1"
  awk -F': ' '$1 == "Enabled" { print $2; exit }' <<<"$text"
}

dns_has_servers() {
  local service="$1"
  local text
  text="$(/usr/sbin/networksetup -getdnsservers "$service" 2>&1 || true)"
  [[ "$text" != *"There aren't any DNS Servers set"* && -n "$(awk 'NF { print; exit }' <<<"$text")" ]]
}

append_proxy_summary() {
  local service web secure socks dns_status
  printf '### Network Service Proxy/DNS Summary\n\n' >>"$OUTPUT_PATH"
  printf '| Service | HTTP | HTTPS | SOCKS | DNS override |\n' >>"$OUTPUT_PATH"
  printf '| --- | --- | --- | --- | --- |\n' >>"$OUTPUT_PATH"

  for service in "${NETWORK_SERVICES[@]}"; do
    web="$(proxy_enabled_value "$(/usr/sbin/networksetup -getwebproxy "$service" 2>&1 || true)")"
    secure="$(proxy_enabled_value "$(/usr/sbin/networksetup -getsecurewebproxy "$service" 2>&1 || true)")"
    socks="$(proxy_enabled_value "$(/usr/sbin/networksetup -getsocksfirewallproxy "$service" 2>&1 || true)")"
    if dns_has_servers "$service"; then
      dns_status="set"
    else
      dns_status="system"
    fi

    printf '| %s | %s | %s | %s | %s |\n' \
      "$service" "${web:-unknown}" "${secure:-unknown}" "${socks:-unknown}" "$dns_status" >>"$OUTPUT_PATH"
    append_summary "proxy" "$service" "http" "${web:-unknown}"
    append_summary "proxy" "$service" "https" "${secure:-unknown}"
    append_summary "proxy" "$service" "socks" "${socks:-unknown}"
    append_summary "dns" "$service" "override" "$dns_status"

    if [[ "$ASSERT_CLEAN" == "1" ]]; then
      [[ "${web:-No}" != "Yes" ]] || failures+=("HTTP proxy still enabled on $service")
      [[ "${secure:-No}" != "Yes" ]] || failures+=("HTTPS proxy still enabled on $service")
      [[ "${socks:-No}" != "Yes" ]] || failures+=("SOCKS proxy still enabled on $service")
    fi
  done
  printf '\n' >>"$OUTPUT_PATH"
}

append_snapshot_summary() {
  local snapshots=(
    "$APP_SUPPORT_DIR/system-proxy-snapshot.json"
    "$APP_SUPPORT_DIR/system-dns-snapshot.json"
    "$APP_SUPPORT_DIR/tun-recovery-snapshot.json"
  )
  local snapshot status

  printf '### Mihomo Recovery Snapshots\n\n' >>"$OUTPUT_PATH"
  printf '| Snapshot | Status | Size |\n' >>"$OUTPUT_PATH"
  printf '| --- | --- | --- |\n' >>"$OUTPUT_PATH"
  for snapshot in "${snapshots[@]}"; do
    if [[ -f "$snapshot" ]]; then
      if command -v jq >/dev/null 2>&1 && jq empty "$snapshot" >/dev/null 2>&1; then
        status="present-json-ok"
      elif ! command -v jq >/dev/null 2>&1; then
        status="present-json-unchecked"
        warnings+=("jq is unavailable, skipped JSON validation for $snapshot")
      else
        status="present-json-invalid"
        failures+=("invalid snapshot JSON: $snapshot")
      fi
      printf '| %s | %s | %s bytes |\n' "$snapshot" "$status" "$(wc -c <"$snapshot" | tr -d ' ')" >>"$OUTPUT_PATH"
      append_summary "snapshot" "$snapshot" "status" "$status"
      if [[ "$ASSERT_CLEAN" == "1" ]]; then
        failures+=("recovery snapshot still present: $snapshot")
      fi
    else
      printf '| %s | missing | 0 bytes |\n' "$snapshot" >>"$OUTPUT_PATH"
      append_summary "snapshot" "$snapshot" "status" "missing"
    fi
  done
  printf '\n' >>"$OUTPUT_PATH"
}

append_utun_summary() {
  local utun_interfaces
  utun_interfaces="$(ifconfig -l 2>/dev/null | tr ' ' '\n' | awk '/^utun/ { print }' | paste -sd ',' - | sed 's/,/, /g')"
  printf '### utun Interfaces\n\n' >>"$OUTPUT_PATH"
  printf '%s\n\n' "${utun_interfaces:-none}" >>"$OUTPUT_PATH"
  append_summary "interface" "utun" "list" "${utun_interfaces:-none}"
}

append_scenario_notes() {
  printf '### Manual Scenario Notes\n\n' >>"$OUTPUT_PATH"
  printf -- '- Scenario: %s\n' "$SCENARIO_NAME" >>"$OUTPUT_PATH"
  printf -- '- Phase: %s\n' "$SCENARIO_PHASE" >>"$OUTPUT_PATH"
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

compare_baseline() {
  [[ -z "$BASELINE_PATH" ]] && return 0
  if [[ ! -f "$BASELINE_PATH" ]]; then
    failures+=("baseline summary does not exist: $BASELINE_PATH")
    return 0
  fi

  local baseline_sorted current_sorted diff_output
  baseline_sorted="$(mktemp "${TMPDIR:-/tmp}/mihomo-baseline.XXXXXX")"
  current_sorted="$(mktemp "${TMPDIR:-/tmp}/mihomo-current.XXXXXX")"
  sort "$BASELINE_PATH" >"$baseline_sorted"
  sort "$SUMMARY_PATH" >"$current_sorted"
  if diff_output="$(/usr/bin/diff -u "$baseline_sorted" "$current_sorted" 2>&1)"; then
    printf '### Baseline Comparison\n\nNo summary differences from baseline `%s`.\n\n' "$BASELINE_PATH" >>"$OUTPUT_PATH"
  else
    printf '### Baseline Comparison\n\n```diff\n%s\n```\n\n' "$diff_output" >>"$OUTPUT_PATH"
    failures+=("network state summary differs from baseline: $BASELINE_PATH")
  fi
  rm -f "$baseline_sorted" "$current_sorted"
}

read_services
if [[ "${#NETWORK_SERVICES[@]}" -eq 0 ]]; then
  failures+=("no network services discovered by networksetup")
fi

cat >"$OUTPUT_PATH" <<HEADER
# Mihomo Network Takeover Smoke

- Timestamp UTC: $TIMESTAMP
- Host: $(/bin/hostname)
- Mode: $([[ "$ASSERT_CLEAN" == "1" ]] && echo "assert-clean" || echo "read-only")
- Scenario: $SCENARIO_NAME
- Phase: $SCENARIO_PHASE
- App Support: $APP_SUPPORT_DIR
- Summary TSV: $SUMMARY_PATH
$([[ -n "$BASELINE_PATH" ]] && printf -- '- Baseline TSV: %s\n' "$BASELINE_PATH")

HEADER

append_scenario_notes
append_proxy_summary
append_snapshot_summary
append_utun_summary
compare_baseline

run_capture "Network Services" /usr/sbin/networksetup -listallnetworkservices
run_capture "Default IPv4 Route" /sbin/route -n get default
run_capture "Default IPv6 Route" /sbin/route -n get -inet6 default
run_capture "DNS Resolver State" /usr/sbin/scutil --dns
run_capture "Interface List" /sbin/ifconfig -l
run_capture "IPv4 Route Table" /usr/sbin/netstat -rn -f inet
run_capture "IPv6 Route Table" /usr/sbin/netstat -rn -f inet6

if [[ "$ASSERT_CLEAN" == "1" ]]; then
  if /usr/sbin/netstat -rn -f inet 2>/dev/null | awk '$1 ~ /^[0-9.]+\/[0-9]+$/ && $NF ~ /^utun/ { found = 1 } END { exit found ? 0 : 1 }'; then
    failures+=("IPv4 route table still contains CIDR routes through utun interfaces")
  fi
  if /usr/sbin/netstat -rn -f inet6 2>/dev/null | awk '$NF ~ /^utun/ && $1 !~ /^fe80/ { found = 1 } END { exit found ? 0 : 1 }'; then
    failures+=("IPv6 route table still contains non-link-local routes through utun interfaces")
  fi
fi

{
  printf '## Smoke Result\n\n'
  if [[ "${#warnings[@]}" -gt 0 ]]; then
    printf 'Warnings:\n'
    for warning in "${warnings[@]}"; do
      printf -- '- %s\n' "$warning"
    done
    printf '\n'
  fi
  if [[ "${#failures[@]}" -gt 0 ]]; then
    printf 'Failures:\n'
    for failure in "${failures[@]}"; do
      printf -- '- %s\n' "$failure"
    done
    printf '\n'
  else
    printf 'No smoke failures detected.\n\n'
  fi
} >>"$OUTPUT_PATH"

echo "$OUTPUT_PATH"
if [[ "${#failures[@]}" -gt 0 ]]; then
  exit 1
fi
