#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SUMMARY_LIMIT="${SUMMARY_LIMIT:-15}"

MAX_IP_ENTRY_CHANGE_PERCENT="${MAX_IP_ENTRY_CHANGE_PERCENT:-40}"
MAX_IP_ENTRY_GROWTH_ABSOLUTE_DELTA="${MAX_IP_ENTRY_GROWTH_ABSOLUTE_DELTA:-50}"
MAX_IP_ENTRY_DELETE_PERCENT="${MAX_IP_ENTRY_DELETE_PERCENT:-25}"
MAX_DOMAIN_RULE_DELETE_PERCENT="${MAX_DOMAIN_RULE_DELETE_PERCENT:-35}"

MIN_IP_CIDR_CN="${MIN_IP_CIDR_CN:-4000}"
MIN_IP_CIDR_CN_V4="${MIN_IP_CIDR_CN_V4:-3000}"
MIN_IP_CIDR_CN_V6="${MIN_IP_CIDR_CN_V6:-300}"
MIN_IP_CIDR_GOOGLE="${MIN_IP_CIDR_GOOGLE:-80}"
MIN_IP_CIDR_GOOGLE_V4="${MIN_IP_CIDR_GOOGLE_V4:-40}"
# Google's published IPv6 prefix count is small and can legitimately sit in
# the mid-teens; keep the guard focused on empty/truncated payloads.
MIN_IP_CIDR_GOOGLE_V6="${MIN_IP_CIDR_GOOGLE_V6:-10}"
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

summarize_artifact_dir() {
  local label="$1"
  local dir="$2"
  local pattern="$3"
  local matching_sample file_sample

  if [ ! -d "$dir" ]; then
    echo "$label directory is missing: $dir"
    return 0
  fi

  matching_sample="$(find "$dir" -maxdepth 1 -type f -name "$pattern" | sort | head -n "$SUMMARY_LIMIT")"
  if [ -n "$matching_sample" ]; then
    echo "$label matching file sample:"
    printf '%s\n' "$matching_sample"
    return 0
  fi

  file_sample="$(find "$dir" -maxdepth 1 -type f | sort | head -n "$SUMMARY_LIMIT")"
  if [ -n "$file_sample" ]; then
    echo "$label non-matching file sample:"
    printf '%s\n' "$file_sample"
    return 0
  fi

  echo "$label directory has no files: $dir"
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
    summarize_artifact_dir "$label" "$dir" "$pattern"
    exit 1
  fi
}

is_redundant_attr_filter_artifact_name() {
  local name="$1"
  local base attr last_segment

  case "$name" in
    *@*@*) return 1 ;;
    *@*) ;;
    *) return 1 ;;
  esac

  base="${name%@*}"
  attr="${name##*@}"
  [ -n "$base" ] || return 1
  [ -n "$attr" ] || return 1

  last_segment="${base##*-}"
  [ "$last_segment" = "$attr" ]
}

check_no_redundant_attr_filter_artifacts_in_dir() {
  local dir="$1"
  local label="$2"
  local file filename stem violations=0

  [ -d "$dir" ] || return 0

  for file in "$dir"/*; do
    [ -f "$file" ] || continue
    filename="$(basename "$file")"
    stem="${filename%.*}"
    if is_redundant_attr_filter_artifact_name "$stem"; then
      echo "$label redundant attr filter artifact should not be published: $filename" >&2
      violations=$((violations + 1))
    fi
  done

  if [ "$violations" -gt 0 ]; then
    exit 1
  fi
  echo "$label: no redundant attr filter artifacts"
}

check_no_redundant_attr_filter_artifacts() {
  check_no_redundant_attr_filter_artifacts_in_dir ".output/domain/surge" "domain/surge"
  check_no_redundant_attr_filter_artifacts_in_dir ".output/domain/quanx" "domain/quanx"
  check_no_redundant_attr_filter_artifacts_in_dir ".output/domain/egern" "domain/egern"
  check_no_redundant_attr_filter_artifacts_in_dir ".output/domain/sing-box" "domain/sing-box"
  check_no_redundant_attr_filter_artifacts_in_dir ".output/domain/mihomo" "domain/mihomo"
}

count_domain_rules_from_file() {
  local file="$1"
  case "$file" in
    *.list)
      awk -F, '
        $1 == "DOMAIN" || $1 == "DOMAIN-SUFFIX" || $1 == "DOMAIN-KEYWORD" || $1 == "DOMAIN-REGEX" ||
        $1 == "HOST" || $1 == "HOST-SUFFIX" || $1 == "HOST-KEYWORD" || $1 == "HOST-REGEX" {
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

count_git_grep_matches() {
  local pattern="$1"
  local ref="$2"
  shift 2

  { git grep -h -E "$pattern" "$ref" -- "$@" 2>/dev/null || true; } | wc -l | tr -d ' '
}

count_domain_rules_from_git_ref_dir() {
  local ref="$1"
  local dir="${2%/}"
  local list_count yaml_count

  list_count="$(
    count_git_grep_matches \
      '^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|DOMAIN-REGEX|HOST|HOST-SUFFIX|HOST-KEYWORD|HOST-REGEX),' \
      "$ref" \
      "$dir/*.list"
  )"
  yaml_count="$(
    count_git_grep_matches \
      '^[[:space:]]*-[[:space:]]' \
      "$ref" \
      "$dir/*.yaml" \
      "$dir/*.yml"
  )"

  printf '%s' "$((list_count + yaml_count))"
}

check_domain_rule_entry_volatility() {
  local label="$1"
  local dir="$2"
  local baseline_ref="${3:-HEAD}"
  local baseline_dir="${4:-$dir}"
  local baseline current deleted_percent

  baseline="$(count_domain_rules_from_git_ref_dir "$baseline_ref" "$baseline_dir")"
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

ensure_origin_branch_baseline() {
  local branch="$1"

  if git rev-parse --verify "origin/$branch^{commit}" >/dev/null 2>&1; then
    return 0
  fi

  if git fetch --depth=1 origin "+${branch}:refs/remotes/origin/${branch}" >/dev/null 2>&1; then
    return 0
  fi

  echo "origin/$branch baseline unavailable, skip related volatility checks"
  return 1
}

check_domain_rule_entry_volatility_against_branch() {
  local branch="$1"
  local dir="$2"
  local label="$3"

  ensure_origin_branch_baseline "$branch" || return 0
  check_domain_rule_entry_volatility "$label" "$dir" "origin/$branch" "domain"
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

ip_entry_growth_exceeds_limit() {
  local delta="$1"
  local change_percent="$2"

  [ "$delta" -gt "$MAX_IP_ENTRY_GROWTH_ABSOLUTE_DELTA" ] && [ "$change_percent" -gt "$MAX_IP_ENTRY_CHANGE_PERCENT" ]
}

check_builtin_ip_entry_volatility() {
  local base path current baseline delta abs_delta change_percent delete_percent

  ensure_origin_branch_baseline surge || return 0

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

    if [ "$delta" -gt 0 ] && ip_entry_growth_exceeds_limit "$delta" "$change_percent"; then
      echo "ip/$base entry growth too high: +${delta} (${change_percent}% > ${MAX_IP_ENTRY_CHANGE_PERCENT}%, absolute limit ${MAX_IP_ENTRY_GROWTH_ABSOLUTE_DELTA})" >&2
      exit 1
    fi

    if [ "$delete_percent" -gt "$MAX_IP_ENTRY_DELETE_PERCENT" ]; then
      echo "ip/$base entry delete ratio too high: ${delete_percent}% > ${MAX_IP_ENTRY_DELETE_PERCENT}%" >&2
      exit 1
    fi
  done
}

main() {
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

  print_section "Domain artifact shape checks"
  check_no_redundant_attr_filter_artifacts

  print_section "Domain rule entry checks"
  check_domain_rule_entry_volatility_against_branch surge ".output/domain/surge" "domain/surge"
  check_domain_rule_entry_volatility_against_branch quanx ".output/domain/quanx" "domain/quanx"
  check_domain_rule_entry_volatility_against_branch egern ".output/domain/egern" "domain/egern"

  print_section "IP CIDR entry checks"
  check_builtin_ip_min_entries
  check_builtin_ip_family_min_entries
  check_builtin_ip_entry_volatility

  print_section "Artifact guard result"
  echo "artifact guard passed"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
