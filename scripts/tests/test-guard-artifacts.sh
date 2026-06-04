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
mkdir -p "$TMP_DIR/files"
touch "$TMP_DIR/files/a.list" "$TMP_DIR/files/b.yaml" "$TMP_DIR/files/c.txt"
mkdir -p "$TMP_DIR/shape-ok" "$TMP_DIR/shape-bad"
touch \
  "$TMP_DIR/shape-ok/geolocation-cn.list" \
  "$TMP_DIR/shape-ok/category-games-!cn.list" \
  "$TMP_DIR/shape-ok/google@cn.list" \
  "$TMP_DIR/shape-ok/geolocation-!cn@cn.list"
touch \
  "$TMP_DIR/shape-bad/cn@cn.list" \
  "$TMP_DIR/shape-bad/geolocation-cn@cn.list" \
  "$TMP_DIR/shape-bad/category-ai-!cn@!cn.list"
mkdir -p "$TMP_DIR/ip-valid" "$TMP_DIR/ip-invalid"
cat > "$TMP_DIR/ip-valid/telegram.list" <<'RULES'
IP-CIDR,91.108.4.0/22,no-resolve
IP-CIDR6,2001:b28:f23c::/48,no-resolve
RULES
cat > "$TMP_DIR/ip-valid/private.list" <<'RULES'
IP-CIDR,10.0.0.0/8,no-resolve
IP-CIDR6,fc00::/7,no-resolve
RULES
cat > "$TMP_DIR/ip-invalid/example.list" <<'RULES'
IP-CIDR,10.0.0.0/8,no-resolve
IP-CIDR6,192.0.2.0/24,no-resolve
RULES

assert_equals "7" "$(count_domain_rules_from_file "$TMP_DIR/domain.list")" "domain list counts Surge and QuanX domain entries"
assert_equals "2" "$(count_domain_rules_from_file "$TMP_DIR/domain.yaml")" "domain yaml counts Egern entries"
assert_equals "1" "$(count_matching_files "$TMP_DIR/files" "*.list")" "count_matching_files filters by extension"
assert_equals "0" "$(count_matching_files "$TMP_DIR/missing" "*.list")" "count_matching_files handles missing directories"
assert_equals "10" "$MIN_IP_CIDR_GOOGLE_V6" "google IPv6 guard default allows normal mid-teen payloads"

if is_redundant_attr_filter_artifact_name "google@cn"; then
  echo "test failed: google@cn should remain an allowed attr artifact" >&2
  exit 1
fi

if is_redundant_attr_filter_artifact_name "geolocation-!cn@cn"; then
  echo "test failed: geolocation-!cn@cn should remain an allowed attr artifact" >&2
  exit 1
fi

if is_redundant_attr_filter_artifact_name "geolocation-cn"; then
  echo "test failed: geolocation-cn should remain an allowed upstream list name" >&2
  exit 1
fi

if is_redundant_attr_filter_artifact_name "foo@bar@bar"; then
  echo "test failed: names with multiple @ separators should not match attr artifact shape" >&2
  exit 1
fi

if ! is_redundant_attr_filter_artifact_name "cn@cn"; then
  echo "test failed: cn@cn should be classified as a redundant attr artifact" >&2
  exit 1
fi

if ! is_redundant_attr_filter_artifact_name "geolocation-cn@cn"; then
  echo "test failed: geolocation-cn@cn should be classified as a redundant attr artifact" >&2
  exit 1
fi

if ! is_redundant_attr_filter_artifact_name "category-ai-!cn@!cn"; then
  echo "test failed: category-ai-!cn@!cn should be classified as a redundant attr artifact" >&2
  exit 1
fi

check_no_redundant_attr_filter_artifacts_in_dir "$TMP_DIR/shape-ok" "shape-ok" >/dev/null

if ( check_no_redundant_attr_filter_artifacts_in_dir "$TMP_DIR/shape-bad" "shape-bad" ) >"$TMP_DIR/shape-bad.stdout" 2>"$TMP_DIR/shape-bad.stderr"; then
  echo "test failed: redundant attr filter artifacts should fail guard" >&2
  exit 1
fi

if ! grep -Fq "shape-bad redundant attr filter artifact should not be published: geolocation-cn@cn.list" "$TMP_DIR/shape-bad.stderr"; then
  echo "test failed: missing redundant attr artifact guard message" >&2
  cat "$TMP_DIR/shape-bad.stderr" >&2
  exit 1
fi

mkdir -p "$TMP_DIR/plain-summary/.output"
cat > "$TMP_DIR/plain-summary/.output/upstream-summary.json" <<'JSON'
[
  {
    "category": "domain",
    "name": "dlc",
    "raw": {"path": "/tmp/dlc.dat_plain.yml"},
    "url": "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat_plain.yml"
  }
]
JSON

if ! ( cd "$TMP_DIR/plain-summary" && uses_dlc_plain_yaml_artifact ); then
  echo "test failed: DLC plain YAML summary should be detected" >&2
  exit 1
fi

mkdir -p "$TMP_DIR/git-summary/.output"
cat > "$TMP_DIR/git-summary/.output/upstream-summary.json" <<'JSON'
[
  {
    "category": "domain",
    "name": "dlc",
    "url": "https://github.com/v2fly/domain-list-community.git"
  }
]
JSON

if ( cd "$TMP_DIR/git-summary" && uses_dlc_plain_yaml_artifact ); then
  echo "test failed: git DLC summary should not be treated as plain YAML" >&2
  exit 1
fi

check_public_ip_cidrs_in_dir "$TMP_DIR/ip-valid" "ip-valid"

if ( check_public_ip_cidrs_in_dir "$TMP_DIR/ip-invalid" "ip-invalid" ) >"$TMP_DIR/ip-invalid.stdout" 2>"$TMP_DIR/ip-invalid.stderr"; then
  echo "test failed: invalid public IP artifacts should fail guard" >&2
  exit 1
fi

if ! grep -Fq "non-global CIDR outside private.list: 10.0.0.0/8" "$TMP_DIR/ip-invalid.stderr"; then
  echo "test failed: missing non-global CIDR guard message" >&2
  cat "$TMP_DIR/ip-invalid.stderr" >&2
  exit 1
fi

if ! grep -Fq "IP-CIDR6 requires IPv6, got 192.0.2.0/24" "$TMP_DIR/ip-invalid.stderr"; then
  echo "test failed: missing IP family guard message" >&2
  cat "$TMP_DIR/ip-invalid.stderr" >&2
  exit 1
fi

if ip_entry_growth_exceeds_limit 31 221; then
  echo "test failed: small absolute IP growth should not trip percentage guard" >&2
  exit 1
fi

if ! ip_entry_growth_exceeds_limit 51 221; then
  echo "test failed: large IP growth should trip percentage guard" >&2
  exit 1
fi

echo "guard artifact tests passed"
