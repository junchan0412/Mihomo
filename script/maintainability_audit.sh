#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist/maintainability"
OUTPUT_PATH=""
SUMMARY_PATH=""
WARN_LINES=350
MAX_LINES=500
FAIL_ON_MAX=0
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SCAN_PATHS=("Sources" "Tests")

usage() {
  cat >&2 <<USAGE
usage: $0 [--output <path>] [--summary <path>] [--warn-lines <count>] [--max-lines <count>] [--fail-on-max]

Writes a maintainability report for Swift file size thresholds.
Default mode is non-blocking and suitable for CI warnings; --fail-on-max exits
with failure when any Swift source file exceeds --max-lines.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --warn-lines)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      WARN_LINES="$2"
      shift 2
      ;;
    --max-lines)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      MAX_LINES="$2"
      shift 2
      ;;
    --fail-on-max)
      FAIL_ON_MAX=1
      shift
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

[[ "$WARN_LINES" =~ ^[0-9]+$ ]] || { echo "--warn-lines must be numeric" >&2; exit 2; }
[[ "$MAX_LINES" =~ ^[0-9]+$ ]] || { echo "--max-lines must be numeric" >&2; exit 2; }
[[ "$WARN_LINES" -le "$MAX_LINES" ]] || { echo "--warn-lines must be <= --max-lines" >&2; exit 2; }

mkdir -p "$OUTPUT_DIR"
if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="$OUTPUT_DIR/maintainability-$TIMESTAMP.md"
fi
if [[ -z "$SUMMARY_PATH" ]]; then
  SUMMARY_PATH="${OUTPUT_PATH%.md}.summary.tsv"
fi
mkdir -p "$(dirname "$OUTPUT_PATH")" "$(dirname "$SUMMARY_PATH")"

tmp_all="$(mktemp "${TMPDIR:-/tmp}/mihomo-maintainability-all.XXXXXX")"
tmp_large="$(mktemp "${TMPDIR:-/tmp}/mihomo-maintainability-large.XXXXXX")"
trap 'rm -f "$tmp_all" "$tmp_large"' EXIT

find_args=()
for scan_path in "${SCAN_PATHS[@]}"; do
  if [[ -d "$ROOT_DIR/$scan_path" ]]; then
    find_args+=("$ROOT_DIR/$scan_path")
  fi
done
if [[ "${#find_args[@]}" -eq 0 ]]; then
  echo "no scan paths found" >&2
  exit 1
fi

find "${find_args[@]}" -type f -name '*.swift' -print0 \
  | while IFS= read -r -d '' file; do
      relative="${file#$ROOT_DIR/}"
      lines="$(wc -l <"$file" | tr -d ' ')"
      status="ok"
      if [[ "$lines" -gt "$MAX_LINES" ]]; then
        status="over-max"
      elif [[ "$lines" -gt "$WARN_LINES" ]]; then
        status="warning"
      fi
      printf '%s\t%s\t%s\n' "$lines" "$status" "$relative"
    done \
  | sort -nr >"$tmp_all"

awk -F'\t' -v warn="$WARN_LINES" '$1 > warn { print }' "$tmp_all" >"$tmp_large"
cp "$tmp_all" "$SUMMARY_PATH"

total_files="$(wc -l <"$tmp_all" | tr -d ' ')"
warning_count="$(awk -F'\t' '$2 == "warning" { count += 1 } END { print count + 0 }' "$tmp_all")"
over_max_count="$(awk -F'\t' '$2 == "over-max" { count += 1 } END { print count + 0 }' "$tmp_all")"
largest_line="$(head -1 "$tmp_all" || true)"

{
  printf '# Mihomo Maintainability Audit\n\n'
  printf -- '- Timestamp UTC: %s\n' "$TIMESTAMP"
  printf -- '- Mode: %s\n' "$([[ "$FAIL_ON_MAX" == "1" ]] && printf 'fail-on-max' || printf 'warning-only')"
  printf -- '- Warn threshold: %s lines\n' "$WARN_LINES"
  printf -- '- Max threshold: %s lines\n' "$MAX_LINES"
  printf -- '- Total Swift files scanned: %s\n' "$total_files"
  printf -- '- Warning files: %s\n' "$warning_count"
  printf -- '- Over max files: %s\n' "$over_max_count"
  if [[ -n "$largest_line" ]]; then
    IFS=$'\t' read -r largest_lines largest_status largest_file <<<"$largest_line"
    printf -- '- Largest file: `%s` (%s lines, %s)\n' "$largest_file" "$largest_lines" "$largest_status"
  fi
  printf -- '- Summary TSV: `%s`\n\n' "$SUMMARY_PATH"

  printf '## Files Above Warning Threshold\n\n'
  if [[ -s "$tmp_large" ]]; then
    printf '| Lines | Status | File |\n'
    printf '| ---: | --- | --- |\n'
    while IFS=$'\t' read -r lines status file; do
      printf '| %s | %s | `%s` |\n' "$lines" "$status" "$file"
    done <"$tmp_large"
  else
    printf 'No Swift files exceed the warning threshold.\n'
  fi
  printf '\n## Guidance\n\n'
  printf -- '- Treat `warning` files as candidates for future split or focused tests when touched.\n'
  printf -- '- Treat `over-max` files as priority refactor targets before adding new responsibilities.\n'
  printf -- '- Keep this report non-blocking in normal CI; use `--fail-on-max` only when the current tree is below the max threshold.\n'
} >"$OUTPUT_PATH"

echo "$OUTPUT_PATH"
if [[ "$FAIL_ON_MAX" == "1" && "$over_max_count" -gt 0 ]]; then
  exit 1
fi
