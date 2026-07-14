#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOOL="$ROOT/scripts/tools/lint-custom-rules.py"
EMPTY_CONFLICTS="$TMP_DIR/empty-conflicts.json"
printf '%s\n' '{"version":1,"relations":[]}' > "$EMPTY_CONFLICTS"

assert_lint_passes() {
  local label="$1"
  local domain_dir="$2"
  local ip_dir="$3"

  if ! python3 "$TOOL" --domain-dir "$domain_dir" --ip-dir "$ip_dir" --conflicts "$EMPTY_CONFLICTS" >"$TMP_DIR/${label}.stdout" 2>"$TMP_DIR/${label}.stderr"; then
    echo "test failed: expected lint to pass for $label" >&2
    cat "$TMP_DIR/${label}.stderr" >&2
    exit 1
  fi
}

assert_lint_fails_with() {
  local label="$1"
  local expected="$2"
  local domain_dir="$3"
  local ip_dir="$4"

  if python3 "$TOOL" --domain-dir "$domain_dir" --ip-dir "$ip_dir" --conflicts "$EMPTY_CONFLICTS" >"$TMP_DIR/${label}.stdout" 2>"$TMP_DIR/${label}.stderr"; then
    echo "test failed: expected lint to fail for $label" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$TMP_DIR/${label}.stderr"; then
    echo "test failed: missing lint message for $label: $expected" >&2
    cat "$TMP_DIR/${label}.stderr" >&2
    exit 1
  fi
}

make_case_dirs() {
  local case_dir="$1"
  mkdir -p "$case_dir/domain" "$case_dir/ip"
}

make_case_dirs "$TMP_DIR/pass"
cat > "$TMP_DIR/pass/domain/example.list" <<'EOF'
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.net
DOMAIN-KEYWORD,emby
DOMAIN-REGEX,^(.+\.)?example\.org$
EOF
cat > "$TMP_DIR/pass/ip/private.list" <<'EOF'
IP-CIDR,10.0.0.0/8
IP-CIDR6,fc00::/7
EOF
assert_lint_passes "pass" "$TMP_DIR/pass/domain" "$TMP_DIR/pass/ip"

make_case_dirs "$TMP_DIR/domain-coverage"
cat > "$TMP_DIR/domain-coverage/domain/example.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN,api.example.com
EOF
assert_lint_fails_with \
  "domain-coverage" \
  "DOMAIN,api.example.com is covered by DOMAIN-SUFFIX,example.com" \
  "$TMP_DIR/domain-coverage/domain" \
  "$TMP_DIR/domain-coverage/ip"

make_case_dirs "$TMP_DIR/domain-exact-suffix-coverage"
cat > "$TMP_DIR/domain-exact-suffix-coverage/domain/example.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN,example.com
EOF
assert_lint_fails_with \
  "domain-exact-suffix-coverage" \
  "DOMAIN,example.com is covered by DOMAIN-SUFFIX,example.com" \
  "$TMP_DIR/domain-exact-suffix-coverage/domain" \
  "$TMP_DIR/domain-exact-suffix-coverage/ip"

make_case_dirs "$TMP_DIR/domain-coverage-order"
cat > "$TMP_DIR/domain-coverage-order/domain/example.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN-SUFFIX,api.example.com
DOMAIN,www.api.example.com
EOF
assert_lint_fails_with \
  "domain-coverage-order" \
  "DOMAIN-SUFFIX,api.example.com is covered by DOMAIN-SUFFIX,example.com" \
  "$TMP_DIR/domain-coverage-order/domain" \
  "$TMP_DIR/domain-coverage-order/ip"

make_case_dirs "$TMP_DIR/domain-regex"
cat > "$TMP_DIR/domain-regex/domain/example.list" <<'EOF'
DOMAIN-REGEX,[
EOF
assert_lint_fails_with \
  "domain-regex" \
  "invalid DOMAIN-REGEX pattern" \
  "$TMP_DIR/domain-regex/domain" \
  "$TMP_DIR/domain-regex/ip"

make_case_dirs "$TMP_DIR/ip-canonical"
cat > "$TMP_DIR/ip-canonical/ip/private.list" <<'EOF'
IP-CIDR,192.168.1.1/24
EOF
assert_lint_fails_with \
  "ip-canonical" \
  "CIDR must be canonical; use 192.168.1.0/24 instead of 192.168.1.1/24" \
  "$TMP_DIR/ip-canonical/domain" \
  "$TMP_DIR/ip-canonical/ip"

make_case_dirs "$TMP_DIR/ip-coverage"
cat > "$TMP_DIR/ip-coverage/ip/private.list" <<'EOF'
IP-CIDR,10.0.0.0/8
IP-CIDR,10.1.0.0/16
EOF
assert_lint_fails_with \
  "ip-coverage" \
  "IP-CIDR,10.1.0.0/16 is covered by IP-CIDR,10.0.0.0/8" \
  "$TMP_DIR/ip-coverage/domain" \
  "$TMP_DIR/ip-coverage/ip"

make_case_dirs "$TMP_DIR/ip-coverage-order"
cat > "$TMP_DIR/ip-coverage-order/ip/private.list" <<'EOF'
IP-CIDR,10.0.0.0/8
IP-CIDR,10.1.0.0/16
IP-CIDR,10.1.2.0/24
EOF
assert_lint_fails_with \
  "ip-coverage-order" \
  "IP-CIDR,10.1.0.0/16 is covered by IP-CIDR,10.0.0.0/8" \
  "$TMP_DIR/ip-coverage-order/domain" \
  "$TMP_DIR/ip-coverage-order/ip"

make_case_dirs "$TMP_DIR/empty-file"
: > "$TMP_DIR/empty-file/domain/empty.list"
assert_lint_fails_with \
  "empty-file" \
  "has no effective rules" \
  "$TMP_DIR/empty-file/domain" \
  "$TMP_DIR/empty-file/ip"

make_case_dirs "$TMP_DIR/invalid-name"
cat > "$TMP_DIR/invalid-name/domain/Bad_Name.list" <<'EOF'
DOMAIN,api.example.com
EOF
assert_lint_fails_with \
  "invalid-name" \
  "invalid custom rule filename" \
  "$TMP_DIR/invalid-name/domain" \
  "$TMP_DIR/invalid-name/ip"

make_case_dirs "$TMP_DIR/canonical-type"
printf '%s\n' 'domain,api.example.com' > "$TMP_DIR/canonical-type/domain/example.list"
assert_lint_fails_with \
  "canonical-type" \
  "rule type must be canonical; use DOMAIN instead of domain" \
  "$TMP_DIR/canonical-type/domain" \
  "$TMP_DIR/canonical-type/ip"

make_case_dirs "$TMP_DIR/canonical-value"
printf '%s\n' 'DOMAIN,Api.Example.com' > "$TMP_DIR/canonical-value/domain/example.list"
printf '%s\n' 'ip_cidr,192.0.2.0/24' > "$TMP_DIR/canonical-value/ip/example.list"
assert_lint_fails_with \
  "canonical-value" \
  "DOMAIN value must be lowercase: Api.Example.com" \
  "$TMP_DIR/canonical-value/domain" \
  "$TMP_DIR/canonical-value/ip"
if ! grep -Fq "rule type must be canonical; use IP-CIDR instead of ip_cidr" "$TMP_DIR/canonical-value.stderr"; then
  echo "test failed: missing strict IP rule type error" >&2
  cat "$TMP_DIR/canonical-value.stderr" >&2
  exit 1
fi

make_case_dirs "$TMP_DIR/cross-domain"
printf '%s\n' 'DOMAIN-SUFFIX,example.com' > "$TMP_DIR/cross-domain/domain/base.list"
printf '%s\n' 'DOMAIN,api.example.com' > "$TMP_DIR/cross-domain/domain/specific.list"
assert_lint_fails_with \
  "cross-domain" \
  "DOMAIN,api.example.com is covered by DOMAIN-SUFFIX,example.com" \
  "$TMP_DIR/cross-domain/domain" \
  "$TMP_DIR/cross-domain/ip"

make_case_dirs "$TMP_DIR/cross-ip"
printf '%s\n' 'IP-CIDR,10.0.0.0/8' > "$TMP_DIR/cross-ip/ip/base.list"
printf '%s\n' 'IP-CIDR,10.1.0.0/16' > "$TMP_DIR/cross-ip/ip/specific.list"
assert_lint_fails_with \
  "cross-ip" \
  "IP-CIDR,10.1.0.0/16 is covered by IP-CIDR,10.0.0.0/8" \
  "$TMP_DIR/cross-ip/domain" \
  "$TMP_DIR/cross-ip/ip"

make_case_dirs "$TMP_DIR/cross-duplicates"
printf '%s\n' 'DOMAIN,api.example.com' > "$TMP_DIR/cross-duplicates/domain/a.list"
printf '%s\n' 'DOMAIN,api.example.com' > "$TMP_DIR/cross-duplicates/domain/b.list"
printf '%s\n' 'IP-CIDR,192.0.2.0/24' > "$TMP_DIR/cross-duplicates/ip/a.list"
printf '%s\n' 'IP-CIDR,192.0.2.0/24' > "$TMP_DIR/cross-duplicates/ip/b.list"
assert_lint_fails_with \
  "cross-duplicates" \
  "duplicate domain rule; first seen" \
  "$TMP_DIR/cross-duplicates/domain" \
  "$TMP_DIR/cross-duplicates/ip"
if ! grep -Fq "duplicate ip rule; first seen" "$TMP_DIR/cross-duplicates.stderr"; then
  echo "test failed: missing cross-file duplicate IP error" >&2
  cat "$TMP_DIR/cross-duplicates.stderr" >&2
  exit 1
fi

cat > "$TMP_DIR/cross-domain/allowed.json" <<'EOF'
{"version":1,"relations":[{"family":"domain","covered":{"file":"specific.list","rule":"DOMAIN,api.example.com"},"covering":{"file":"base.list","rule":"DOMAIN-SUFFIX,example.com"}}]}
EOF
python3 "$TOOL" \
  --domain-dir "$TMP_DIR/cross-domain/domain" \
  --ip-dir "$TMP_DIR/cross-domain/ip" \
  --conflicts "$TMP_DIR/cross-domain/allowed.json" >/dev/null

cat > "$TMP_DIR/cross-domain/stale.json" <<'EOF'
{"version":1,"relations":[{"family":"domain","covered":{"file":"specific.list","rule":"DOMAIN,missing.example.com"},"covering":{"file":"base.list","rule":"DOMAIN-SUFFIX,example.com"}}]}
EOF
if python3 "$TOOL" --domain-dir "$TMP_DIR/cross-domain/domain" --ip-dir "$TMP_DIR/cross-domain/ip" \
  --conflicts "$TMP_DIR/cross-domain/stale.json" > /dev/null 2>"$TMP_DIR/stale.stderr"; then
  echo "test failed: stale allowlist should fail" >&2
  exit 1
fi
grep -Fq "stale conflict allowlist relation" "$TMP_DIR/stale.stderr"

cat > "$TMP_DIR/cross-domain/duplicate.json" <<'EOF'
{"version":1,"relations":[{"family":"domain","covered":{"file":"specific.list","rule":"DOMAIN,api.example.com"},"covering":{"file":"base.list","rule":"DOMAIN-SUFFIX,example.com"}},{"family":"domain","covered":{"file":"specific.list","rule":"DOMAIN,api.example.com"},"covering":{"file":"base.list","rule":"DOMAIN-SUFFIX,example.com"}}]}
EOF
if python3 "$TOOL" --domain-dir "$TMP_DIR/cross-domain/domain" --ip-dir "$TMP_DIR/cross-domain/ip" \
  --conflicts "$TMP_DIR/cross-domain/duplicate.json" > /dev/null 2>"$TMP_DIR/duplicate.stderr"; then
  echo "test failed: duplicate allowlist relation should fail" >&2
  exit 1
fi
grep -Fq "duplicates an earlier allowlisted relation" "$TMP_DIR/duplicate.stderr"

cat > "$TMP_DIR/cross-domain/broad.json" <<'EOF'
{"version":1,"relations":[{"family":"domain","covered":{"file":"specific.list"},"covering":{"file":"base.list"}}]}
EOF
if python3 "$TOOL" --domain-dir "$TMP_DIR/cross-domain/domain" --ip-dir "$TMP_DIR/cross-domain/ip" \
  --conflicts "$TMP_DIR/cross-domain/broad.json" > /dev/null 2>"$TMP_DIR/broad.stderr"; then
  echo "test failed: broad allowlist should fail" >&2
  exit 1
fi
grep -Fq "must contain exactly 'file' and 'rule'" "$TMP_DIR/broad.stderr"

python3 "$TOOL" \
  --domain-dir "$ROOT/sources/custom/domain" \
  --ip-dir "$ROOT/sources/custom/ip" \
  --conflicts "$ROOT/config/custom-rule-conflicts.json" >/dev/null

echo "custom rule quality tests passed"
