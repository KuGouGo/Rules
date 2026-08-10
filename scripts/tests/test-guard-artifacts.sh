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

mkdir -p "$TMP_DIR/files"
touch "$TMP_DIR/files/a.list" "$TMP_DIR/files/b.yaml" "$TMP_DIR/files/c.txt"
mkdir -p "$TMP_DIR/shape-ok" "$TMP_DIR/shape-bad"
touch \
  "$TMP_DIR/shape-ok/geolocation-cn.list" \
  "$TMP_DIR/shape-ok/category-games-!cn.list" \
  "$TMP_DIR/shape-ok/google@cn.list" \
  "$TMP_DIR/shape-ok/geolocation-!cn@cn.list" \
  "$TMP_DIR/shape-ok/geolocation-cn@!cn.list" \
  "$TMP_DIR/shape-ok/tracking-ads@ads.list"
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

assert_equals "1" "$(count_matching_files "$TMP_DIR/files" "*.list")" "count_matching_files filters by extension"
assert_equals "0" "$(count_matching_files "$TMP_DIR/missing" "*.list")" "count_matching_files handles missing directories"
assert_equals "10" "$MIN_IP_CIDR_GOOGLE_V6" "google IPv6 guard default allows normal mid-teen payloads"
assert_equals "40" "$MIN_DOMAIN_ARTIFACT_FILES" "domain artifact minimum matches curated publication policy"
assert_equals "90" "$MAX_DOMAIN_ARTIFACT_FILES" "domain artifact maximum prevents publication growth"
extended_range="$(DOMAIN_PUBLISH_PROFILE=extended bash -c '
  source scripts/commands/guard-artifacts.sh
  printf "%s %s" "$MIN_DOMAIN_ARTIFACT_FILES" "$MAX_DOMAIN_ARTIFACT_FILES"
')"
assert_equals "150 250" "$extended_range" "extended profile uses its own artifact range"

mkdir -p "$TMP_DIR/range-ok" "$TMP_DIR/range-too-large"
touch "$TMP_DIR/range-ok/a.list" "$TMP_DIR/range-ok/b.list"
touch "$TMP_DIR/range-too-large/a.list" "$TMP_DIR/range-too-large/b.list" "$TMP_DIR/range-too-large/c.list"
check_max_files "range-ok" "$TMP_DIR/range-ok/*.list" 2 >/dev/null
if ( check_max_files "range-too-large" "$TMP_DIR/range-too-large/*.list" 2 ) >/dev/null 2>&1; then
  echo "test failed: maximum artifact count must reject oversized output" >&2
  exit 1
fi

mkdir -p "$TMP_DIR/large-matching" "$TMP_DIR/large-nonmatching"
python3 - <<'PY' "$TMP_DIR/large-matching" "$TMP_DIR/large-nonmatching"
import sys
from pathlib import Path

for directory, suffix in ((Path(sys.argv[1]), ".list"), (Path(sys.argv[2]), ".txt")):
    for index in range(2000):
        (directory / f"{index:04d}-{'x' * 80}{suffix}").touch()
PY
large_matching_summary="$(summarize_artifact_dir "large-matching" "$TMP_DIR/large-matching" "*.list")"
large_nonmatching_summary="$(summarize_artifact_dir "large-nonmatching" "$TMP_DIR/large-nonmatching" "*.list")"
assert_equals "$SUMMARY_LIMIT" "$(grep -Fc "$TMP_DIR/large-matching/" <<< "$large_matching_summary")" "large matching summary stays limited under pipefail"
assert_equals "$SUMMARY_LIMIT" "$(grep -Fc "$TMP_DIR/large-nonmatching/" <<< "$large_nonmatching_summary")" "large non-matching summary stays limited under pipefail"

if is_redundant_attr_filter_artifact_name "google@cn"; then
  echo "test failed: google@cn should remain an allowed attr artifact" >&2
  exit 1
fi

if is_redundant_attr_filter_artifact_name "geolocation-!cn@cn"; then
  echo "test failed: geolocation-!cn@cn should remain an allowed attr artifact" >&2
  exit 1
fi

if is_redundant_attr_filter_artifact_name "geolocation-cn@!cn"; then
  echo "test failed: geolocation-cn@!cn should remain an allowed attr artifact" >&2
  exit 1
fi

if is_redundant_attr_filter_artifact_name "tracking-ads@ads"; then
  echo "test failed: tracking-ads@ads should remain an allowed attr artifact" >&2
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

echo "guard artifact tests passed"
