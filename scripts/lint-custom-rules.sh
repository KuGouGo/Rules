#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CUSTOM_DOMAIN_DIR="$ROOT/sources/custom/domain"
CUSTOM_IP_DIR="$ROOT/sources/custom/ip"

list_rule_files() {
  local dir="$1"
  python3 - <<'PY' "$dir"
import sys
from pathlib import Path

dir_path = Path(sys.argv[1])
if not dir_path.is_dir():
    raise SystemExit(0)
for path in sorted(dir_path.glob('*.list')):
    if path.is_file():
        print(path)
PY
}

DOMAIN_RULE_FILES="$(list_rule_files "$CUSTOM_DOMAIN_DIR")"
IP_RULE_FILES="$(list_rule_files "$CUSTOM_IP_DIR")"

if [ -z "$DOMAIN_RULE_FILES" ] && [ -z "$IP_RULE_FILES" ]; then
  echo "no custom rule lists, skip"
  exit 0
fi

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_inline_comment() {
  local value="$1"
  printf '%s' "${value%%#*}"
}

check_name() {
  local base="$1"
  if [[ ! "$base" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "invalid custom rule filename: $base.list" >&2
    echo "use lowercase letters, digits, and hyphens only" >&2
    return 1
  fi
}

# Validate a batch of CIDRs in a single Python call.
# Reads tab-separated "type\tcidr\tfile:lineno" from stdin, one entry per line.
# Prints validation errors to stderr; exits non-zero if any entry is invalid.
_validate_ip_cidrs_bulk() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to lint custom IP rules" >&2
    return 1
  fi

  python3 - <<'PY'
import ipaddress
import sys

ok = True
for line in sys.stdin:
    line = line.rstrip('\n')
    if not line:
        continue
    rule_type, cidr, location = line.split('\t', 2)
    try:
        network = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        print(f"{location} invalid CIDR value: {rule_type},{cidr}", file=sys.stderr)
        ok = False
        continue
    if rule_type == "IP-CIDR" and network.version != 4:
        print(f"{location} IP-CIDR requires an IPv4 address: {rule_type},{cidr}", file=sys.stderr)
        ok = False
    elif rule_type == "IP-CIDR6" and network.version != 6:
        print(f"{location} IP-CIDR6 requires an IPv6 address: {rule_type},{cidr}", file=sys.stderr)
        ok = False
sys.exit(0 if ok else 1)
PY
}

check_domain_file() {
  local file="$1"
  local line_no=0
  local seen_non_comment=0
  local has_plain_domain_rule=0
  local has_error=0
  local normalized kind kind_raw value

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"

    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    normalized="$(trim_whitespace "$(strip_inline_comment "$line")")"
    if [ -z "$normalized" ]; then
      continue
    fi

    seen_non_comment=1

    if [[ "$normalized" != *,* ]]; then
      echo "$file:$line_no invalid rule syntax: $line" >&2
      echo "expected DOMAIN,example.com DOMAIN-SUFFIX,example.com DOMAIN-KEYWORD,keyword or DOMAIN-REGEX,pattern" >&2
      has_error=1
      continue
    fi

    kind_raw="$(trim_whitespace "${normalized%%,*}")"
    kind="$(printf '%s' "$kind_raw" | tr '[:lower:]' '[:upper:]')"
    kind="${kind//_/-}"
    value="$(trim_whitespace "${normalized#*,}")"

    if [[ ! "$kind" =~ ^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|DOMAIN-REGEX)$ ]]; then
      echo "$file:$line_no invalid rule type: $line" >&2
      echo "expected DOMAIN DOMAIN-SUFFIX DOMAIN-KEYWORD or DOMAIN-REGEX" >&2
      has_error=1
      continue
    fi

    if [ -z "$value" ]; then
      echo "$file:$line_no rule value must not be empty: $line" >&2
      has_error=1
      continue
    fi

    if [[ "$kind" =~ ^(DOMAIN|DOMAIN-SUFFIX)$ ]] && [[ "$value" == .* ]]; then
      echo "$file:$line_no domain should not start with dot: $line" >&2
      has_error=1
    fi

    if [[ "$kind" =~ ^(DOMAIN|DOMAIN-SUFFIX)$ ]] && [[ "$value" == *,* ]]; then
      echo "$file:$line_no domain value must not contain commas: $line" >&2
      has_error=1
    fi

    if [[ "$kind" =~ ^(DOMAIN|DOMAIN-SUFFIX)$ ]] && [[ "$value" =~ [[:space:]] ]]; then
      echo "$file:$line_no domain value must not contain whitespace: $line" >&2
      has_error=1
    fi

    if [[ "$kind" =~ ^(DOMAIN|DOMAIN-SUFFIX)$ ]]; then
      has_plain_domain_rule=1
    fi
  done < "$file"

  if [ "$seen_non_comment" -eq 0 ]; then
    echo "$file has no effective rules" >&2
    has_error=1
  fi

  if [ "$has_plain_domain_rule" -eq 0 ]; then
    echo "$file has no DOMAIN/DOMAIN-SUFFIX entries; sing-box artifacts will still be built, but mihomo .mrs will be skipped" >&2
  fi

  return "$has_error"
}

check_ip_file() {
  local file="$1"
  local line_no=0
  local seen_non_comment=0
  local has_error=0
  local type value
  # Collect valid-syntax CIDRs for bulk validation: "type\tvalue\tfile:lineno"
  local -a bulk_validate=()

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"

    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    seen_non_comment=1

    if [[ ! "$line" =~ ^(IP-CIDR|IP-CIDR6),[^[:space:],]+$ ]]; then
      echo "$file:$line_no invalid rule syntax: $line" >&2
      echo "expected IP-CIDR,1.2.3.0/24 or IP-CIDR6,2403:300::/32" >&2
      has_error=1
      continue
    fi

    type="${line%%,*}"
    value="${line#*,}"

    if [[ "$type" = "IP-CIDR" && "$value" == *:* ]]; then
      echo "$file:$line_no IPv4 rule should not contain an IPv6 CIDR: $line" >&2
      has_error=1
    fi

    if [[ "$type" = "IP-CIDR6" && "$value" != *:* ]]; then
      echo "$file:$line_no IPv6 rule should contain an IPv6 CIDR: $line" >&2
      has_error=1
    fi

    bulk_validate+=("${type}	${value}	${file}:${line_no}")
  done < "$file"

  if [ "$seen_non_comment" -eq 0 ]; then
    echo "$file has no effective rules" >&2
    has_error=1
  fi

  # Validate all collected CIDRs in a single Python call instead of one per line.
  if [ "${#bulk_validate[@]}" -gt 0 ]; then
    if ! printf '%s\n' "${bulk_validate[@]}" | _validate_ip_cidrs_bulk; then
      has_error=1
    fi
  fi

  return "$has_error"
}

overall_error=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  base="$(basename "$file" .list)"
  check_name "$base" || overall_error=1
  check_domain_file "$file" || overall_error=1
done <<< "$DOMAIN_RULE_FILES"

while IFS= read -r file; do
  [ -n "$file" ] || continue
  base="$(basename "$file" .list)"
  check_name "$base" || overall_error=1
  check_ip_file "$file" || overall_error=1
done <<< "$IP_RULE_FILES"

if [ "$overall_error" -ne 0 ]; then
  echo "custom rule lint failed" >&2
  exit 1
fi

echo "custom rule lint passed"
