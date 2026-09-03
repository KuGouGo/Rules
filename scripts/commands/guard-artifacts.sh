#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SUMMARY_LIMIT="${SUMMARY_LIMIT:-15}"
ARTIFACT_ROOT="${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
CAPABILITY_REGISTRY="$(python3 "$ROOT/scripts/tools/platform_capabilities.py" shell-registry)"

# CN floors sit just below the five-source union (APNIC + Clang v4/v6 +
# Loyalsoldier GeoIP + 17mon/iPIP ≈ 8.9k prefixes, ~6.4k v4 / ~2.5k v6) so a
# silently degraded feed cannot shrink the published ruleset unnoticed.
MIN_IP_CIDR_CN="${MIN_IP_CIDR_CN:-7500}"
MIN_IP_CIDR_CN_V4="${MIN_IP_CIDR_CN_V4:-5000}"
MIN_IP_CIDR_CN_V6="${MIN_IP_CIDR_CN_V6:-2000}"
MIN_IP_CIDR_GOOGLE="${MIN_IP_CIDR_GOOGLE:-80}"
MIN_IP_CIDR_GOOGLE_V4="${MIN_IP_CIDR_GOOGLE_V4:-40}"
# Google's published IPv6 prefix count is small and can legitimately sit in
# the mid-teens; keep the guard focused on empty/truncated payloads.
MIN_IP_CIDR_GOOGLE_V6="${MIN_IP_CIDR_GOOGLE_V6:-10}"
MIN_IP_CIDR_TELEGRAM="${MIN_IP_CIDR_TELEGRAM:-8}"
MIN_IP_CIDR_CLOUDFLARE="${MIN_IP_CIDR_CLOUDFLARE:-15}"
MIN_IP_CIDR_CLOUDFRONT="${MIN_IP_CIDR_CLOUDFRONT:-10}"
MIN_IP_CIDR_FASTLY="${MIN_IP_CIDR_FASTLY:-12}"
MIN_IP_CIDR_APPLE="${MIN_IP_CIDR_APPLE:-3}"
MIN_IP_CIDR_PRIVATE="${MIN_IP_CIDR_PRIVATE:-15}"
case "${DOMAIN_PUBLISH_PROFILE:-common}" in
  common)
    # Curated common scope ships ~48 domain lists (44 published + custom
    # sources + fakeip-filter); the floor catches truncated exports, the
    # ceiling unexpected growth.
    DEFAULT_MIN_DOMAIN_ARTIFACT_FILES=40
    DEFAULT_MAX_DOMAIN_ARTIFACT_FILES=90
    ;;
  extended)
    # extended publishes all DLC standalone lists (≈159); the floor catches
    # truncated exports, the ceiling unexpected growth.
    DEFAULT_MIN_DOMAIN_ARTIFACT_FILES=150
    DEFAULT_MAX_DOMAIN_ARTIFACT_FILES=250
    ;;
  *) echo "unsupported domain publish profile: ${DOMAIN_PUBLISH_PROFILE}" >&2; exit 2 ;;
esac
MIN_DOMAIN_ARTIFACT_FILES="${MIN_DOMAIN_ARTIFACT_FILES:-$DEFAULT_MIN_DOMAIN_ARTIFACT_FILES}"
MAX_DOMAIN_ARTIFACT_FILES="${MAX_DOMAIN_ARTIFACT_FILES:-$DEFAULT_MAX_DOMAIN_ARTIFACT_FILES}"

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

  matching_sample="$(find "$dir" -maxdepth 1 -type f -name "$pattern" | sort | awk -v limit="$SUMMARY_LIMIT" 'NR <= limit')"
  if [ -n "$matching_sample" ]; then
    echo "$label matching file sample:"
    printf '%s\n' "$matching_sample"
    return 0
  fi

  file_sample="$(find "$dir" -maxdepth 1 -type f | sort | awk -v limit="$SUMMARY_LIMIT" 'NR <= limit')"
  if [ -n "$file_sample" ]; then
    echo "$label non-matching file sample:"
    printf '%s\n' "$file_sample"
    return 0
  fi

  echo "$label directory has no files: $dir"
}

count_matching_files() {
  find "$1" -maxdepth 1 -type f -name "$2" 2>/dev/null | wc -l | tr -d ' '
}

# Count files for a "<dir>/<pattern>" glob; sets DIR and PATTERN so callers
# can pass them to summarize_artifact_dir on failure.
count_artifact_files() {
  DIR="${1%/*}"
  PATTERN="${1##*/}"
  find "$DIR" -maxdepth 1 -type f -name "$PATTERN" 2>/dev/null | wc -l | tr -d ' '
}

check_min_files() {
  local label="$1"
  local glob="$2"
  local min_expected="$3"
  local count

  count=$(count_artifact_files "$glob")
  echo "$label: $count files (min expected: $min_expected)"

  if [ "$count" -lt "$min_expected" ]; then
    echo "artifact guard failed for $label: expected at least $min_expected files, got $count" >&2
    summarize_artifact_dir "$label" "$DIR" "$PATTERN"
    exit 1
  fi
}

check_max_files() {
  local label="$1"
  local glob="$2"
  local max_expected="$3"
  local count

  count=$(count_artifact_files "$glob")
  echo "$label: $count files (max expected: $max_expected)"

  if [ "$count" -gt "$max_expected" ]; then
    echo "artifact guard failed for $label: expected at most $max_expected files, got $count" >&2
    summarize_artifact_dir "$label" "$DIR" "$PATTERN"
    exit 1
  fi
}

is_redundant_attr_filter_artifact_name() {
  local name="$1"
  local base attr

  case "$name" in
    *@*@*) return 1 ;;
    *@*) ;;
    *) return 1 ;;
  esac

  base="${name%@*}"
  attr="${name##*@}"
  [ -n "$base" ] || return 1
  [ -n "$attr" ] || return 1

  case "$attr" in
    cn)
      [ "$base" = "cn" ] || [ "${base%-cn}" != "$base" ]
      ;;
    '!cn')
      [ "${base%-!cn}" != "$base" ]
      ;;
    *)
      return 1
      ;;
  esac
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
  local platform
  while IFS=$'\t' read -r platform _public _branch section _extension _format _empty _compiler _verifier; do
    [ "$section" = domain ] || continue
    check_no_redundant_attr_filter_artifacts_in_dir "$ARTIFACT_ROOT/domain/$platform" "domain/$platform"
  done <<< "$CAPABILITY_REGISTRY"
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

count_ip_cidrs_by_family_from_file() {
  local file="$1"
  local family="$2"
  awk -F, -v family="$family" '
    family == "v4" && $1 == "IP-CIDR" { count++ }
    family == "v6" && ($1 == "IP-CIDR6" || $1 == "IP6-CIDR") { count++ }
    END { print count + 0 }
  ' "$file"
}

check_public_ip_cidrs_in_dir() {
  local dir="$1"
  local label="$2"

  python3 - <<'PY' "$dir" "$label"
import ipaddress
import sys
from pathlib import Path

dir_path = Path(sys.argv[1])
label = sys.argv[2]
violations: list[str] = []
ip_rule_types = {"IP-CIDR", "IP-CIDR6", "IP6-CIDR"}

if not dir_path.exists():
    raise SystemExit(0)

for path in sorted(dir_path.glob("*.list")):
    allow_non_global = path.stem == "private"
    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        parts = [part.strip() for part in line.split(",")]
        kind = parts[0] if parts else ""
        if kind not in ip_rule_types:
            continue
        if len(parts) < 2 or not parts[1]:
            violations.append(f"{label}/{path.name}:{line_no}: missing CIDR value")
            continue

        try:
            network = ipaddress.ip_network(parts[1], strict=False)
        except ValueError as exc:
            violations.append(f"{label}/{path.name}:{line_no}: invalid CIDR {parts[1]!r} ({exc})")
            continue

        if kind == "IP-CIDR" and network.version != 4:
            violations.append(f"{label}/{path.name}:{line_no}: IP-CIDR requires IPv4, got {network}")
        if kind in {"IP-CIDR6", "IP6-CIDR"} and network.version != 6:
            violations.append(f"{label}/{path.name}:{line_no}: {kind} requires IPv6, got {network}")
        if not allow_non_global and not network.is_global:
            violations.append(f"{label}/{path.name}:{line_no}: non-global CIDR outside private.list: {network}")

if violations:
    print("IP CIDR validity guard failed:", file=sys.stderr)
    for violation in violations:
        print(violation, file=sys.stderr)
    raise SystemExit(1)
PY
}

check_public_ip_cidrs() {
  check_public_ip_cidrs_in_dir "$ARTIFACT_ROOT/ip/surge" "ip-surge"
  check_public_ip_cidrs_in_dir "$ARTIFACT_ROOT/ip/quanx" "ip-quanx"
}

ip_family_min_entries() {
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

check_upstream_ip_family_min_entries_in_dir() {
  local dir="$1"
  local label="$2"
  local file base family min_expected count

  for file in "$dir"/*.list; do
    [ -f "$file" ] || continue
    base="$(basename "$file" .list)"
    for family in v4 v6; do
      min_expected="$(ip_family_min_entries "$base" "$family")"
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

check_upstream_ip_family_min_entries() {
  check_upstream_ip_family_min_entries_in_dir "$ARTIFACT_ROOT/ip/surge" "ip-surge"
  check_upstream_ip_family_min_entries_in_dir "$ARTIFACT_ROOT/ip/quanx" "ip-quanx"
}

upstream_ip_min_entries() {
  local name="$1"
  case "$name" in
    cn) printf '%s' "$MIN_IP_CIDR_CN" ;;
    google) printf '%s' "$MIN_IP_CIDR_GOOGLE" ;;
    telegram) printf '%s' "$MIN_IP_CIDR_TELEGRAM" ;;
    private) printf '%s' "$MIN_IP_CIDR_PRIVATE" ;;
    cloudflare) printf '%s' "$MIN_IP_CIDR_CLOUDFLARE" ;;
    cloudfront) printf '%s' "$MIN_IP_CIDR_CLOUDFRONT" ;;
    fastly) printf '%s' "$MIN_IP_CIDR_FASTLY" ;;
    apple) printf '%s' "$MIN_IP_CIDR_APPLE" ;;
    *) printf '' ;;
  esac
}

check_upstream_ip_min_entries_in_dir() {
  local dir="$1"
  local label="$2"
  local file base min_expected count

  for file in "$dir"/*.list; do
    [ -f "$file" ] || continue
    base="$(basename "$file" .list)"
    min_expected="$(upstream_ip_min_entries "$base")"
    [ -n "$min_expected" ] || continue

    count="$(count_ip_cidrs_from_file "$file")"
    echo "$label/$base entries: $count (min expected: $min_expected)"

    if [ "$count" -lt "$min_expected" ]; then
      echo "$label/$base entries too low: $count < $min_expected" >&2
      exit 1
    fi
  done
}

check_upstream_ip_min_entries() {
  check_upstream_ip_min_entries_in_dir "$ARTIFACT_ROOT/ip/surge" "ip-surge"
  check_upstream_ip_min_entries_in_dir "$ARTIFACT_ROOT/ip/quanx" "ip-quanx"
}

main() {
  print_section "Artifact count checks"
  local platform section extension min_expected
  while IFS=$'\t' read -r platform _public _branch section extension _format _empty _compiler _verifier; do
    if [ "$section" = domain ]; then min_expected="$MIN_DOMAIN_ARTIFACT_FILES"; else min_expected=8; fi
    check_min_files "$ARTIFACT_ROOT/$section/$platform" "$ARTIFACT_ROOT/$section/$platform/*.${extension}" "$min_expected"
    if [ "$section" = domain ]; then
      check_max_files \
        "$ARTIFACT_ROOT/$section/$platform" \
        "$ARTIFACT_ROOT/$section/$platform/*.${extension}" \
        "$MAX_DOMAIN_ARTIFACT_FILES"
    fi
  done <<< "$CAPABILITY_REGISTRY"
  # Minimum 8 covers the guaranteed sources:
  # cn, private, google, telegram, cloudflare, cloudfront, fastly, apple.

  print_section "Domain artifact shape checks"
  check_no_redundant_attr_filter_artifacts

  print_section "IP CIDR entry checks"
  check_public_ip_cidrs
  check_upstream_ip_min_entries
  check_upstream_ip_family_min_entries

  print_section "Artifact guard result"
  echo "artifact guard passed"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
