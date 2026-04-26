#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/lib/rules.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_file_content() {
  local file="$1"
  local expected="$2"
  local actual

  actual="$(cat "$file")"
  if [ "$actual" != "$expected" ]; then
    echo "test failed: unexpected content in $file" >&2
    echo "expected:" >&2
    printf '%s\n' "$expected" >&2
    echo "actual:" >&2
    printf '%s\n' "$actual" >&2
    exit 1
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$actual" != "$expected" ]; then
    echo "test failed: $label" >&2
    echo "expected: $expected" >&2
    echo "actual: $actual" >&2
    exit 1
  fi
}

assert_equals "4" "$(singbox_rule_set_source_version_for_release 1.13.11)" "sing-box 1.13 uses source format v4"
assert_equals "5" "$(singbox_rule_set_source_version_for_release 1.14.0)" "sing-box 1.14 uses source format v5"
assert_equals "3" "$(singbox_rule_set_source_version_for_release 1.12.0)" "sing-box 1.12 uses source format v3"

cat > "$TMP_DIR/mixed.txt" <<'CIDRS'
192.168.1.1/24
192.168.1.0/24
2001:db8::1/32
not-a-cidr
# comment
CIDRS

python3 "$ROOT/scripts/tools/normalize-ip-rules.py" single text "$TMP_DIR/mixed.txt" "$TMP_DIR/mixed.out"
assert_file_content "$TMP_DIR/mixed.out" $'192.168.1.0/24\n2001:db8::/32'

cat > "$TMP_DIR/empty.txt" <<'CIDRS'
# comment only
not-a-cidr
CIDRS

python3 "$ROOT/scripts/tools/normalize-ip-rules.py" single text "$TMP_DIR/empty.txt" "$TMP_DIR/empty.out"
if [ -s "$TMP_DIR/empty.out" ]; then
  echo "test failed: empty normalization output should be zero bytes" >&2
  cat "$TMP_DIR/empty.out" >&2
  exit 1
fi

cat > "$TMP_DIR/custom-source.list" <<'CIDRS'
IP-CIDR,192.168.1.1/24
IP-CIDR,192.168.1.0/24
IP-CIDR6,2001:db8::1/32
# comment
CIDRS

normalize_ip_rule_source \
  "$TMP_DIR/custom-source.list" \
  "$TMP_DIR/custom-source.surge" \
  "$TMP_DIR/custom-source.plain"
assert_file_content \
  "$TMP_DIR/custom-source.plain" \
  $'192.168.1.0/24\n2001:db8::/32'
assert_file_content \
  "$TMP_DIR/custom-source.surge" \
  $'IP-CIDR,192.168.1.0/24,no-resolve\nIP-CIDR6,2001:db8::/32,no-resolve'

render_ip_plain_to_egern_yaml "$TMP_DIR/custom-source.plain" "$TMP_DIR/custom-source.egern.yaml"
assert_file_content \
  "$TMP_DIR/custom-source.egern.yaml" \
  $'no_resolve: true\n\nip_cidr_set:\n  - \'192.168.1.0/24\'\n\nip_cidr6_set:\n  - \'2001:db8::/32\''

cat > "$TMP_DIR/surge-source.list" <<'CIDRS'
IP-CIDR,10.1.2.3/8,no-resolve
IP-CIDR,10.0.0.0/8,no-resolve
IP-CIDR6,2001:db8::1/32,no-resolve
CIDRS

normalize_ip_surge_list_to_plain "$TMP_DIR/surge-source.list" "$TMP_DIR/surge-source.plain"
assert_file_content \
  "$TMP_DIR/surge-source.plain" \
  $'10.0.0.0/8\n2001:db8::/32'

cat > "$TMP_DIR/singbox-source.txt" <<'CIDRS'
192.168.1.1/24
192.168.1.0/24
2001:db8::1/32
CIDRS

python3 "$ROOT/scripts/tools/normalize-ip-rules.py" \
  singbox-json \
  "$TMP_DIR/singbox-source.txt" \
  "$TMP_DIR/singbox.json"
assert_file_content \
  "$TMP_DIR/singbox.json" \
  '{"version":4,"rules":[{"ip_cidr":["192.168.1.0/24","2001:db8::/32"]}]}'

echo "ip normalization tests passed"
