#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAX_DELETE_PERCENT="${MAX_DELETE_PERCENT:-30}"
MAX_CHANGE_PERCENT="${MAX_CHANGE_PERCENT:-50}"

check_min_files() {
  local label="$1"
  local glob="$2"
  local min_expected="$3"
  local dir pattern count

  dir="${glob%/*}"
  pattern="${glob##*/}"
  count=$(find "$dir" -maxdepth 1 -type f -name "$pattern" | wc -l | tr -d ' ')
  echo "$label: $count files (min expected: $min_expected)"

  if [ "$count" -lt "$min_expected" ]; then
    echo "artifact guard failed for $label: expected at least $min_expected files, got $count" >&2
    exit 1
  fi
}

check_diff_ratio() {
  local label="$1"
  local pathspec="$2"
  local baseline_count deleted changed delete_percent change_percent

  baseline_count=$(git ls-tree -r --name-only HEAD -- "$pathspec" | wc -l | tr -d ' ')
  if [ "$baseline_count" -eq 0 ]; then
    echo "$label: no baseline files, skip diff-ratio guard"
    return 0
  fi

  deleted=$(git diff --name-only --diff-filter=D HEAD -- "$pathspec" | wc -l | tr -d ' ')
  changed=$(git diff --name-only HEAD -- "$pathspec" | wc -l | tr -d ' ')
  delete_percent=$(( deleted * 100 / baseline_count ))
  change_percent=$(( changed * 100 / baseline_count ))

  echo "$label: baseline=$baseline_count deleted=$deleted (${delete_percent}%) changed=$changed (${change_percent}%)"

  if [ "$delete_percent" -gt "$MAX_DELETE_PERCENT" ]; then
    echo "$label delete ratio too high: ${delete_percent}% > ${MAX_DELETE_PERCENT}%" >&2
    exit 1
  fi

  if [ "$change_percent" -gt "$MAX_CHANGE_PERCENT" ]; then
    echo "$label change ratio too high: ${change_percent}% > ${MAX_CHANGE_PERCENT}%" >&2
    exit 1
  fi
}

check_min_files "domain/surge" "domain/surge/*.txt" 1000
check_min_files "domain/sing-box" "domain/sing-box/*.srs" 1000
check_min_files "domain/mihomo" "domain/mihomo/*.mrs" 1000

check_min_files "ip/surge" "ip/surge/*.txt" 8
check_min_files "ip/sing-box" "ip/sing-box/*.srs" 8
check_min_files "ip/mihomo" "ip/mihomo/*.mrs" 8

if compgen -G "sources/domain/custom/*.list" >/dev/null; then
  check_min_files "domain/custom-surge" "domain/custom-surge/*.txt" 1
  check_min_files "domain/custom-sing-box" "domain/custom-sing-box/*.srs" 1
  check_min_files "domain/custom-mihomo" "domain/custom-mihomo/*.mrs" 1
fi

check_diff_ratio "domain/surge" "domain/surge"
check_diff_ratio "domain/sing-box" "domain/sing-box"
check_diff_ratio "domain/mihomo" "domain/mihomo"
check_diff_ratio "ip/surge" "ip/surge"
check_diff_ratio "ip/sing-box" "ip/sing-box"
check_diff_ratio "ip/mihomo" "ip/mihomo"
check_diff_ratio "domain/custom-surge" "domain/custom-surge"
check_diff_ratio "domain/custom-sing-box" "domain/custom-sing-box"
check_diff_ratio "domain/custom-mihomo" "domain/custom-mihomo"

echo "artifact guard passed"
