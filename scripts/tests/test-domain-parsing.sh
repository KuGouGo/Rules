#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/rules.sh
source "$ROOT/scripts/lib/rules.sh"

TMP_DIR="$(mktemp -d)"
FIXTURE_ROOT="$ROOT/scripts/tests/fixtures/domain"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_egern_yaml_parses() {
  local file="$1"
  python3 - "$file" <<'PYCODE'
import sys
from pathlib import Path

allowed = {"domain_set", "domain_suffix_set", "domain_keyword_set", "domain_regex_set", "ip_cidr_set", "ip_cidr6_set"}
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

assert_file_absent() {
  local file="$1"
  local label="$2"

  if [ -e "$file" ]; then
    echo "test failed: $label" >&2
    echo "unexpected file exists: $file" >&2
    exit 1
  fi
}

assert_text_equals() {
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

test_compile_jobs_override_validation() {
  local actual

  actual="$(RULES_COMPILE_JOBS=2 detect_compile_jobs)"
  assert_text_equals "2" "$actual" "RULES_COMPILE_JOBS override is honored"

  if RULES_COMPILE_JOBS=0 detect_compile_jobs >"$TMP_DIR/compile_jobs.stdout" 2>"$TMP_DIR/compile_jobs.stderr"; then
    echo "test failed: RULES_COMPILE_JOBS=0 should fail" >&2
    exit 1
  fi
  if ! grep -Fxq "RULES_COMPILE_JOBS must be a positive integer" "$TMP_DIR/compile_jobs.stderr"; then
    echo "test failed: missing RULES_COMPILE_JOBS validation message" >&2
    cat "$TMP_DIR/compile_jobs.stderr" >&2
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

test_upstream_single_label_suffix() {
  mkdir -p "$TMP_DIR/tld_suffix/data" "$TMP_DIR/tld_suffix/out"
  printf '%s\n' 'alibaba' > "$TMP_DIR/tld_suffix/data/brand-tld"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/tld_suffix/data" \
    "$TMP_DIR/tld_suffix/out"
  python3 "$ROOT/scripts/tools/export-domain-rules.py" surge-list \
    "$TMP_DIR/tld_suffix/out/brand-tld.list" \
    "$TMP_DIR/tld_suffix/brand-tld.surge.list"

  grep -Fx 'DOMAIN-SUFFIX,alibaba' "$TMP_DIR/tld_suffix/brand-tld.surge.list" >/dev/null || {
    echo "test failed: upstream brand TLD suffix was not rendered" >&2
    exit 1
  }

  python3 - "$ROOT" "$TMP_DIR/tld_suffix/out/brand-tld.list" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "tools"))
from domain_rules import parse_classical_domain_file

_, errors = parse_classical_domain_file(Path(sys.argv[2]))
assert errors and "too broad" in errors[0], errors
PY
}

test_export_plain_yaml_artifact() {
  mkdir -p "$TMP_DIR/export_plain_yaml/out"
  cat > "$TMP_DIR/export_plain_yaml/dlc.dat_plain.yml" <<'EOF'
lists:
  - name: yaml-test
    length: 6
    rules:
      - "domain:Example.COM."
      - "full:Api.Example.COM."
      - "keyword:YouTube"
      - "regexp:^Foo\\."
      - "domain:example.com"
      - "full:api.example.com"
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/export_plain_yaml/dlc.dat_plain.yml" \
    "$TMP_DIR/export_plain_yaml/out" \
    2>"$TMP_DIR/export_plain_yaml/stderr"

  cat > "$TMP_DIR/export_plain_yaml/expected.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,youtube
DOMAIN-REGEX,^Foo\.
EOF

  assert_file_equals \
    "$TMP_DIR/export_plain_yaml/expected.list" \
    "$TMP_DIR/export_plain_yaml/out/yaml-test.list" \
    "export supports domain-list-community plain YAML artifacts"
}

test_export_plain_yaml_rejects_path_traversal_name() {
  mkdir -p "$TMP_DIR/export_traversal/out"
  cat > "$TMP_DIR/export_traversal/dlc.dat_plain.yml" <<'EOF'
lists:
  - name: ../../../../tmp/evil
    length: 1
    rules:
      - "domain:example.com"
EOF

  if python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/export_traversal/dlc.dat_plain.yml" \
    "$TMP_DIR/export_traversal/out" \
    2>"$TMP_DIR/export_traversal/stderr"; then
    echo "test failed: export accepted a path-traversal list name" >&2
    exit 1
  fi
  if ! grep -q "invalid list name" "$TMP_DIR/export_traversal/stderr"; then
    echo "test failed: expected invalid list name error, got: $(cat "$TMP_DIR/export_traversal/stderr")" >&2
    exit 1
  fi
  if [ -e "$TMP_DIR/evil.list" ]; then
    echo "test failed: path-traversal list name escaped the output dir" >&2
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

test_batch_domain_dir_outputs() {
  mkdir -p \
    "$TMP_DIR/batch/input" \
    "$TMP_DIR/batch/surge" \
    "$TMP_DIR/batch/quanx" \
    "$TMP_DIR/batch/egern" \
    "$TMP_DIR/batch/binary"
  cp "$FIXTURE_ROOT/input/mixed.list" "$TMP_DIR/batch/input/mixed.list"
  cat > "$TMP_DIR/batch/input/regex-only.list" <<'EOF'
DOMAIN-REGEX,^regex-only\.example$
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" text-platform-dirs \
    "$TMP_DIR/batch/input" \
    "$TMP_DIR/batch/surge" \
    "$TMP_DIR/batch/quanx" \
    "$TMP_DIR/batch/egern"

  SINGBOX_RULE_SET_VERSION=4 \
    python3 "$ROOT/scripts/tools/export-domain-rules.py" binary-input-dir \
      "$TMP_DIR/batch/input" \
      "$TMP_DIR/batch/binary" \
      2>"$TMP_DIR/batch/binary.stderr"

  assert_file_equals \
    "$FIXTURE_ROOT/expected/mixed.surge.list" \
    "$TMP_DIR/batch/surge/mixed.list" \
    "batch surge domain fixture output is stable"
  assert_file_equals \
    "$FIXTURE_ROOT/expected/mixed.quanx.list" \
    "$TMP_DIR/batch/quanx/mixed.list" \
    "batch quanx domain fixture output is stable"
  assert_file_equals \
    "$FIXTURE_ROOT/expected/mixed.egern.yaml" \
    "$TMP_DIR/batch/egern/mixed.yaml" \
    "batch egern domain fixture output is stable"
  assert_file_absent \
    "$TMP_DIR/batch/surge/regex-only.list" \
    "Surge skips regex-only domain lists"
  assert_file_absent \
    "$TMP_DIR/batch/quanx/regex-only.list" \
    "QuanX skips regex-only domain lists"
  grep -Fx "domain_regex_set:" "$TMP_DIR/batch/egern/regex-only.yaml" >/dev/null || {
    echo "test failed: Egern should keep regex-only domain lists" >&2
    cat "$TMP_DIR/batch/egern/regex-only.yaml" >&2
    exit 1
  }
  assert_file_text_equals \
    "$FIXTURE_ROOT/expected/mixed.singbox.json" \
    "$TMP_DIR/batch/binary/mixed.json" \
    "batch sing-box domain json fixture output is stable"
  assert_file_equals \
    "$FIXTURE_ROOT/expected/mixed.mihomo.txt" \
    "$TMP_DIR/batch/binary/mixed.mihomo.txt" \
    "batch mihomo domain text fixture output is stable"
}

test_include_filter_semantics() {
  mkdir -p "$TMP_DIR/include_filter/data" "$TMP_DIR/include_filter/out"
  cat > "$TMP_DIR/include_filter/data/base" <<'EOF'
domain:example.com @cn
domain:ads.example.com @cn @ads
full:exact.example.com @cn
keyword:cn-keyword @cn
regexp:^cn-regex\.example$ @cn
domain:global.example
EOF

  cat > "$TMP_DIR/include_filter/data/filtered" <<'EOF'
include:base @cn @-ads
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/include_filter/data" \
    "$TMP_DIR/include_filter/out" \
    2>"$TMP_DIR/include_filter/export.stderr"
  python3 "$ROOT/scripts/tools/export-domain-rules.py" text-platform-dirs \
    "$TMP_DIR/include_filter/out" \
    "$TMP_DIR/include_filter/surge" \
    "$TMP_DIR/include_filter/quanx" \
    "$TMP_DIR/include_filter/egern" \
    2>"$TMP_DIR/include_filter/text-platform.stderr"
  python3 "$ROOT/scripts/tools/export-domain-rules.py" binary-input-dir \
    "$TMP_DIR/include_filter/out" \
    "$TMP_DIR/include_filter/binary" \
    2>"$TMP_DIR/include_filter/binary.stderr"

  cat > "$TMP_DIR/include_filter/expected.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,cn-keyword
DOMAIN-REGEX,^cn-regex\.example$
EOF

  cat > "$TMP_DIR/include_filter/expected.surge.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,cn-keyword
EOF

  cat > "$TMP_DIR/include_filter/expected.mihomo.txt" <<'EOF'
.example.com
EOF

  assert_file_equals \
    "$TMP_DIR/include_filter/expected.list" \
    "$TMP_DIR/include_filter/out/filtered.list" \
    "include filters match required attrs, exclude blocked attrs, and preserve rule kinds"
  assert_file_equals \
    "$TMP_DIR/include_filter/expected.surge.list" \
    "$TMP_DIR/include_filter/surge/filtered.list" \
    "Surge renders supported include-filtered rule kinds"
  assert_file_equals \
    "$TMP_DIR/include_filter/expected.mihomo.txt" \
    "$TMP_DIR/include_filter/binary/filtered.mihomo.txt" \
    "mihomo keeps only supported include-filtered domain kinds"

  grep -Fx "domain_regex_set:" "$TMP_DIR/include_filter/egern/filtered.yaml" >/dev/null || {
    echo "test failed: Egern should render include-filtered regex rules" >&2
    cat "$TMP_DIR/include_filter/egern/filtered.yaml" >&2
    exit 1
  }

  python3 - "$TMP_DIR/include_filter/binary/filtered.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["rules"][0]
assert payload["domain_suffix"] == ["example.com"]
assert "domain" not in payload
assert payload["domain_keyword"] == ["cn-keyword"]
assert payload["domain_regex"] == [r"^cn-regex\.example$"]
PY
}


test_suffix_compaction_keeps_attr_derivative() {
  mkdir -p "$TMP_DIR/suffix_compaction/data" "$TMP_DIR/suffix_compaction/out"
  cat > "$TMP_DIR/suffix_compaction/data/base" <<'EOF'
domain:example.com
full:exact.example.com @cn
full:deeper.example.com @!cn
domain:child.example.com
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/suffix_compaction/data" \
    "$TMP_DIR/suffix_compaction/out"

  cat > "$TMP_DIR/suffix_compaction/base.expected" <<'EOF'
DOMAIN-SUFFIX,example.com
EOF

  assert_file_equals \
    "$TMP_DIR/suffix_compaction/base.expected" \
    "$TMP_DIR/suffix_compaction/out/base.list" \
    "base export drops suffix-covered rules"
  assert_file_absent \
    "$TMP_DIR/suffix_compaction/out/base@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"
  assert_file_absent \
    "$TMP_DIR/suffix_compaction/out/base@!cn.list" \
    "per-category @!cn derivative is folded into the geographic partition"
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

  assert_file_equals \
    "$TMP_DIR/cn_regex/base_expected.list" \
    "$TMP_DIR/cn_regex/out/base.list" \
    "export preserves upstream order and regex in full list"
  assert_file_absent \
    "$TMP_DIR/cn_regex/out/base@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"
  assert_file_absent \
    "$TMP_DIR/cn_regex/out/base@!cn.list" \
    "per-category @!cn derivative is folded into the geographic partition"
}


test_attr_derivatives_merge_duplicate_rule_attrs() {
  mkdir -p "$TMP_DIR/duplicate_attrs/data" "$TMP_DIR/duplicate_attrs/out"
  cat > "$TMP_DIR/duplicate_attrs/data/base" <<'EOF'
domain:shared.example @cn
domain:shared.example @ads
domain:shared.example @cn
domain:unique.example @cn
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/duplicate_attrs/data" \
    "$TMP_DIR/duplicate_attrs/out"

  cat > "$TMP_DIR/duplicate_attrs/base_expected.list" <<'EOF'
DOMAIN-SUFFIX,shared.example
DOMAIN-SUFFIX,unique.example
EOF

  assert_file_equals \
    "$TMP_DIR/duplicate_attrs/base_expected.list" \
    "$TMP_DIR/duplicate_attrs/out/base.list" \
    "base output deduplicates repeated rules"
  assert_file_absent \
    "$TMP_DIR/duplicate_attrs/out/base@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"
  assert_file_absent \
    "$TMP_DIR/duplicate_attrs/out/base@ads.list" \
    "@ads derivatives are not published"
}


test_regional_base_lists_apply_safe_attribute_policy() {
  mkdir -p "$TMP_DIR/regional_policy/data" "$TMP_DIR/regional_policy/out"
  cat > "$TMP_DIR/regional_policy/data/shared" <<'EOF'
domain:plain.example
domain:cn.example @cn
domain:not-cn.example @!cn
domain:ads.example @ads
domain:cn-ads.example @cn @ads
EOF
  cat > "$TMP_DIR/regional_policy/data/cn" <<'EOF'
include:shared
EOF
  cat > "$TMP_DIR/regional_policy/data/geolocation-cn" <<'EOF'
include:shared
EOF
  cat > "$TMP_DIR/regional_policy/data/geolocation-!cn" <<'EOF'
include:shared
EOF
  cat > "$TMP_DIR/regional_policy/data/category-standalone-cn" <<'EOF'
domain:standalone.example
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/regional_policy/data" \
    "$TMP_DIR/regional_policy/out"

  cat > "$TMP_DIR/regional_policy/cn.expected" <<'EOF'
DOMAIN-SUFFIX,plain.example
DOMAIN-SUFFIX,cn.example
EOF
  cat > "$TMP_DIR/regional_policy/not-cn.expected" <<'EOF'
DOMAIN-SUFFIX,not-cn.example
EOF
  cat > "$TMP_DIR/regional_policy/cn-attr.expected" <<'EOF'
DOMAIN-SUFFIX,cn-ads.example
EOF

  assert_file_equals \
    "$TMP_DIR/regional_policy/cn.expected" \
    "$TMP_DIR/regional_policy/out/cn.list" \
    "cn excludes ads and !cn rules from its default output"
  assert_file_equals \
    "$TMP_DIR/regional_policy/cn.expected" \
    "$TMP_DIR/regional_policy/out/geolocation-cn.list" \
    "geolocation-cn excludes ads and !cn rules from its default output"
  assert_file_equals \
    "$TMP_DIR/regional_policy/not-cn.expected" \
    "$TMP_DIR/regional_policy/out/geolocation-!cn.list" \
    "geolocation-!cn excludes attributes and exact rules owned by geolocation-cn"
  assert_file_absent \
    "$TMP_DIR/regional_policy/out/cn@ads.list" \
    "ads derivatives are not published"
  assert_file_absent \
    "$TMP_DIR/regional_policy/out/cn@!cn.list" \
    "per-category cn@!cn derivative is folded into geolocation-!cn"
  assert_file_equals \
    "$TMP_DIR/regional_policy/cn-attr.expected" \
    "$TMP_DIR/regional_policy/out/geolocation-!cn@cn.list" \
    "geolocation-!cn@cn aggregate covers @cn rules not in the cn base list"

  python3 "$ROOT/scripts/tools/audit-dlc-data.py" \
    "$TMP_DIR/regional_policy/data" \
    >"$TMP_DIR/regional_policy/audit.stdout" \
    2>"$TMP_DIR/regional_policy/audit.stderr"
  grep -Fx "DLC data audit passed (0 warning(s))" \
    "$TMP_DIR/regional_policy/audit.stdout" >/dev/null || {
      echo "test failed: handled geographic root overlap should not warn" >&2
      cat "$TMP_DIR/regional_policy/audit.stdout" >&2
      cat "$TMP_DIR/regional_policy/audit.stderr" >&2
      exit 1
    }
}


test_publish_policy_prunes_geographic_children() {
  mkdir -p "$TMP_DIR/publish_policy/data" "$TMP_DIR/publish_policy/out"
  cat > "$TMP_DIR/publish_policy/data/cn-provider" <<'EOF'
domain:cn-provider.example
EOF
  cat > "$TMP_DIR/publish_policy/data/foreign-common" <<'EOF'
domain:foreign-common.example
EOF
  cat > "$TMP_DIR/publish_policy/data/foreign-rare" <<'EOF'
domain:foreign-rare.example
EOF
  cat > "$TMP_DIR/publish_policy/data/standalone" <<'EOF'
domain:standalone.example
EOF
  cat > "$TMP_DIR/publish_policy/data/canonical-name" <<'EOF'
domain:compat.example
EOF
  cat > "$TMP_DIR/publish_policy/data/compat-name" <<'EOF'
include:canonical-name
EOF
  cat > "$TMP_DIR/publish_policy/data/cn" <<'EOF'
include:cn-provider
EOF
  cat > "$TMP_DIR/publish_policy/data/geolocation-cn" <<'EOF'
include:cn-provider
EOF
  cat > "$TMP_DIR/publish_policy/data/geolocation-!cn" <<'EOF'
include:foreign-common
include:foreign-rare
EOF
  cat > "$TMP_DIR/publish_policy/policy.json" <<'EOF'
{
  "common": {
    "geographic_roots": ["geolocation-!cn"],
    "geolocation_not_cn": ["foreign-common"],
    "standalone": ["canonical-name", "standalone"]
  },
  "compatibility_replacements": {
    "compat-name": "canonical-name"
  },
  "default_profile": "common",
  "extended": {
    "geographic_roots": [],
    "geolocation_not_cn": ["foreign-rare"],
    "standalone": "all"
  },
  "schema_version": 4
}
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/publish_policy/data" \
    "$TMP_DIR/publish_policy/out" \
    --publish-policy "$TMP_DIR/publish_policy/policy.json"

  for name in canonical-name cn geolocation-!cn foreign-common standalone; do
    [ -s "$TMP_DIR/publish_policy/out/$name.list" ] || {
      echo "test failed: publish policy omitted required list: $name" >&2
      exit 1
    }
  done
  assert_file_absent \
    "$TMP_DIR/publish_policy/out/cn-provider.list" \
    "publish policy omits geolocation-cn children"
  assert_file_absent \
    "$TMP_DIR/publish_policy/out/geolocation-cn.list" \
    "common profile uses the smaller cn compatibility aggregate"
  assert_file_absent \
    "$TMP_DIR/publish_policy/out/compat-name.list" \
    "common profile omits a validated compatibility alias"
  assert_file_absent \
    "$TMP_DIR/publish_policy/out/foreign-rare.list" \
    "publish policy omits uncommon geolocation-!cn children"
  grep -Fx "DOMAIN-SUFFIX,cn-provider.example" \
    "$TMP_DIR/publish_policy/out/cn.list" >/dev/null || {
      echo "test failed: pruned CN child rules must remain covered by cn" >&2
      exit 1
    }
  grep -Fx "DOMAIN-SUFFIX,foreign-rare.example" \
    "$TMP_DIR/publish_policy/out/geolocation-!cn.list" >/dev/null || {
      echo "test failed: pruned foreign child rules must remain in geolocation-!cn" >&2
      exit 1
    }

  printf 'domain:compat-only.example\n' >> "$TMP_DIR/publish_policy/data/compat-name"
  if python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
      "$TMP_DIR/publish_policy/data" \
      "$TMP_DIR/publish_policy/unsafe-common" \
      --publish-policy "$TMP_DIR/publish_policy/policy.json" \
      --publish-profile common \
      >"$TMP_DIR/publish_policy/unsafe-common.stdout" \
      2>"$TMP_DIR/publish_policy/unsafe-common.stderr"; then
    echo "test failed: common profile omitted an uncovered compatibility alias rule" >&2
    exit 1
  fi
  grep -F "compatibility replacement is no longer semantically safe: compat-name -> canonical-name" \
    "$TMP_DIR/publish_policy/unsafe-common.stderr" >/dev/null || {
    echo "test failed: uncovered compatibility guard message missing" >&2
    cat "$TMP_DIR/publish_policy/unsafe-common.stderr" >&2
    exit 1
  }
  # Drop the last line portably: BSD sed cannot express `sed -i '$d'`.
  awk 'NR > 1 { print prev } { prev = $0 }' \
    "$TMP_DIR/publish_policy/data/compat-name" > "$TMP_DIR/publish_policy/data/compat-name.tmp" \
    && mv "$TMP_DIR/publish_policy/data/compat-name.tmp" "$TMP_DIR/publish_policy/data/compat-name"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/publish_policy/data" \
    "$TMP_DIR/publish_policy/extended" \
    --publish-policy "$TMP_DIR/publish_policy/policy.json" \
    --publish-profile extended
  [ -s "$TMP_DIR/publish_policy/extended/foreign-rare.list" ] || {
    echo "test failed: extended profile should restore uncommon geographic children" >&2
    exit 1
  }
  assert_file_absent \
    "$TMP_DIR/publish_policy/extended/geolocation-cn.list" \
    "extended profile does not publish geolocation-cn (cn is the superset entry point)"
  [ -s "$TMP_DIR/publish_policy/extended/compat-name.list" ] || {
    echo "test failed: extended profile should restore compatibility aliases" >&2
    exit 1
  }
}


test_export_materializes_attr_derivatives_with_sing_geosite_filter() {
  mkdir -p "$TMP_DIR/region_derivatives/data" "$TMP_DIR/region_derivatives/out"
  cat > "$TMP_DIR/region_derivatives/data/vendor" <<'EOF'
domain:vendor-cn.example @cn
domain:vendor-ads.example @ads
domain:vendor-global.example
EOF
  cat > "$TMP_DIR/region_derivatives/data/cn" <<'EOF'
include:vendor
domain:mainland.example @cn
full:not-mainland.example @!cn
EOF
  cat > "$TMP_DIR/region_derivatives/data/vendor-cn" <<'EOF'
domain:vendor-region.example @cn
EOF
  cat > "$TMP_DIR/region_derivatives/data/vendor-!cn" <<'EOF'
domain:vendor-overseas.example @!cn
domain:vendor-overseas-cn.example @cn
EOF
  cat > "$TMP_DIR/region_derivatives/data/geolocation-cn" <<'EOF'
include:cn
EOF
  cat > "$TMP_DIR/region_derivatives/data/geolocation-!cn" <<'EOF'
include:vendor-!cn
EOF
  cat > "$TMP_DIR/region_derivatives/data/category-ai-!cn" <<'EOF'
domain:ai-overseas.example @!cn
EOF
  cat > "$TMP_DIR/region_derivatives/data/category-games-!cn" <<'EOF'
domain:games-mainland.example @cn
EOF
  cat > "$TMP_DIR/region_derivatives/data/apple" <<'EOF'
domain:apple-cn.example @cn
domain:apple-global.example
EOF
  cat > "$TMP_DIR/region_derivatives/data/tracking-ads" <<'EOF'
domain:tracking-ad.example @ads
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/region_derivatives/data" \
    "$TMP_DIR/region_derivatives/out"
  python3 "$ROOT/scripts/tools/export-domain-rules.py" domain-rule-manifest \
    "$TMP_DIR/region_derivatives/out" \
    "$TMP_DIR/region_derivatives/manifest.json"

  cat > "$TMP_DIR/region_derivatives/geo_not_cn_expected.list" <<'EOF'
DOMAIN-SUFFIX,vendor-overseas.example
DOMAIN-SUFFIX,ai-overseas.example
DOMAIN,not-mainland.example
EOF
  cat > "$TMP_DIR/region_derivatives/geo_not_cn_cn_expected.list" <<'EOF'
DOMAIN-SUFFIX,vendor-overseas-cn.example
DOMAIN-SUFFIX,apple-cn.example
DOMAIN-SUFFIX,games-mainland.example
DOMAIN-SUFFIX,vendor-region.example
EOF
  cat > "$TMP_DIR/region_derivatives/cn_expected.list" <<'EOF'
DOMAIN-SUFFIX,mainland.example
DOMAIN-SUFFIX,vendor-cn.example
DOMAIN-SUFFIX,vendor-global.example
EOF

  assert_file_equals \
    "$TMP_DIR/region_derivatives/geo_not_cn_expected.list" \
    "$TMP_DIR/region_derivatives/out/geolocation-!cn.list" \
    "geolocation-!cn folds in orphaned @!cn rules from the whole tree"
  assert_file_equals \
    "$TMP_DIR/region_derivatives/geo_not_cn_cn_expected.list" \
    "$TMP_DIR/region_derivatives/out/geolocation-!cn@cn.list" \
    "geolocation-!cn@cn aggregates @cn rules not in the cn base list"
  assert_file_equals \
    "$TMP_DIR/region_derivatives/cn_expected.list" \
    "$TMP_DIR/region_derivatives/out/cn.list" \
    "cn base list stays pure mainland"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/vendor@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/vendor-!cn@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/geolocation-cn@!cn.list" \
    "per-category @!cn derivative is folded into geolocation-!cn"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/cn@!cn.list" \
    "per-category @!cn derivative is folded into geolocation-!cn"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/category-games-!cn@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/tracking-ads@ads.list" \
    "ads derivatives are not published"

  cat > "$TMP_DIR/region_derivatives/apple_cn_expected.list" <<'EOF'
DOMAIN-SUFFIX,apple-cn.example
EOF
  assert_file_equals \
    "$TMP_DIR/region_derivatives/apple_cn_expected.list" \
    "$TMP_DIR/region_derivatives/out/apple@cn.list" \
    "apple@cn derivative is published for front-loaded direct routing"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/apple-global@cn.list" \
    "non-cn attrs do not generate derivatives"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/cn@cn.list" \
    "cn should not generate redundant @cn derivative"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/geolocation-cn@cn.list" \
    "geolocation-cn should not generate redundant @cn derivative"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/vendor-cn@cn.list" \
    "region-suffixed cn list should not generate redundant @cn derivative"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/vendor-!cn@!cn.list" \
    "region-suffixed !cn list should not generate redundant @!cn derivative"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/geolocation-!cn@!cn.list" \
    "geolocation-!cn should not generate redundant @!cn derivative"
  assert_file_absent \
    "$TMP_DIR/region_derivatives/out/category-ai-!cn@!cn.list" \
    "category-ai-!cn should not generate redundant @!cn derivative"

  python3 - "$TMP_DIR/region_derivatives/manifest.json" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
by_name = {entry["name"]: entry for entry in manifest["lists"]}
assert by_name["geolocation-cn"]["kind"] == "regional"
assert by_name["geolocation-cn"]["region_suffix"] == "cn"
assert by_name["geolocation-cn"]["region_base"] == "geolocation"
assert by_name["vendor-!cn"]["kind"] == "regional"
assert by_name["vendor-!cn"]["region_suffix"] == "!cn"
assert by_name["geolocation-!cn@cn"]["kind"] == "attr"
assert by_name["geolocation-!cn@cn"]["base"] == "geolocation-!cn"
assert by_name["geolocation-!cn@cn"]["attr"] == "cn"
assert by_name["geolocation-!cn@cn"]["base_kind"] == "regional"
assert by_name["geolocation-!cn@cn"]["base_region_suffix"] == "!cn"
assert by_name["geolocation-!cn@cn"]["base_region_base"] == "geolocation"
assert by_name["apple@cn"]["kind"] == "attr"
assert by_name["apple@cn"]["base"] == "apple"
assert by_name["apple@cn"]["attr"] == "cn"
assert "vendor@cn" not in by_name
assert "geolocation-cn@!cn" not in by_name
assert "cn@cn" not in by_name
assert "geolocation-cn@cn" not in by_name
assert "category-ai-!cn@!cn" not in by_name
assert "tracking-ads@ads" not in by_name
assert manifest["by_attr"] == {"cn": 2}
assert manifest["by_region_suffix"] == {"!cn": 4, "cn": 3}
PY
}


test_ads_category_collapse() {
  mkdir -p "$TMP_DIR/ads_collapse/data" "$TMP_DIR/ads_collapse/out"
  cat > "$TMP_DIR/ads_collapse/data/category-ads" <<'EOF'
domain:plain-ads.example @ads
EOF
  cat > "$TMP_DIR/ads_collapse/data/category-ads-ir" <<'EOF'
domain:ir-ads.example @ads
EOF
  cat > "$TMP_DIR/ads_collapse/data/category-ads-all" <<'EOF'
include:category-ads
include:category-ads-ir
domain:cn-ads.example @cn @ads
domain:not-cn-ads.example @!cn @ads
domain:global-ads.example @ads
EOF
  cat > "$TMP_DIR/ads_collapse/data/vendor" <<'EOF'
domain:vendor-cn.example @cn
domain:vendor-ads.example @ads
domain:vendor-global.example
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/ads_collapse/data" \
    "$TMP_DIR/ads_collapse/out"
  python3 "$ROOT/scripts/tools/export-domain-rules.py" domain-rule-manifest \
    "$TMP_DIR/ads_collapse/out" \
    "$TMP_DIR/ads_collapse/manifest.json"

  cat > "$TMP_DIR/ads_collapse/expected.list" <<'EOF'
DOMAIN-SUFFIX,cn-ads.example
DOMAIN-SUFFIX,not-cn-ads.example
DOMAIN-SUFFIX,global-ads.example
DOMAIN-SUFFIX,plain-ads.example
DOMAIN-SUFFIX,ir-ads.example
EOF

  assert_file_equals \
    "$TMP_DIR/ads_collapse/expected.list" \
    "$TMP_DIR/ads_collapse/out/category-ads-all.list" \
    "category-ads-all is the single flat ads product"
  assert_file_absent \
    "$TMP_DIR/ads_collapse/out/category-ads.list" \
    "plain category-ads list is not published"
  assert_file_absent \
    "$TMP_DIR/ads_collapse/out/category-ads-ir.list" \
    "plain category-ads-ir list is not published"
  assert_file_absent \
    "$TMP_DIR/ads_collapse/out/category-ads-all@cn.list" \
    "category-ads-all does not publish an @cn derivative"
  assert_file_absent \
    "$TMP_DIR/ads_collapse/out/category-ads-all@!cn.list" \
    "category-ads-all does not publish an @!cn derivative"
  assert_file_absent \
    "$TMP_DIR/ads_collapse/out/vendor@ads.list" \
    "ads derivatives are not published"
  assert_file_absent \
    "$TMP_DIR/ads_collapse/out/vendor@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"

  python3 - "$TMP_DIR/ads_collapse/manifest.json" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
by_name = {entry["name"]: entry for entry in manifest["lists"]}
assert "category-ads-all" in by_name
assert "category-ads" not in by_name
assert "category-ads-ir" not in by_name
assert "category-ads-all@cn" not in by_name
assert "category-ads-all@!cn" not in by_name
PY
}


test_geographic_partition_folds_regional_attributes() {
  mkdir -p "$TMP_DIR/partition_fold/data" "$TMP_DIR/partition_fold/out"
  cat > "$TMP_DIR/partition_fold/data/cn" <<'EOF'
domain:mainland.example @cn
domain:covered.example @cn
EOF
  cat > "$TMP_DIR/partition_fold/data/geolocation-cn" <<'EOF'
include:cn
EOF
  cat > "$TMP_DIR/partition_fold/data/geolocation-!cn" <<'EOF'
domain:foreign.example
EOF
  cat > "$TMP_DIR/partition_fold/data/tencent" <<'EOF'
domain:tencent-cn.example @cn
domain:tencent-overseas.example @!cn
EOF
  cat > "$TMP_DIR/partition_fold/data/icbc" <<'EOF'
domain:icbc-overseas.example @!cn
EOF
  cat > "$TMP_DIR/partition_fold/data/vendor" <<'EOF'
domain:vendor-foreign-cn.example @cn
full:api.covered.example @cn
domain:child.covered.example @cn
full:api.notcovered.example @cn
EOF

  python3 "$ROOT/scripts/tools/export-domain-rules.py" export \
    "$TMP_DIR/partition_fold/data" \
    "$TMP_DIR/partition_fold/out"

  cat > "$TMP_DIR/partition_fold/geo_not_cn.expected" <<'EOF'
DOMAIN-SUFFIX,foreign.example
DOMAIN-SUFFIX,icbc-overseas.example
DOMAIN-SUFFIX,tencent-overseas.example
EOF
  cat > "$TMP_DIR/partition_fold/geo_not_cn_cn.expected" <<'EOF'
DOMAIN-SUFFIX,tencent-cn.example
DOMAIN-SUFFIX,vendor-foreign-cn.example
DOMAIN,api.notcovered.example
EOF
  cat > "$TMP_DIR/partition_fold/cn.expected" <<'EOF'
DOMAIN-SUFFIX,mainland.example
DOMAIN-SUFFIX,covered.example
EOF

  assert_file_equals \
    "$TMP_DIR/partition_fold/geo_not_cn.expected" \
    "$TMP_DIR/partition_fold/out/geolocation-!cn.list" \
    "orphaned @!cn rules fold into geolocation-!cn for proxy coverage"
  assert_file_equals \
    "$TMP_DIR/partition_fold/geo_not_cn_cn.expected" \
    "$TMP_DIR/partition_fold/out/geolocation-!cn@cn.list" \
    "orphaned @cn rules fold into the geolocation-!cn@cn aggregate"
  assert_file_equals \
    "$TMP_DIR/partition_fold/cn.expected" \
    "$TMP_DIR/partition_fold/out/cn.list" \
    "cn base list keeps only its own rules"
  assert_file_absent \
    "$TMP_DIR/partition_fold/out/tencent@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"
  assert_file_absent \
    "$TMP_DIR/partition_fold/out/tencent@!cn.list" \
    "per-category @!cn derivative is folded into geolocation-!cn"
  assert_file_absent \
    "$TMP_DIR/partition_fold/out/vendor@cn.list" \
    "per-category @cn derivative is folded into the geographic partition"
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

  grep -Fx "domain batch summary: mihomo skips unsupported rules in 1 list(s): DOMAIN-KEYWORD=1, DOMAIN-REGEX=1" \
    "$TMP_DIR/capability_summary/stderr" >/dev/null || {
      echo "test failed: missing mihomo-mrs capability summary" >&2
      cat "$TMP_DIR/capability_summary/stderr" >&2
      exit 1
    }
  grep -Fx "domain batch summary: surge skips unsupported rules in 1 list(s): DOMAIN-REGEX=1" \
    "$TMP_DIR/capability_summary/stderr" >/dev/null || {
      echo "test failed: missing surge capability summary" >&2
      cat "$TMP_DIR/capability_summary/stderr" >&2
      exit 1
    }
  grep -Fx "domain batch summary: quanx skips unsupported rules in 1 list(s): DOMAIN-REGEX=1" \
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


test_classical_comments_preserve_hash_values() {
  cat > "$TMP_DIR/hash-values.list" <<'EOF'
# full-line comment
   # indented full-line comment
DOMAIN-REGEX,^foo#bar$
DOMAIN-KEYWORD,hash#value
EOF

  python3 - "$ROOT" "$TMP_DIR/hash-values.list" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "tools"))
from domain_rules import parse_classical_domain_file

rules, errors = parse_classical_domain_file(Path(sys.argv[2]))
assert not errors, errors
assert [rule.text for rule in rules] == [
    r"DOMAIN-REGEX,^foo#bar$",
    "DOMAIN-KEYWORD,hash#value",
]
PY
}


test_mihomo_domain_text_generation() {
  cat > "$TMP_DIR/mihomo_domain_in.list" <<'EOF'
DOMAIN,exact.example.com
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

test_domain_semantic_compile_cache() {
  local cache_root="$TMP_DIR/compile-cache/cache"
  local bin_dir="$TMP_DIR/compile-cache/bin"
  local singbox_tmp="$TMP_DIR/compile-cache/singbox-tmp"
  local singbox_out="$TMP_DIR/compile-cache/singbox-out"
  local mihomo_tmp="$TMP_DIR/compile-cache/mihomo-tmp"
  local mihomo_out="$TMP_DIR/compile-cache/mihomo-out"
  mkdir -p "$bin_dir" "$singbox_tmp" "$singbox_out" "$mihomo_tmp" "$mihomo_out"

  cat > "$bin_dir/sing-box" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo run >> "$FAKE_SINGBOX_COUNTER"
cp "$3" "$5"
EOF
  cat > "$bin_dir/mihomo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo run >> "$FAKE_MIHOMO_COUNTER"
cp "$4" "$5"
EOF
  chmod +x "$bin_dir/sing-box" "$bin_dir/mihomo"
  export FAKE_SINGBOX_COUNTER="$TMP_DIR/compile-cache/singbox-counter"
  export FAKE_MIHOMO_COUNTER="$TMP_DIR/compile-cache/mihomo-counter"
  printf '{"version":4}\n' > "$singbox_tmp/base.json"
  printf '.example.org\n' > "$mihomo_tmp/base.mihomo.txt"

  PATH="$bin_dir:$PATH" compile_domain_singbox_json_dir \
    "$singbox_tmp" "$singbox_out" 1 "$cache_root/singbox" >/dev/null
  PATH="$bin_dir:$PATH" compile_domain_mihomo_text_dir \
    "$mihomo_tmp" "$mihomo_out" 1 "$cache_root/mihomo" >/dev/null
  rm -f "$singbox_out/base.srs" "$mihomo_out/base.mrs"
  PATH="$bin_dir:$PATH" compile_domain_singbox_json_dir \
    "$singbox_tmp" "$singbox_out" 1 "$cache_root/singbox" >/dev/null
  PATH="$bin_dir:$PATH" compile_domain_mihomo_text_dir \
    "$mihomo_tmp" "$mihomo_out" 1 "$cache_root/mihomo" >/dev/null

  assert_text_equals "1" "$(wc -l < "$FAKE_SINGBOX_COUNTER" | tr -d ' ')" \
    "sing-box semantic cache avoids recompiling unchanged input"
  assert_text_equals "1" "$(wc -l < "$FAKE_MIHOMO_COUNTER" | tr -d ' ')" \
    "mihomo semantic cache avoids recompiling unchanged input"

  cached_srs="$(find "$cache_root/singbox" -type f -name '*.srs' | head -n 1)"
  printf 'corrupt\n' >> "$cached_srs"
  rm -f "$singbox_out/base.srs"
  PATH="$bin_dir:$PATH" compile_domain_singbox_json_dir \
    "$singbox_tmp" "$singbox_out" 1 "$cache_root/singbox" >/dev/null
  assert_text_equals "2" "$(wc -l < "$FAKE_SINGBOX_COUNTER" | tr -d ' ')" \
    "semantic cache recompiles a corrupted cache entry"

  printf '{"version":4,"rules":[{"domain_suffix":["changed.example"]}]}\n' > "$singbox_tmp/base.json"
  PATH="$bin_dir:$PATH" compile_domain_singbox_json_dir \
    "$singbox_tmp" "$singbox_out" 1 "$cache_root/singbox" >/dev/null
  assert_text_equals "3" "$(wc -l < "$FAKE_SINGBOX_COUNTER" | tr -d ' ')" \
    "semantic cache invalidates changed input"
}

test_compile_jobs_override_validation
test_export_alias_prefixes
test_export_unknown_prefix_fails
test_upstream_single_label_suffix
test_export_plain_yaml_artifact
test_classical_domain_fixture_outputs
test_batch_domain_dir_outputs
test_include_filter_semantics
test_suffix_compaction_keeps_attr_derivative
test_export_preserves_upstream_order_and_cn_regex_policy
test_attr_derivatives_merge_duplicate_rule_attrs
test_regional_base_lists_apply_safe_attribute_policy
test_publish_policy_prunes_geographic_children
test_export_materializes_attr_derivatives_with_sing_geosite_filter
test_ads_category_collapse
test_geographic_partition_folds_regional_attributes
test_domain_capability_summary
test_mihomo_mrs_skip_summary
test_classical_comments_preserve_hash_values
test_mihomo_domain_text_generation
test_domain_semantic_compile_cache

echo "domain parsing tests passed"
