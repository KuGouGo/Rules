#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/rules.sh
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

normalize_body="$TMP_DIR/normalize-ip-rule-source.body"
awk '
  /^normalize_ip_rule_source\(\) \{/ { capture = 1 }
  capture { print }
  capture && $0 == "}" { exit }
' "$ROOT/scripts/lib/rules.sh" > "$normalize_body"
if ! grep -Fq 'normalize-ip-rules.py" custom-source' "$normalize_body"; then
  echo "test failed: custom IP normalization must use the strict shared entrypoint" >&2
  cat "$normalize_body" >&2
  exit 1
fi

cat > "$TMP_DIR/mixed.txt" <<'CIDRS'
192.168.1.1/24
192.168.1.0/24
2001:db8::1/32
not-a-cidr
# comment
CIDRS

python3 "$ROOT/scripts/tools/normalize-ip-rules.py" single text "$TMP_DIR/mixed.txt" "$TMP_DIR/mixed.out"
assert_file_content "$TMP_DIR/mixed.out" $'192.168.1.0/24\n2001:db8::/32'

cat > "$TMP_DIR/merge-a.txt" <<'CIDRS'
10.0.0.0/8
192.168.1.0/24
2001:db8::/32
CIDRS
cat > "$TMP_DIR/merge-b.txt" <<'CIDRS'
10.1.0.0/16
192.168.2.0/24
2001:db8:1::/48
CIDRS

python3 "$ROOT/scripts/tools/normalize-ip-rules.py" \
  merge \
  "$TMP_DIR/merged.out" \
  "$TMP_DIR/merge-a.txt" \
  "$TMP_DIR/merge-b.txt"
assert_file_content "$TMP_DIR/merged.out" $'10.0.0.0/8\n192.168.1.0/24\n192.168.2.0/24\n2001:db8::/32'

cat > "$TMP_DIR/adjacent-a.txt" <<'CIDRS'
192.0.2.0/25
2001:db8::/33
CIDRS
cat > "$TMP_DIR/adjacent-b.txt" <<'CIDRS'
192.0.2.128/25
2001:db8:8000::/33
CIDRS

python3 "$ROOT/scripts/tools/normalize-ip-rules.py" \
  merge \
  "$TMP_DIR/adjacent-merged.out" \
  "$TMP_DIR/adjacent-a.txt" \
  "$TMP_DIR/adjacent-b.txt"
assert_file_content "$TMP_DIR/adjacent-merged.out" $'192.0.2.0/24\n2001:db8::/32'

python3 "$ROOT/scripts/tools/normalize-ip-rules.py" \
  merge-dedupe \
  "$TMP_DIR/merged-dedupe.out" \
  "$TMP_DIR/merge-a.txt" \
  "$TMP_DIR/merge-b.txt"
assert_file_content "$TMP_DIR/merged-dedupe.out" $'10.0.0.0/8\n192.168.1.0/24\n2001:db8::/32\n10.1.0.0/16\n192.168.2.0/24\n2001:db8:1::/48'

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

printf 'preserved single output\n' > "$TMP_DIR/atomic-single.out"
printf '{invalid json\n' > "$TMP_DIR/invalid-google.json"
if python3 "$ROOT/scripts/tools/normalize-ip-rules.py" single google-json \
  "$TMP_DIR/invalid-google.json" "$TMP_DIR/atomic-single.out" >/dev/null 2>&1; then
  echo "test failed: invalid single input should fail" >&2
  exit 1
fi
assert_file_content "$TMP_DIR/atomic-single.out" 'preserved single output'

printf 'preserved batch one\n' > "$TMP_DIR/atomic-batch-one.out"
printf 'preserved batch two\n' > "$TMP_DIR/atomic-batch-two.out"
cat > "$TMP_DIR/atomic-batch.json" <<EOF
[
  {"source_type":"text","input_file":"$TMP_DIR/mixed.txt","output_file":"$TMP_DIR/atomic-batch-one.out"},
  {"source_type":"google-json","input_file":"$TMP_DIR/invalid-google.json","output_file":"$TMP_DIR/atomic-batch-two.out"}
]
EOF
if python3 "$ROOT/scripts/tools/normalize-ip-rules.py" batch "$TMP_DIR/atomic-batch.json" >/dev/null 2>&1; then
  echo "test failed: late invalid batch task should fail" >&2
  exit 1
fi
assert_file_content "$TMP_DIR/atomic-batch-one.out" 'preserved batch one'
assert_file_content "$TMP_DIR/atomic-batch-two.out" 'preserved batch two'
if find "$TMP_DIR" -maxdepth 1 -type f -name '.*.tmp' | grep -q .; then
  echo "test failed: atomic normalization left temporary files" >&2
  exit 1
fi

cat > "$TMP_DIR/custom-source.list" <<'CIDRS'
IP-CIDR,192.168.1.0/24
IP-CIDR6,2001:db8::/32
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

printf '%s\n' 'IP-CIDR,192.168.1.1/24' > "$TMP_DIR/noncanonical-custom.list"
if normalize_ip_rule_source \
  "$TMP_DIR/noncanonical-custom.list" \
  "$TMP_DIR/noncanonical-custom.surge" \
  "$TMP_DIR/noncanonical-custom.plain" \
  >"$TMP_DIR/noncanonical-custom.stdout" 2>"$TMP_DIR/noncanonical-custom.stderr"; then
  echo "test failed: custom IP normalizer should reject non-canonical CIDR" >&2
  exit 1
fi
if ! grep -Fq "CIDR must be canonical; use 192.168.1.0/24" "$TMP_DIR/noncanonical-custom.stderr"; then
  echo "test failed: missing strict custom IP normalizer error" >&2
  cat "$TMP_DIR/noncanonical-custom.stderr" >&2
  exit 1
fi

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
