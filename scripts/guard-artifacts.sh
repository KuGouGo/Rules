#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAX_DELETE_PERCENT="${MAX_DELETE_PERCENT:-30}"
MAX_CHANGE_PERCENT="${MAX_CHANGE_PERCENT:-50}"
SUMMARY_LIMIT="${SUMMARY_LIMIT:-15}"

MAX_IP_ENTRY_CHANGE_PERCENT="${MAX_IP_ENTRY_CHANGE_PERCENT:-40}"
MAX_IP_ENTRY_DELETE_PERCENT="${MAX_IP_ENTRY_DELETE_PERCENT:-25}"

MIN_IP_CIDR_CN="${MIN_IP_CIDR_CN:-4000}"
MIN_IP_CIDR_GOOGLE="${MIN_IP_CIDR_GOOGLE:-80}"
MIN_IP_CIDR_TELEGRAM="${MIN_IP_CIDR_TELEGRAM:-8}"
MIN_IP_CIDR_CLOUDFLARE="${MIN_IP_CIDR_CLOUDFLARE:-15}"
MIN_IP_CIDR_CLOUDFRONT="${MIN_IP_CIDR_CLOUDFRONT:-150}"
MIN_IP_CIDR_FASTLY="${MIN_IP_CIDR_FASTLY:-12}"
MIN_IP_CIDR_APPLE="${MIN_IP_CIDR_APPLE:-3}"

print_section() {
  local title="$1"
  echo
  echo "=== $title ==="
}

summarize_diff() {
  local label="$1"
  local pathspec="$2"
  local changed_sample deleted_sample

  changed_sample="$(git diff --name-only HEAD -- "$pathspec" | head -n "$SUMMARY_LIMIT")"
  deleted_sample="$(git diff --name-only --diff-filter=D HEAD -- "$pathspec" | head -n "$SUMMARY_LIMIT")"

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

count_ip_cidrs_from_file() {
  local file="$1"
  awk -F, '
    $1 == "IP-CIDR" || $1 == "IP-CIDR6" || $1 == "IP6-CIDR" {
      count++
    }
    END {
      print count + 0
    }
  ' "$file"
}

count_ip_cidrs_from_git_ref() {
  local ref="$1"
  local path="$2"
  git show "${ref}:${path}" 2>/dev/null | awk -F, '
    $1 == "IP-CIDR" || $1 == "IP-CIDR6" || $1 == "IP6-CIDR" {
      count++
    }
    END {
      print count + 0
    }
  '
}

builtin_ip_min_entries() {
  local name="$1"
  case "$name" in
    cn) printf '%s' "$MIN_IP_CIDR_CN" ;;
    google) printf '%s' "$MIN_IP_CIDR_GOOGLE" ;;
    telegram) printf '%s' "$MIN_IP_CIDR_TELEGRAM" ;;
    cloudflare) printf '%s' "$MIN_IP_CIDR_CLOUDFLARE" ;;
    cloudfront) printf '%s' "$MIN_IP_CIDR_CLOUDFRONT" ;;
    fastly) printf '%s' "$MIN_IP_CIDR_FASTLY" ;;
    apple) printf '%s' "$MIN_IP_CIDR_APPLE" ;;
    *) printf '' ;;
  esac
}

check_builtin_ip_min_entries_in_dir() {
  local dir="$1"
  local label="$2"
  local file base min_expected count

  for file in "$dir"/*.list; do
    [ -f "$file" ] || continue
    base="$(basename "$file" .list)"
    min_expected="$(builtin_ip_min_entries "$base")"
    [ -n "$min_expected" ] || continue

    count="$(count_ip_cidrs_from_file "$file")"
    echo "$label/$base entries: $count (min expected: $min_expected)"

    if [ "$count" -lt "$min_expected" ]; then
      echo "$label/$base entries too low: $count < $min_expected" >&2
      exit 1
    fi
  done
}

check_builtin_ip_min_entries() {
  check_builtin_ip_min_entries_in_dir ".output/ip/surge" "ip-surge"
  check_builtin_ip_min_entries_in_dir ".output/ip/quanx" "ip-quanx"
}

ensure_origin_surge_baseline() {
  if git rev-parse --verify "origin/surge^{commit}" >/dev/null 2>&1; then
    return 0
  fi

  if git fetch --depth=1 origin "+surge:refs/remotes/origin/surge" >/dev/null 2>&1; then
    return 0
  fi

  echo "origin/surge baseline unavailable, skip ip entry volatility checks"
  return 1
}

check_builtin_ip_entry_volatility() {
  local base path current baseline delta abs_delta change_percent delete_percent

  ensure_origin_surge_baseline || return 0

  for base in cn google telegram cloudflare cloudfront fastly apple; do
    path=".output/ip/surge/${base}.list"
    if [ ! -f "$path" ]; then
      echo "ip/$base generated file missing for entry guard" >&2
      exit 1
    fi

    if ! git cat-file -e "origin/surge:ip/${base}.list" 2>/dev/null; then
      echo "ip/$base baseline missing on origin/surge, skip volatility check"
      continue
    fi

    current="$(count_ip_cidrs_from_file "$path")"
    baseline="$(count_ip_cidrs_from_git_ref "origin/surge" "ip/${base}.list")"
    if [ "$baseline" -eq 0 ]; then
      echo "ip/$base baseline entries are 0, skip volatility check"
      continue
    fi

    delta=$(( current - baseline ))
    abs_delta="$delta"
    if [ "$abs_delta" -lt 0 ]; then
      abs_delta=$(( -abs_delta ))
    fi

    change_percent=$(( abs_delta * 100 / baseline ))
    delete_percent=0
    if [ "$delta" -lt 0 ]; then
      delete_percent=$(( (-delta) * 100 / baseline ))
    fi

    echo "ip/$base entries: baseline=$baseline current=$current delta=$delta (${change_percent}%)"

    if [ "$change_percent" -gt "$MAX_IP_ENTRY_CHANGE_PERCENT" ]; then
      echo "ip/$base entry change ratio too high: ${change_percent}% > ${MAX_IP_ENTRY_CHANGE_PERCENT}%" >&2
      exit 1
    fi

    if [ "$delete_percent" -gt "$MAX_IP_ENTRY_DELETE_PERCENT" ]; then
      echo "ip/$base entry delete ratio too high: ${delete_percent}% > ${MAX_IP_ENTRY_DELETE_PERCENT}%" >&2
      exit 1
    fi
  done
}

print_section "Artifact count checks"
check_min_files ".output/domain/surge" ".output/domain/surge/*.list" 1000
check_min_files ".output/domain/quanx" ".output/domain/quanx/*.list" 1000
check_min_files ".output/domain/sing-box" ".output/domain/sing-box/*.srs" 1000
check_min_files ".output/domain/mihomo" ".output/domain/mihomo/*.mrs" 1000
# Minimum 9 covers the guaranteed official sources:
# cn, google, telegram, cloudflare, cloudfront, aws, fastly, github, apple.
# Streaming services (netflix, spotify, disney) are best-effort via RIPE NCC
# Stat and are not counted here as they may return empty prefixes.
check_min_files ".output/ip/surge" ".output/ip/surge/*.list" 9
check_min_files ".output/ip/quanx" ".output/ip/quanx/*.list" 9
check_min_files ".output/ip/sing-box" ".output/ip/sing-box/*.srs" 9
check_min_files ".output/ip/mihomo" ".output/ip/mihomo/*.mrs" 9

print_section "IP CIDR entry checks"
check_builtin_ip_min_entries
check_builtin_ip_entry_volatility

print_section "Artifact diff-ratio checks"
check_diff_ratio ".output/domain/surge" ".output/domain/surge"
check_diff_ratio ".output/domain/quanx" ".output/domain/quanx"
check_diff_ratio ".output/domain/sing-box" ".output/domain/sing-box"
check_diff_ratio ".output/domain/mihomo" ".output/domain/mihomo"
check_diff_ratio ".output/ip/surge" ".output/ip/surge"
check_diff_ratio ".output/ip/quanx" ".output/ip/quanx"
check_diff_ratio ".output/ip/sing-box" ".output/ip/sing-box"
check_diff_ratio ".output/ip/mihomo" ".output/ip/mihomo"

print_section "Artifact guard result"
echo "artifact guard passed"
