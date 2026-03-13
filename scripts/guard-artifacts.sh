#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAX_DELETE_PERCENT="${MAX_DELETE_PERCENT:-30}"
MAX_CHANGE_PERCENT="${MAX_CHANGE_PERCENT:-50}"
SUMMARY_LIMIT="${SUMMARY_LIMIT:-15}"

print_section() {
  local title="$1"
  echo
  echo "=== $title ==="
}

summarize_diff() {
  local label="$1"
  local pathspec="$2"
  local changed_sample deleted_sample

  changed_sample="$(git diff --name-only HEAD -- "$pathspec" | sed -n "1,${SUMMARY_LIMIT}p")"
  deleted_sample="$(git diff --name-only --diff-filter=D HEAD -- "$pathspec" | sed -n "1,${SUMMARY_LIMIT}p")"

  if [ -n "$changed_sample" ]; then
    echo "$label changed sample:"
    printf '%s\n' "$changed_sample"
  fi

  if [ -n "$deleted_sample" ]; then
    echo "$label deleted sample:"
    printf '%s\n' "$deleted_sample"
  fi
}

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
    summarize_diff "$label" "$dir"
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
    summarize_diff "$label" "$pathspec"
    exit 1
  fi

  if [ "$change_percent" -gt "$MAX_CHANGE_PERCENT" ]; then
    echo "$label change ratio too high: ${change_percent}% > ${MAX_CHANGE_PERCENT}%" >&2
    summarize_diff "$label" "$pathspec"
    exit 1
  fi
}

print_section "Artifact count checks"
check_min_files "domain/surge" "domain/surge/*.txt" 1000
check_min_files "domain/sing-box" "domain/sing-box/*.srs" 1000
check_min_files "domain/mihomo" "domain/mihomo/*.mrs" 1000
check_min_files "ip/surge" "ip/surge/*.txt" 8
check_min_files "ip/sing-box" "ip/sing-box/*.srs" 8
check_min_files "ip/mihomo" "ip/mihomo/*.mrs" 8

print_section "Artifact diff-ratio checks"
check_diff_ratio "domain/surge" "domain/surge"
check_diff_ratio "domain/sing-box" "domain/sing-box"
check_diff_ratio "domain/mihomo" "domain/mihomo"
check_diff_ratio "ip/surge" "ip/surge"
check_diff_ratio "ip/sing-box" "ip/sing-box"
check_diff_ratio "ip/mihomo" "ip/mihomo"

print_section "Artifact guard result"
echo "artifact guard passed"
