#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/commands/guard-artifacts.sh
source "$ROOT/scripts/commands/guard-artifacts.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$expected" != "$actual" ]; then
    echo "test failed: $label" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

cat > "$TMP_DIR/domain.list" <<'RULES'
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,example
DOMAIN-REGEX,^(.+\.)?example\.com$
HOST,quanx.example.com,proxy
HOST-SUFFIX,quanx.example,proxy
HOST-KEYWORD,quanx,proxy
IP-CIDR,192.0.2.0/24,no-resolve
RULES

cat > "$TMP_DIR/domain.yaml" <<'RULES'
domain_set:
  - 'api.example.com'
domain_suffix_set:
  - 'example.com'
RULES

assert_equals "7" "$(count_domain_rules_from_file "$TMP_DIR/domain.list")" "domain list counts Surge and QuanX domain entries"
assert_equals "2" "$(count_domain_rules_from_file "$TMP_DIR/domain.yaml")" "domain yaml counts Egern entries"
assert_equals "10" "$MIN_IP_CIDR_GOOGLE_V6" "google IPv6 guard default allows normal mid-teen payloads"

echo "guard artifact tests passed"
