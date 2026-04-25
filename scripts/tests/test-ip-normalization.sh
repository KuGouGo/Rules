#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

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

echo "ip normalization tests passed"
