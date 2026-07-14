#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist/accessibility"
OUTPUT_PATH=""
SCENARIO_NAME="manual-accessibility-qa"
SCENARIO_NOTES=()
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
APP_BUNDLE="${MIHOMO_APP_BUNDLE:-$ROOT_DIR/dist/Mihomo.app}"

usage() {
  cat >&2 <<USAGE
usage: $0 [--output <path>] [--scenario <name>] [--note <text>]

Writes a read-only Markdown checklist for manual Mihomo accessibility QA.
Use it with VoiceOver and Accessibility Inspector while exercising the built app.
--scenario names the manual pass, such as voiceover-main-tabs or inspector-tables.
--note appends an operator note to the report; repeat it for multiple steps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
  OUTPUT_PATH="$OUTPUT_DIR/accessibility-qa-$TIMESTAMP.md"
fi
mkdir -p "$(dirname "$OUTPUT_PATH")"

bundle_value() {
  local key="$1"
  if [[ -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
    /usr/libexec/PlistBuddy -c "Print :$key" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || printf 'unknown'
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

append_app_context() {
  printf '## App Context\n\n' >>"$OUTPUT_PATH"
  printf '| Field | Value |\n' >>"$OUTPUT_PATH"
  printf '| --- | --- |\n' >>"$OUTPUT_PATH"
  printf '| App bundle | `%s` |\n' "$APP_BUNDLE" >>"$OUTPUT_PATH"
  printf '| Bundle identifier | `%s` |\n' "$(bundle_value CFBundleIdentifier)" >>"$OUTPUT_PATH"
  printf '| Version | `%s` |\n' "$(bundle_value CFBundleShortVersionString)" >>"$OUTPUT_PATH"
  printf '| Build | `%s` |\n' "$(bundle_value CFBundleVersion)" >>"$OUTPUT_PATH"
  printf '| Host | `%s` |\n' "$(/bin/hostname)" >>"$OUTPUT_PATH"
  printf '\n' >>"$OUTPUT_PATH"
}

append_global_checklist() {
  printf '## Global Checks\n\n' >>"$OUTPUT_PATH"
  cat >>"$OUTPUT_PATH" <<'CHECKS'
- [ ] VoiceOver can enter the main window, sidebar, toolbar, settings, and menu bar extra without focus traps.
- [ ] Command-1 through Command-9 announce and display the expected workspace; Command-, opens the separate Settings window.
- [ ] Command-F moves focus to the active toolbar search field and Command-R refreshes only the active workspace.
- [ ] Tab, Shift-Tab, arrow keys, Return, Enter, Space, and Escape behave predictably on controls, tables, dialogs, and inspectors.
- [ ] Command-click and Shift-click multi-selection are announced; Return, Space, and Delete act on the current selection.
- [ ] Accessibility Inspector shows stable labels, roles, values, and help text for interactive controls.
- [ ] Dynamic status, progress, alerts, and error messages are reachable after the action that creates them.
- [ ] No essential operation depends only on color, hover, pointer precision, or visual table position.

CHECKS
}

append_page_checklist() {
  local page="$1"
  local focus="$2"
  printf '## %s\n\n' "$page" >>"$OUTPUT_PATH"
  printf 'Focus: %s\n\n' "$focus" >>"$OUTPUT_PATH"
  cat >>"$OUTPUT_PATH" <<'CHECKS'
- [ ] VoiceOver announces the page title or selected navigation item before the primary content.
- [ ] Primary controls have concise labels and do not expose raw implementation names.
- [ ] Table/list rows expose useful row content, selection state, and available actions.
- [ ] Keyboard navigation reaches every enabled command and can leave the page naturally.
- [ ] Empty, loading, success, warning, and failure states are announced or discoverable.
- [ ] Accessibility Inspector roles match the control type, especially tables, text areas, buttons, menus, and toggles.
- Result:
- Notes:

CHECKS
}

cat >"$OUTPUT_PATH" <<HEADER
# Mihomo Accessibility QA Checklist

- Timestamp UTC: $TIMESTAMP
- Mode: read-only checklist
- Scenario: $SCENARIO_NAME

HEADER

append_notes
append_app_context
append_global_checklist
append_page_checklist "Overview" "Runtime state cards, traffic graph, network takeover health, and quick actions."
append_page_checklist "Activity" "Recent requests, active connections, read-only DNS observations, traffic statistics, compact columns, and batch connection actions."
append_page_checklist "Profiles" "Profile list, quality analyzer pane, editor entry points, import/refresh/delete actions, and statistics."
append_page_checklist "Policies" "Policy group table, proxy candidates, search/sort controls, delay tests, and offline preview."
append_page_checklist "Rules" "Rule table, checkbox state, multi-selection, edit/delete confirmation, hit counts, and inspector."
append_page_checklist "Overrides" "Profile-matched table layout, local/URL import, remote refresh, source and scope columns, multi-selection, Quick Look, separate editor window, delete confirmation, and Undo/Redo."
append_page_checklist "Network" "System proxy, TUN, runtime/system DNS, domain sniffing, protocol ports, exception rules, recovery snapshots, confirmation dialogs, and status values."
append_page_checklist "Resources" "Rule/Proxy Provider rows, Geo resources, update history, rollback controls, and readiness filters."
append_page_checklist "Logs" "Category sidebar, structured table, filters, pause/resume, multi-row copy, clear confirmation, and retention controls."
append_page_checklist "Diagnostics" "Helper audit, network takeover diagnostics, redacted export actions, and warning/error rows."
append_page_checklist "Advanced" "Backups, secret restore indicators, managed artifacts, Age encryption, four Geo datasets, and config preview."
append_page_checklist "Settings" "Separate Settings scene, user-facing remote management without internal Controller terminology, automatic access-key generation, notification purpose text, draft preservation, Apply/restart, and window close/reopen behavior."

cat >>"$OUTPUT_PATH" <<'FOOTER'
## Sign-off

- [ ] VoiceOver pass completed.
- [ ] Accessibility Inspector pass completed.
- [ ] Keyboard-only pass completed.
- [ ] Issues filed or linked below.

Issues:
FOOTER

echo "$OUTPUT_PATH"
