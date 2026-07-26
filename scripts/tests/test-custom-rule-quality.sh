#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/tools/lint-custom-rules.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_lint() {
  python3 "$TOOL" --domain-dir "$1/domain" --ip-dir "$1/ip"
}

make_case() {
  mkdir -p "$TMP_DIR/$1/domain" "$TMP_DIR/$1/ip"
}

make_case valid
cat > "$TMP_DIR/valid/domain/example.list" <<'EOF'
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.net
DOMAIN-KEYWORD,emby
DOMAIN-REGEX,^(.+\.)?example\.org$
EOF
cat > "$TMP_DIR/valid/ip/example.list" <<'EOF'
IP-CIDR,192.0.2.0/24
IP-CIDR6,2001:db8::/32
EOF
run_lint "$TMP_DIR/valid" >/dev/null

make_case invalid-domain
printf '%s\n' 'DOMAIN,Api.Example.com' > "$TMP_DIR/invalid-domain/domain/example.list"
if run_lint "$TMP_DIR/invalid-domain" > /dev/null 2>"$TMP_DIR/error"; then
  echo "test failed: invalid domain passed" >&2
  exit 1
fi
grep -Fq 'DOMAIN value must be lowercase' "$TMP_DIR/error"

make_case invalid-cidr
printf '%s\n' 'IP-CIDR,192.168.1.1/24' > "$TMP_DIR/invalid-cidr/ip/example.list"
if run_lint "$TMP_DIR/invalid-cidr" > /dev/null 2>"$TMP_DIR/error"; then
  echo "test failed: non-canonical CIDR passed" >&2
  exit 1
fi
grep -Fq 'CIDR must be canonical' "$TMP_DIR/error"

make_case redundant
cat > "$TMP_DIR/redundant/domain/example.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN,api.example.com
EOF
if run_lint "$TMP_DIR/redundant" > /dev/null 2>"$TMP_DIR/error"; then
  echo "test failed: within-file redundancy passed" >&2
  exit 1
fi
grep -Fq 'is covered by DOMAIN-SUFFIX,example.com' "$TMP_DIR/error"

make_case intentional-overlap
printf '%s\n' 'DOMAIN-SUFFIX,example.com' > "$TMP_DIR/intentional-overlap/domain/general.list"
printf '%s\n' 'DOMAIN,api.example.com' > "$TMP_DIR/intentional-overlap/domain/specific.list"
run_lint "$TMP_DIR/intentional-overlap" >/dev/null

run_lint "$ROOT/sources/custom" >/dev/null

echo "custom rule quality tests passed"
