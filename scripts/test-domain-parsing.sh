#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/lib/rules.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_file_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if ! diff -u "$expected" "$actual"; then
    echo "test failed: $label" >&2
    exit 1
  fi
}

test_export_alias_prefixes() {
  mkdir -p "$TMP_DIR/export_alias/data" "$TMP_DIR/export_alias/out"
  cat > "$TMP_DIR/export_alias/data/a" <<'EOF'
domain-suffix:Example.COM.
domain_suffix:foo.com
suffix:bar.com
domain-full:Api.Example.com.
domain-keyword:YouTube
domain-regex:^Foo\\.
regex:^bar$
example.org
EOF

  python3 "$ROOT/scripts/export-domain-rules.py" export \
    "$TMP_DIR/export_alias/data" \
    "$TMP_DIR/export_alias/out"

  cat > "$TMP_DIR/export_alias/expected.list" <<'EOF'
DOMAIN,api.example.com
DOMAIN-KEYWORD,youtube
DOMAIN-REGEX,^Foo\\.
DOMAIN-REGEX,^bar$
DOMAIN-SUFFIX,bar.com
DOMAIN-SUFFIX,example.com
DOMAIN-SUFFIX,example.org
DOMAIN-SUFFIX,foo.com
EOF

  assert_file_equals \
    "$TMP_DIR/export_alias/expected.list" \
    "$TMP_DIR/export_alias/out/a.list" \
    "export supports domain prefix aliases"
}

test_export_unknown_prefix_fails() {
  mkdir -p "$TMP_DIR/export_error/data" "$TMP_DIR/export_error/out"
  cat > "$TMP_DIR/export_error/data/b" <<'EOF'
unknownprefix:example.com
EOF

  if python3 "$ROOT/scripts/export-domain-rules.py" export \
    "$TMP_DIR/export_error/data" \
    "$TMP_DIR/export_error/out" >"$TMP_DIR/export_error/stdout" 2>"$TMP_DIR/export_error/stderr"; then
    echo "test failed: export should reject unknown prefix" >&2
    exit 1
  fi

  if ! grep -q "unsupported rule prefix: unknownprefix" "$TMP_DIR/export_error/stderr"; then
    echo "test failed: missing unknown-prefix error message" >&2
    cat "$TMP_DIR/export_error/stderr" >&2
    exit 1
  fi
}

test_custom_domain_normalization() {
  cat > "$TMP_DIR/custom_in.list" <<'EOF'
domain_suffix,Example.COM.
domain,API.Example.COM
DOMAIN-KEYWORD,YouTube
EOF

  normalize_custom_domain_source "$TMP_DIR/custom_in.list" "$TMP_DIR/custom_out.list"

  cat > "$TMP_DIR/custom_expected.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN,api.example.com
DOMAIN-KEYWORD,youtube
EOF

  assert_file_equals \
    "$TMP_DIR/custom_expected.list" \
    "$TMP_DIR/custom_out.list" \
    "custom domain normalization is stable"
}

test_include_filter_semantics() {
  mkdir -p "$TMP_DIR/include_filter/data" "$TMP_DIR/include_filter/out"
  cat > "$TMP_DIR/include_filter/data/base" <<'EOF'
domain:example.com @cn
domain:ads.example.com @cn @ads
full:exact.example.com @cn
domain:global.example
EOF

  cat > "$TMP_DIR/include_filter/data/filtered" <<'EOF'
include:base @cn @-ads
EOF

  python3 "$ROOT/scripts/export-domain-rules.py" export \
    "$TMP_DIR/include_filter/data" \
    "$TMP_DIR/include_filter/out"

  cat > "$TMP_DIR/include_filter/expected.list" <<'EOF'
DOMAIN,exact.example.com
DOMAIN-SUFFIX,example.com
EOF

  assert_file_equals \
    "$TMP_DIR/include_filter/expected.list" \
    "$TMP_DIR/include_filter/out/filtered.list" \
    "include filters match required attrs and exclude blocked attrs"
}

test_export_alias_prefixes
test_export_unknown_prefix_fails
test_custom_domain_normalization
test_include_filter_semantics

echo "domain parsing tests passed"
