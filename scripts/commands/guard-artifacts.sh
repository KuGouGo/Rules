#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MAX_DELETE_PERCENT="${MAX_DELETE_PERCENT:-30}"
MAX_CHANGE_PERCENT="${MAX_CHANGE_PERCENT:-50}"
SUMMARY_LIMIT="${SUMMARY_LIMIT:-15}"

MAX_IP_ENTRY_CHANGE_PERCENT="${MAX_IP_ENTRY_CHANGE_PERCENT:-40}"
MAX_IP_ENTRY_DELETE_PERCENT="${MAX_IP_ENTRY_DELETE_PERCENT:-25}"
MAX_DOMAIN_RULE_DELETE_PERCENT="${MAX_DOMAIN_RULE_DELETE_PERCENT:-35}"

MIN_IP_CIDR_CN="${MIN_IP_CIDR_CN:-4000}"
MIN_IP_CIDR_CN_V4="${MIN_IP_CIDR_CN_V4:-3000}"
MIN_IP_CIDR_CN_V6="${MIN_IP_CIDR_CN_V6:-300}"
MIN_IP_CIDR_GOOGLE="${MIN_IP_CIDR_GOOGLE:-80}"
MIN_IP_CIDR_GOOGLE_V4="${MIN_IP_CIDR_GOOGLE_V4:-40}"
MIN_IP_CIDR_GOOGLE_V6="${MIN_IP_CIDR_GOOGLE_V6:-20}"
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

count_matching_files() {
  local dir="$1"
  local pattern="$2"
  python3 - <<'PY' "$dir" "$pattern"
import sys
from pathlib import Path

dir_path = Path(sys.argv[1])
pattern = sys.argv[2]
if not dir_path.exists():
    print(0)
else:
    print(sum(1 for path in dir_path.iterdir() if path.is_file() and path.match(pattern)))
PY
}

count_paths_from_text() {
  local text="$1"
  python3 - <<'PY' "$text"
import sys
text = sys.argv[1]
print(sum(1 for line in text.splitlines() if line.strip()))
PY
}

check_min_files() {
  local label="$1"
  local glob="$2"
  local min_expected="$3"
  local dir pattern count

  dir="${glob%/*}"
  pattern="${glob##*/}"
  count=$(count_matching_files "$dir" "$pattern")
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
  local baseline_paths deleted_paths changed_paths baseline_count deleted changed delete_percent change_percent

  baseline_paths=$(git ls-tree -r --name-only HEAD -- "$pathspec")
  baseline_count=$(count_paths_from_text "$baseline_paths")
  if [ "$baseline_count" -eq 0 ]; then
    echo "$label: no baseline files, skip diff-ratio guard"
    return 0
  fi

  deleted_paths=$(git diff --name-only --diff-filter=D HEAD -- "$pathspec")
  changed_paths=$(git diff --name-only HEAD -- "$pathspec")
  deleted=$(count_paths_from_text "$deleted_paths")
  changed=$(count_paths_from_text "$changed_paths")
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

count_domain_rules_from_file() {
  local file="$1"
  case "$file" in
    *.list)
      awk -F, '
        $1 == "DOMAIN" || $1 == "DOMAIN-SUFFIX" || $1 == "DOMAIN-KEYWORD" || $1 == "DOMAIN-REGEX" {
          count++
        }
        END { print count + 0 }
      ' "$file"
      ;;
    *.yaml|*.yml)
      awk '
        /^[[:space:]]*-[[:space:]]/ { count++ }
        END { print count + 0 }
      ' "$file"
      ;;
    *) printf '0' ;;
  esac
}

count_domain_rules_in_dir() {
  local dir="$1"
  local total=0 count file
  [ -d "$dir" ] || { printf '0'; return 0; }
  for file in "$dir"/*; do
    [ -f "$file" ] || continue
    count="$(count_domain_rules_from_file "$file")"
    total=$((total + count))
  done
  printf '%s' "$total"
}

count_domain_rules_from_git_ref_dir() {
  local ref="$1"
  local dir="$2"
  local total=0 count path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      *.list)
        count="$(git show "${ref}:${path}" 2>/dev/null | awk -F, '
          $1 == "DOMAIN" || $1 == "DOMAIN-SUFFIX" || $1 == "DOMAIN-KEYWORD" || $1 == "DOMAIN-REGEX" { count++ }
          END { print count + 0 }
        ')"
        ;;
      *.yaml|*.yml)
        count="$(git show "${ref}:${path}" 2>/dev/null | awk '
          /^[[:space:]]*-[[:space:]]/ { count++ }
          END { print count + 0 }
        ')"
        ;;
      *) count=0 ;;
    esac
    total=$((total + count))
  done < <(git ls-tree -r --name-only "$ref" -- "$dir" 2>/dev/null)
  printf '%s' "$total"
}

check_domain_rule_entry_volatility() {
  local label="$1"
  local dir="$2"
  local baseline current deleted_percent

  baseline="$(count_domain_rules_from_git_ref_dir HEAD "$dir")"
  current="$(count_domain_rules_in_dir "$dir")"
  if [ "$baseline" -eq 0 ]; then
    echo "$label: no baseline domain rules, skip entry guard"
    return 0
  fi

  echo "$label: baseline_rules=$baseline current_rules=$current"
  if [ "$current" -lt "$baseline" ]; then
    deleted_percent=$(( (baseline - current) * 100 / baseline ))
    if [ "$deleted_percent" -gt "$MAX_DOMAIN_RULE_DELETE_PERCENT" ]; then
      echo "$label domain rule drop too high: ${deleted_percent}% > ${MAX_DOMAIN_RULE_DELETE_PERCENT}%" >&2
      exit 1
    fi
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

count_ip_cidrs_by_family_from_file() {
  local file="$1"
  local family="$2"
  awk -F, -v family="$family" '
    family == "v4" && $1 == "IP-CIDR" { count++ }
    family == "v6" && ($1 == "IP-CIDR6" || $1 == "IP6-CIDR") { count++ }
    END { print count + 0 }
  ' "$file"
}

builtin_ip_min_family_entries() {
  local name="$1"
  local family="$2"
  case "$name:$family" in
    cn:v4) printf '%s' "$MIN_IP_CIDR_CN_V4" ;;
    cn:v6) printf '%s' "$MIN_IP_CIDR_CN_V6" ;;
    google:v4) printf '%s' "$MIN_IP_CIDR_GOOGLE_V4" ;;
    google:v6) printf '%s' "$MIN_IP_CIDR_GOOGLE_V6" ;;
    *) printf '' ;;
  esac
}

check_builtin_ip_family_min_entries_in_dir() {
  local dir="$1"
  local label="$2"
  local file base family min_expected count

  for file in "$dir"/*.list; do
    [ -f "$file" ] || continue
    base="$(basename "$file" .list)"
    for family in v4 v6; do
      min_expected="$(builtin_ip_min_family_entries "$base" "$family")"
      [ -n "$min_expected" ] || continue
      count="$(count_ip_cidrs_by_family_from_file "$file" "$family")"
      echo "$label/$base $family entries: $count (min expected: $min_expected)"
      if [ "$count" -lt "$min_expected" ]; then
        echo "$label/$base $family entries too low: $count < $min_expected" >&2
        exit 1
      fi
    done
  done
}

check_builtin_ip_family_min_entries() {
  check_builtin_ip_family_min_entries_in_dir ".output/ip/surge" "ip-surge"
  check_builtin_ip_family_min_entries_in_dir ".output/ip/quanx" "ip-quanx"
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
check_min_files ".output/domain/egern" ".output/domain/egern/*.yaml" 1000
check_min_files ".output/domain/sing-box" ".output/domain/sing-box/*.srs" 1000
check_min_files ".output/domain/mihomo" ".output/domain/mihomo/*.mrs" 1000
# Minimum 9 covers the guaranteed official sources:
# cn, google, telegram, cloudflare, cloudfront, aws, fastly, github, apple.
# Streaming services (netflix, spotify, disney) are best-effort via RIPE NCC
# Stat and are not counted here as they may return empty prefixes.
check_min_files ".output/ip/surge" ".output/ip/surge/*.list" 9
check_min_files ".output/ip/quanx" ".output/ip/quanx/*.list" 9
check_min_files ".output/ip/egern" ".output/ip/egern/*.yaml" 9
check_min_files ".output/ip/sing-box" ".output/ip/sing-box/*.srs" 9
check_min_files ".output/ip/mihomo" ".output/ip/mihomo/*.mrs" 9

print_section "IP CIDR entry checks"
check_builtin_ip_min_entries
check_builtin_ip_family_min_entries
check_builtin_ip_entry_volatility

print_section "Artifact diff-ratio checks"
check_diff_ratio ".output/domain/surge" ".output/domain/surge"
check_diff_ratio ".output/domain/quanx" ".output/domain/quanx"
check_diff_ratio ".output/domain/egern" ".output/domain/egern"
check_diff_ratio ".output/domain/sing-box" ".output/domain/sing-box"
check_diff_ratio ".output/domain/mihomo" ".output/domain/mihomo"
check_diff_ratio ".output/ip/surge" ".output/ip/surge"
check_diff_ratio ".output/ip/quanx" ".output/ip/quanx"
check_diff_ratio ".output/ip/egern" ".output/ip/egern"
check_diff_ratio ".output/ip/sing-box" ".output/ip/sing-box"
check_diff_ratio ".output/ip/mihomo" ".output/ip/mihomo"

print_section "Artifact guard result"
echo "artifact guard passed"
