#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/lib/rules.sh"

TMP_DIR="$(mktemp -d)"
FIXTURE_ROOT="$ROOT/tests/fixtures/domain"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_egern_yaml_parses() {
  local file="$1"
  python3 - "$file" <<'PYCODE'
import sys
from pathlib import Path

allowed = {"domain_set", "domain_suffix_set", "domain_keyword_set", "domain_regex_set", "ip_cidr_set"}
current = None
for line_no, raw_line in enumerate(Path(sys.argv[1]).read_text(encoding="utf-8").splitlines(), start=1):
    if not raw_line.strip():
        continue
    if raw_line in {"no_resolve: true", "no_resolve: false"}:
        current = "no_resolve"
        continue
    if raw_line.endswith(":") and not raw_line.startswith(" "):
        current = raw_line[:-1]
        if current not in allowed:
            raise SystemExit(f"unexpected Egern YAML key at line {line_no}: {current}")
        continue
    if raw_line.startswith("  - "):
        if current is None or current == "no_resolve":
            raise SystemExit(f"list entry without section at line {line_no}")
        continue
    raise SystemExit(f"unexpected Egern YAML line {line_no}: {raw_line}")
PYCODE
}

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

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/export_alias/data" \
    "$TMP_DIR/export_alias/out" \
    2>"$TMP_DIR/export_alias/stderr"

  cat > "$TMP_DIR/export_alias/expected.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN-SUFFIX,foo.com
DOMAIN-SUFFIX,bar.com
DOMAIN,api.example.com
DOMAIN-KEYWORD,youtube
DOMAIN-REGEX,^Foo\\.
DOMAIN-REGEX,^bar$
DOMAIN-SUFFIX,example.org
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

  if python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
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
  build_mihomo_domain_text_from_rules "$normalized_out" "$mihomo_out" \
    2>"$TMP_DIR/$fixture_name.mihomo.stderr"
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
  assert_egern_yaml_parses "$egern_out"
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

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/include_filter/data" \
    "$TMP_DIR/include_filter/out"

  cat > "$TMP_DIR/include_filter/expected.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN,exact.example.com
EOF

  assert_file_equals \
    "$TMP_DIR/include_filter/expected.list" \
    "$TMP_DIR/include_filter/out/filtered.list" \
    "include filters match required attrs and exclude blocked attrs"
}


test_export_preserves_upstream_order_and_cn_regex_policy() {
  mkdir -p "$TMP_DIR/cn_regex/data" "$TMP_DIR/cn_regex/out"
  cat > "$TMP_DIR/cn_regex/data/base" <<'EOF'
regexp:^cn-regex\.example$ @cn
keyword:cn-keyword @cn
domain:cn.example @cn
regexp:^not-cn-regex\.example$ @!cn
full:not-cn.example @!cn
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/cn_regex/data" \
    "$TMP_DIR/cn_regex/out" \
    2>"$TMP_DIR/cn_regex/stderr"

  cat > "$TMP_DIR/cn_regex/base_expected.list" <<'EOF'
DOMAIN-REGEX,^cn-regex\.example$
DOMAIN-KEYWORD,cn-keyword
DOMAIN-SUFFIX,cn.example
DOMAIN-REGEX,^not-cn-regex\.example$
DOMAIN,not-cn.example
EOF

  cat > "$TMP_DIR/cn_regex/base_cn_expected.list" <<'EOF'
DOMAIN-KEYWORD,cn-keyword
DOMAIN-SUFFIX,cn.example
EOF

  cat > "$TMP_DIR/cn_regex/base_not_cn_expected.list" <<'EOF'
DOMAIN,not-cn.example
EOF

  assert_file_equals \
    "$TMP_DIR/cn_regex/base_expected.list" \
    "$TMP_DIR/cn_regex/out/base.list" \
    "export preserves upstream order and regex in full list"
  assert_file_equals \
    "$TMP_DIR/cn_regex/base_cn_expected.list" \
    "$TMP_DIR/cn_regex/out/base@cn.list" \
    "@cn derivative intentionally filters regex entries"
  assert_file_equals \
    "$TMP_DIR/cn_regex/base_not_cn_expected.list" \
    "$TMP_DIR/cn_regex/out/base@!cn.list" \
    "@!cn derivative intentionally filters regex entries"
}


test_domain_capability_summary() {
  mkdir -p "$TMP_DIR/capability_summary/data" "$TMP_DIR/capability_summary/out"
  cat > "$TMP_DIR/capability_summary/data/base" <<'EOF'
domain:example.com
keyword:example-keyword
regexp:^example-regex$
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/capability_summary/data" \
    "$TMP_DIR/capability_summary/out" \
    >"$TMP_DIR/capability_summary/stdout" \
    2>"$TMP_DIR/capability_summary/stderr"

  grep -Fx "domain summary: base skips unsupported rules for mihomo-mrs: DOMAIN-KEYWORD=1, DOMAIN-REGEX=1" \
    "$TMP_DIR/capability_summary/stderr" >/dev/null || {
      echo "test failed: missing mihomo-mrs capability summary" >&2
      cat "$TMP_DIR/capability_summary/stderr" >&2
      exit 1
    }
  grep -Fx "domain summary: base skips unsupported rules for surge: DOMAIN-REGEX=1" \
    "$TMP_DIR/capability_summary/stderr" >/dev/null || {
      echo "test failed: missing surge capability summary" >&2
      cat "$TMP_DIR/capability_summary/stderr" >&2
      exit 1
    }
  grep -Fx "domain summary: base skips unsupported rules for quanx: DOMAIN-REGEX=1" \
    "$TMP_DIR/capability_summary/stderr" >/dev/null || {
      echo "test failed: missing quanx capability summary" >&2
      cat "$TMP_DIR/capability_summary/stderr" >&2
      exit 1
    }
}


test_mihomo_mrs_skip_summary() {
  cat > "$TMP_DIR/mihomo_summary_in.list" <<'EOF'
DOMAIN,exact.example.com
DOMAIN-SUFFIX,example.org
DOMAIN-KEYWORD,ignored-keyword
DOMAIN-REGEX,^ignored$
EOF

  build_mihomo_domain_text_from_rules "$TMP_DIR/mihomo_summary_in.list" "$TMP_DIR/mihomo_summary_out.txt" \
    2>"$TMP_DIR/mihomo_summary_stderr"

  grep -Fx "mihomo mrs summary: mihomo_summary_in.list skips unsupported rules: DOMAIN-KEYWORD=1, DOMAIN-REGEX=1" \
    "$TMP_DIR/mihomo_summary_stderr" >/dev/null || {
      echo "test failed: missing mihomo mrs skip summary" >&2
      cat "$TMP_DIR/mihomo_summary_stderr" >&2
      exit 1
    }
  grep -Fx "mihomo mrs warning: mihomo_summary_in.list skips 50% unsupported rules (threshold 30%)" \
    "$TMP_DIR/mihomo_summary_stderr" >/dev/null || {
      echo "test failed: missing mihomo mrs skip warning" >&2
      cat "$TMP_DIR/mihomo_summary_stderr" >&2
      exit 1
    }
}


test_mihomo_domain_text_generation() {
  cat > "$TMP_DIR/mihomo_domain_in.list" <<'EOF'
DOMAIN,exact.example.com
DOMAIN-SUFFIX,example.org
DOMAIN-SUFFIX,example.org
DOMAIN-KEYWORD,ignored-keyword
DOMAIN-REGEX,^ignored$
EOF

  build_mihomo_domain_text_from_rules "$TMP_DIR/mihomo_domain_in.list" "$TMP_DIR/mihomo_domain_out.txt" \
    2>"$TMP_DIR/mihomo_domain_stderr"

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

  build_mihomo_domain_text_from_rules "$TMP_DIR/mihomo_keyword_only.list" "$TMP_DIR/mihomo_keyword_only_out.txt" \
    2>"$TMP_DIR/mihomo_keyword_only_stderr"
  if [ -s "$TMP_DIR/mihomo_keyword_only_out.txt" ]; then
    echo "test failed: keyword/regex-only input should produce empty mihomo domain text" >&2
    exit 1
  fi
}

test_export_alias_prefixes
test_export_unknown_prefix_fails
test_classical_domain_fixture_outputs
test_include_filter_semantics
test_export_preserves_upstream_order_and_cn_regex_policy
test_domain_capability_summary
test_mihomo_mrs_skip_summary
test_mihomo_domain_text_generation

echo "domain parsing tests passed"
