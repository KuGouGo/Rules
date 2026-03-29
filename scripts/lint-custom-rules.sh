#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CUSTOM_DOMAIN_DIR="$ROOT/sources/custom/domain"
CUSTOM_IP_DIR="$ROOT/sources/custom/ip"

shopt -s nullglob
domain_lists=("$CUSTOM_DOMAIN_DIR"/*.list)
ip_lists=("$CUSTOM_IP_DIR"/*.list)

if [ ${#domain_lists[@]} -eq 0 ] && [ ${#ip_lists[@]} -eq 0 ]; then
  echo "no custom rule lists, skip"
  exit 0
fi

check_name() {
  local base="$1"
  if [[ ! "$base" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "invalid custom rule filename: $base.list" >&2
    echo "use lowercase letters, digits, and hyphens only" >&2
    return 1
  fi
}

validate_ip_cidr() {
  local type="$1"
  local value="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to lint custom IP rules" >&2
    return 1
  fi

  python3 - "$type" "$value" <<'PY'
import ipaddress
import sys

rule_type, cidr = sys.argv[1], sys.argv[2]

try:
    network = ipaddress.ip_network(cidr, strict=False)
except ValueError:
    sys.exit(1)

if rule_type == "IP-CIDR" and network.version != 4:
    sys.exit(1)

if rule_type == "IP-CIDR6" and network.version != 6:
    sys.exit(1)
PY
  return $?
}

check_domain_file() {
  local file="$1"
  local line_no=0
  local seen_non_comment=0
  local has_error=0

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"

    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    seen_non_comment=1

    if [[ ! "$line" =~ ^(DOMAIN|DOMAIN-SUFFIX),[^[:space:],]+$ ]]; then
      echo "$file:$line_no invalid rule syntax: $line" >&2
      echo "expected DOMAIN,example.com or DOMAIN-SUFFIX,example.com" >&2
      has_error=1
      continue
    fi

    if [[ "$line" =~ ,\. ]]; then
      echo "$file:$line_no domain should not start with dot: $line" >&2
      has_error=1
    fi
  done < "$file"

  if [ "$seen_non_comment" -eq 0 ]; then
    echo "$file has no effective rules" >&2
    has_error=1
  fi

  return "$has_error"
}

check_ip_file() {
  local file="$1"
  local line_no=0
  local seen_non_comment=0
  local has_error=0
  local type value

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

    if ! validate_ip_cidr "$type" "$value"; then
      echo "$file:$line_no invalid CIDR value: $line" >&2
      has_error=1
    fi
  done < "$file"

  if [ "$seen_non_comment" -eq 0 ]; then
    echo "$file has no effective rules" >&2
    has_error=1
  fi

  return "$has_error"
}

for file in "${domain_lists[@]}"; do
  base="$(basename "$file" .list)"
  check_name "$base"
  check_domain_file "$file"
done

for file in "${ip_lists[@]}"; do
  base="$(basename "$file" .list)"
  check_name "$base"
  check_ip_file "$file"
done

echo "custom rule lint passed"
