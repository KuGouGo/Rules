#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/lib/rules.sh"

TMP_DIR="$(mktemp -d)"
FIXTURE_ROOT="$ROOT/tests/fixtures/domain"
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

assert_file_text_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  local expected_text actual_text

  expected_text="$(cat "$expected")"
  actual_text="$(cat "$actual")"
  if [ "$expected_text" != "$actual_text" ]; then
    echo "test failed: $label" >&2
    diff -u "$expected" "$actual" || true
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

test_classical_domain_fixture_outputs() {
  local fixture_name="mixed"
  local input_file="$FIXTURE_ROOT/input/$fixture_name.list"
  local normalized_out="$TMP_DIR/$fixture_name.normalized.list"
  local surge_out="$TMP_DIR/$fixture_name.surge.list"
  local quanx_out="$TMP_DIR/$fixture_name.quanx.list"
  local egern_out="$TMP_DIR/$fixture_name.egern.yaml"
  local mihomo_out="$TMP_DIR/$fixture_name.mihomo.txt"
  local singbox_out="$TMP_DIR/$fixture_name.singbox.json"

  normalize_custom_domain_source "$input_file" "$normalized_out"
  render_surge_domain_ruleset_from_rules "$normalized_out" "$surge_out"
  render_quanx_domain_ruleset_from_rules "$normalized_out" "$quanx_out" "$fixture_name"
  render_egern_domain_ruleset_from_rules "$normalized_out" "$egern_out"
  build_mihomo_domain_text_from_rules "$normalized_out" "$mihomo_out"
  build_domain_json_from_rules "$normalized_out" "$singbox_out"

  assert_file_equals \
    "$FIXTURE_ROOT/expected/$fixture_name.normalized.list" \
    "$normalized_out" \
    "normalized domain fixture output is stable"
  assert_file_equals \
    "$FIXTURE_ROOT/expected/$fixture_name.surge.list" \
    "$surge_out" \
    "surge domain fixture output is stable"
  assert_file_equals \
    "$FIXTURE_ROOT/expected/$fixture_name.quanx.list" \
    "$quanx_out" \
    "quanx domain fixture output is stable"
  assert_file_equals \
    "$FIXTURE_ROOT/expected/$fixture_name.egern.yaml" \
    "$egern_out" \
    "egern domain fixture output is stable"
  assert_file_equals \
    "$FIXTURE_ROOT/expected/$fixture_name.mihomo.txt" \
    "$mihomo_out" \
    "mihomo domain text fixture output is stable"
  assert_file_text_equals \
    "$FIXTURE_ROOT/expected/$fixture_name.singbox.json" \
    "$singbox_out" \
    "sing-box domain json fixture output is stable"
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

test_mihomo_domain_text_generation() {
  cat > "$TMP_DIR/mihomo_domain_in.list" <<'EOF'
DOMAIN,exact.example.com
DOMAIN-SUFFIX,example.org
DOMAIN-SUFFIX,example.org
DOMAIN-KEYWORD,ignored-keyword
DOMAIN-REGEX,^ignored$
EOF

  build_mihomo_domain_text_from_rules "$TMP_DIR/mihomo_domain_in.list" "$TMP_DIR/mihomo_domain_out.txt"

  cat > "$TMP_DIR/mihomo_domain_expected.txt" <<'EOF'
exact.example.com
.example.org
EOF

  assert_file_equals \
    "$TMP_DIR/mihomo_domain_expected.txt" \
    "$TMP_DIR/mihomo_domain_out.txt" \
    "mihomo domain text keeps only DOMAIN/DOMAIN-SUFFIX entries"

  cat > "$TMP_DIR/mihomo_keyword_only.list" <<'EOF'
DOMAIN-KEYWORD,only-keyword
DOMAIN-REGEX,^only-regex$
EOF

  build_mihomo_domain_text_from_rules "$TMP_DIR/mihomo_keyword_only.list" "$TMP_DIR/mihomo_keyword_only_out.txt"
  if [ -s "$TMP_DIR/mihomo_keyword_only_out.txt" ]; then
    echo "test failed: keyword/regex-only input should produce empty mihomo domain text" >&2
    exit 1
  fi
}

test_export_alias_prefixes
test_export_unknown_prefix_fails
test_classical_domain_fixture_outputs
test_include_filter_semantics
test_mihomo_domain_text_generation

echo "domain parsing tests passed"
