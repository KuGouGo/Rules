#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

WORK_TMP_DIR="$ROOT_DIR/.tmp/sync"
BIN_DIR="$ROOT_DIR/.bin"
DOMAIN_BUILD_TMP_DIR="$WORK_TMP_DIR/domain-build"
DOMAIN_RULE_TMP_DIR="$WORK_TMP_DIR/domain-rules"
IP_BUILD_TMP_DIR="$WORK_TMP_DIR/ip-build"
ARTIFACTS_DIR="$ROOT_DIR/.output"
DOMAIN_ARTIFACTS_DIR="$ARTIFACTS_DIR/domain"
IP_ARTIFACTS_DIR="$ARTIFACTS_DIR/ip"

DOMAIN_SOURCE_REPO_URL="https://github.com/v2fly/domain-list-community.git"
AWAVENUE_DOMAIN_SOURCE_URL="https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Surge-RULE-SET.list"
AWAVENUE_DOMAIN_SOURCE_FALLBACK_URL="https://gcore.jsdelivr.net/gh/TG-Twilight/AWAvenue-Ads-Rule@main/Filters/AWAvenue-Ads-Rule-Surge-RULE-SET.list"
CN_IPV4_SOURCE_URL="https://ispip.clang.cn/all_cn.txt"
CN_IPV6_SOURCE_URL="https://ispip.clang.cn/all_cn_ipv6.txt"
CN_ASN_IPV4_SOURCE_URL="https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"
CN_ASN_IPV6_SOURCE_URL="https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt"
GOOGLE_IP_SOURCE_URL="https://www.gstatic.com/ipranges/goog.json"
TELEGRAM_IP_SOURCE_URL="https://core.telegram.org/resources/cidr.txt"
CLOUDFLARE_IPV4_SOURCE_URL="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPV6_SOURCE_URL="https://www.cloudflare.com/ips-v6"
# One download used for both CloudFront (service-filtered) and AWS (all services).
AWS_IP_SOURCE_URL="https://ip-ranges.amazonaws.com/ip-ranges.json"
FASTLY_IP_SOURCE_URL="https://api.fastly.com/public-ip-list"
GITHUB_IP_SOURCE_URL="https://api.github.com/meta"
APPLE_IP_SOURCE_URL="https://support.apple.com/en-us/101555"
APPLE_IP_SOURCE_FALLBACK_URL="https://support.apple.com/zh-cn/101555"

APPLE_MIN_CIDR_COUNT="${APPLE_MIN_CIDR_COUNT:-3}"
AWAVENUE_MIN_RULE_COUNT="${AWAVENUE_MIN_RULE_COUNT:-500}"

# RIPE NCC Stat API: official RPKI/routing data for ASN prefix lookups.
# Used for streaming services that publish no machine-readable CIDR lists.
RIPE_STAT_BASE_URL="https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS"

# Netflix: AS2906 (Netflix Streaming), AS40027 (Netflix CDN LLC)
NETFLIX_ASNS=(2906 40027)
# Spotify: AS35228, AS7441
SPOTIFY_ASNS=(35228 7441)
# Disney+ / BAMTech: AS133530, AS394297
DISNEY_ASNS=(133530 394297)

source "$ROOT_DIR/scripts/lib/common.sh"
source "$ROOT_DIR/scripts/lib/rules.sh"

rm -rf "$WORK_TMP_DIR"
mkdir -p "$WORK_TMP_DIR" "$BIN_DIR" "$DOMAIN_BUILD_TMP_DIR" "$DOMAIN_RULE_TMP_DIR" "$IP_BUILD_TMP_DIR"
trap 'rm -rf "$WORK_TMP_DIR"' EXIT

mkdir -p "$DOMAIN_ARTIFACTS_DIR" "$IP_ARTIFACTS_DIR"

echo "=== SYNC START ==="

clone_repository_shallow() {
  local repo_url="$1"
  local dest="$2"
  git clone --depth=1 --single-branch "$repo_url" "$dest"
}

assert_files_present() {
  local label="$1"
  local glob="$2"
  if ! compgen -G "$glob" >/dev/null; then
    echo "$label is empty: $glob" >&2
    exit 1
  fi
}

merge_cidr_plain_files() {
  local output_file="$1"
  shift
  # Filter blank/comment lines while deduplicating.
  awk '!/^[[:space:]]*$/ && !/^[[:space:]]*#/ && !seen[$0]++' "$@" > "$output_file"
}

# sync_asn_ip_list <name> <asn> [<asn> ...]
# Download RIPE NCC Stat prefix data for each ASN, normalise in one batch,
# merge, and render to a Surge list at IP_ARTIFACTS_DIR/surge/<name>.list.
sync_asn_ip_list() {
  local name="$1"
  shift
  local -a asns=("$@")
  local -a cidr_files=()
  local -a task_args=()
  local asn raw_json cidr_txt manifest_file

  for asn in "${asns[@]}"; do
    raw_json="$IP_BUILD_TMP_DIR/${name}_as${asn}.raw.json"
    cidr_txt="$IP_BUILD_TMP_DIR/${name}_as${asn}.cidr.txt"
    download_file "${RIPE_STAT_BASE_URL}${asn}" "$raw_json"
    cidr_files+=("$cidr_txt")
    task_args+=(
      "ripe-stat-json"
      "$raw_json"
      "$cidr_txt"
    )
  done

  manifest_file="$IP_BUILD_TMP_DIR/${name}.asn-normalize-tasks.json"
  generate_normalize_manifest "$manifest_file" "${task_args[@]}"
  python3 "$ROOT_DIR/scripts/normalize-ip-source.py" batch "$manifest_file"

  merge_cidr_plain_files "$IP_BUILD_TMP_DIR/${name}.cidr.txt" "${cidr_files[@]}"

  if [ ! -s "$IP_BUILD_TMP_DIR/${name}.cidr.txt" ]; then
    echo "warning: no prefixes found for $name (ASNs: ${asns[*]}), skipping" >&2
    return 0
  fi

  render_ip_plain_to_surge_list \
    "$IP_BUILD_TMP_DIR/${name}.cidr.txt" \
    "$IP_ARTIFACTS_DIR/surge/${name}.list"
  render_ip_plain_to_quanx_list \
    "$IP_BUILD_TMP_DIR/${name}.cidr.txt" \
    "$IP_ARTIFACTS_DIR/quanx/${name}.list" \
    "$name"
}

generate_normalize_manifest() {
  local manifest_file="$1"
  shift

  python3 - <<'PY' "$manifest_file" "$@"
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
args = sys.argv[2:]

if len(args) % 3 != 0:
    raise SystemExit("normalize manifest generator expects triplets: source_type input_file output_file")

tasks = []
for i in range(0, len(args), 3):
    tasks.append({
        "source_type": args[i],
        "input_file": args[i + 1],
        "output_file": args[i + 2],
    })

manifest_path.write_text(json.dumps(tasks, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

generate_ip_normalize_manifest() {
  local manifest_file="$1"
  local tmp_dir="$IP_BUILD_TMP_DIR"

  generate_normalize_manifest "$manifest_file" \
    text "$tmp_dir/cn_ipv4.raw.txt" "$tmp_dir/cn_ipv4.cidr.txt" \
    text "$tmp_dir/cn_ipv6.raw.txt" "$tmp_dir/cn_ipv6.cidr.txt" \
    text "$tmp_dir/cn_asn_ipv4.raw.txt" "$tmp_dir/cn_asn_ipv4.cidr.txt" \
    text "$tmp_dir/cn_asn_ipv6.raw.txt" "$tmp_dir/cn_asn_ipv6.cidr.txt" \
    google-json "$tmp_dir/google.raw.json" "$tmp_dir/google.cidr.txt" \
    text "$tmp_dir/telegram.raw.txt" "$tmp_dir/telegram.cidr.txt" \
    text "$tmp_dir/cloudflare_ipv4.raw.txt" "$tmp_dir/cloudflare_ipv4.cidr.txt" \
    text "$tmp_dir/cloudflare_ipv6.raw.txt" "$tmp_dir/cloudflare_ipv6.cidr.txt" \
    aws-cloudfront-json "$tmp_dir/aws.raw.json" "$tmp_dir/cloudfront.cidr.txt" \
    aws-json "$tmp_dir/aws.raw.json" "$tmp_dir/aws.cidr.txt" \
    fastly-json "$tmp_dir/fastly.raw.json" "$tmp_dir/fastly.cidr.txt" \
    github-json "$tmp_dir/github.raw.json" "$tmp_dir/github.cidr.txt" \
    html "$tmp_dir/apple.raw.html" "$tmp_dir/apple.cidr.txt"
}

download_file_with_fallback() {
  local out_file="$1"
  shift
  local url
  local attempted=""

  for url in "$@"; do
    if download_file "$url" "$out_file"; then
      echo "downloaded $(basename "$out_file") from $url"
      return 0
    fi

    attempted="${attempted}${attempted:+, }$url"
    echo "download failed from $url, trying next fallback..." >&2
  done

  echo "failed to download $(basename "$out_file") from all sources: $attempted" >&2
  return 1
}

assert_min_cidrs() {
  local label="$1"
  local file="$2"
  local min_expected="$3"
  local count

  count=$(wc -l < "$file" | tr -d ' ')
  echo "$label cidr entries: $count (min expected: $min_expected)"

  if [ "$count" -lt "$min_expected" ]; then
    echo "$label cidr count too low: $count < $min_expected" >&2
    return 1
  fi
}

assert_min_rules() {
  local label="$1"
  local file="$2"
  local min_expected="$3"
  local count

  count=$(wc -l < "$file" | tr -d ' ')
  echo "$label rule entries: $count (min expected: $min_expected)"

  if [ "$count" -lt "$min_expected" ]; then
    echo "$label rule count too low: $count < $min_expected" >&2
    return 1
  fi
}

sync_remote_domain_ruleset() {
  local name="$1"
  local min_expected="$2"
  shift 2
  local raw_file normalized_file

  raw_file="$DOMAIN_BUILD_TMP_DIR/${name}.raw.list"
  normalized_file="$DOMAIN_RULE_TMP_DIR/${name}.list"

  download_file_with_fallback "$raw_file" "$@"
  normalize_custom_domain_source "$raw_file" "$normalized_file"

  if [ ! -s "$normalized_file" ]; then
    echo "normalized remote domain ruleset is empty: $name" >&2
    return 1
  fi

  assert_min_rules "$name" "$normalized_file" "$min_expected"
}

# Domain rules from domain-list-community/data plus curated remote lists
# The export script now automatically generates @cn filtered versions for all rule sets
rm -rf "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/mihomo"
clone_repository_shallow "$DOMAIN_SOURCE_REPO_URL" "$WORK_TMP_DIR/domain-list-community"
python3 "$ROOT_DIR/scripts/export-domain-rules.py" export \
  "$WORK_TMP_DIR/domain-list-community/data" \
  "$DOMAIN_RULE_TMP_DIR"
sync_remote_domain_ruleset \
  awavenue-ads \
  "$AWAVENUE_MIN_RULE_COUNT" \
  "$AWAVENUE_DOMAIN_SOURCE_URL" \
  "$AWAVENUE_DOMAIN_SOURCE_FALLBACK_URL"
assert_files_present "$DOMAIN_RULE_TMP_DIR" "$DOMAIN_RULE_TMP_DIR/*.list"
render_domain_rule_dir_to_surge_dir \
  "$DOMAIN_RULE_TMP_DIR" \
  "$DOMAIN_ARTIFACTS_DIR/surge" \
  "$DOMAIN_BUILD_TMP_DIR/surge"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/surge/*.list"
render_domain_rule_dir_to_quanx_dir \
  "$DOMAIN_RULE_TMP_DIR" \
  "$DOMAIN_ARTIFACTS_DIR/quanx" \
  "$DOMAIN_BUILD_TMP_DIR/quanx"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/quanx/*.list"
render_domain_rule_dir_to_egern_dir \
  "$DOMAIN_RULE_TMP_DIR" \
  "$DOMAIN_ARTIFACTS_DIR/egern" \
  "$DOMAIN_BUILD_TMP_DIR/egern"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/egern/*.yaml"

# Domain sing-box and mihomo built locally from the full classical domain lists
build_domain_artifacts_from_rule_dir \
  "$DOMAIN_RULE_TMP_DIR" \
  "$DOMAIN_BUILD_TMP_DIR" \
  "$DOMAIN_ARTIFACTS_DIR/sing-box" \
  "$DOMAIN_ARTIFACTS_DIR/mihomo"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/sing-box/*.srs"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/mihomo" "$DOMAIN_ARTIFACTS_DIR/mihomo/*.mrs"

# IP rules from curated remote sources
rm -rf "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/egern" "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/mihomo"
mkdir -p "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx"

download_file "$CN_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv4.raw.txt"
download_file "$CN_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv6.raw.txt"
download_file "$CN_ASN_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_asn_ipv4.raw.txt"
download_file "$CN_ASN_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_asn_ipv6.raw.txt"
download_file "$GOOGLE_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/google.raw.json"
download_file "$TELEGRAM_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/telegram.raw.txt"
download_file "$CLOUDFLARE_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv4.raw.txt"
download_file "$CLOUDFLARE_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv6.raw.txt"
# AWS JSON is shared between cloudfront (service-filtered) and aws (all services)
download_file "$AWS_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/aws.raw.json"
download_file "$FASTLY_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/fastly.raw.json"
download_file "$GITHUB_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/github.raw.json"
download_file_with_fallback \
  "$IP_BUILD_TMP_DIR/apple.raw.html" \
  "$APPLE_IP_SOURCE_URL" \
  "$APPLE_IP_SOURCE_FALLBACK_URL"

IP_NORMALIZE_MANIFEST="$IP_BUILD_TMP_DIR/normalize-tasks.json"

generate_ip_normalize_manifest "$IP_NORMALIZE_MANIFEST"
python3 "$ROOT_DIR/scripts/normalize-ip-source.py" batch "$IP_NORMALIZE_MANIFEST"
merge_cidr_plain_files \
  "$IP_BUILD_TMP_DIR/cn.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv6.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_asn_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_asn_ipv6.cidr.txt"
merge_cidr_plain_files \
  "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv6.cidr.txt"
assert_min_cidrs apple "$IP_BUILD_TMP_DIR/apple.cidr.txt" "$APPLE_MIN_CIDR_COUNT"

render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cn.cidr.txt"         "$IP_ARTIFACTS_DIR/surge/cn.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/google.cidr.txt"     "$IP_ARTIFACTS_DIR/surge/google.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/telegram.cidr.txt"   "$IP_ARTIFACTS_DIR/surge/telegram.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" "$IP_ARTIFACTS_DIR/surge/cloudflare.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cloudfront.cidr.txt" "$IP_ARTIFACTS_DIR/surge/cloudfront.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/aws.cidr.txt"        "$IP_ARTIFACTS_DIR/surge/aws.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/fastly.cidr.txt"     "$IP_ARTIFACTS_DIR/surge/fastly.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/github.cidr.txt"     "$IP_ARTIFACTS_DIR/surge/github.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/apple.cidr.txt"      "$IP_ARTIFACTS_DIR/surge/apple.list"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/cn.cidr.txt"         "$IP_ARTIFACTS_DIR/quanx/cn.list" "cn"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/google.cidr.txt"     "$IP_ARTIFACTS_DIR/quanx/google.list" "google"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/telegram.cidr.txt"   "$IP_ARTIFACTS_DIR/quanx/telegram.list" "telegram"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" "$IP_ARTIFACTS_DIR/quanx/cloudflare.list" "cloudflare"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/cloudfront.cidr.txt" "$IP_ARTIFACTS_DIR/quanx/cloudfront.list" "cloudfront"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/aws.cidr.txt"        "$IP_ARTIFACTS_DIR/quanx/aws.list" "aws"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/fastly.cidr.txt"     "$IP_ARTIFACTS_DIR/quanx/fastly.list" "fastly"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/github.cidr.txt"     "$IP_ARTIFACTS_DIR/quanx/github.list" "github"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/apple.cidr.txt"      "$IP_ARTIFACTS_DIR/quanx/apple.list" "apple"

# Streaming services: no official CIDR lists; use RIPE NCC Stat (RPKI data) by ASN.
sync_asn_ip_list netflix  "${NETFLIX_ASNS[@]}"
sync_asn_ip_list spotify  "${SPOTIFY_ASNS[@]}"
sync_asn_ip_list disney   "${DISNEY_ASNS[@]}"

assert_files_present "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/surge/*.list"
assert_files_present "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/quanx/*.list"
build_ip_artifacts_from_surge_dir \
  "$IP_ARTIFACTS_DIR/surge" \
  "$IP_BUILD_TMP_DIR" \
  "$IP_ARTIFACTS_DIR/sing-box" \
  "$IP_ARTIFACTS_DIR/mihomo"
build_ip_egern_artifacts_from_surge_dir \
  "$IP_ARTIFACTS_DIR/surge" \
  "$IP_BUILD_TMP_DIR" \
  "$IP_ARTIFACTS_DIR/egern"
assert_files_present "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/sing-box/*.srs"
assert_files_present "$IP_ARTIFACTS_DIR/mihomo" "$IP_ARTIFACTS_DIR/mihomo/*.mrs"
assert_files_present "$IP_ARTIFACTS_DIR/egern" "$IP_ARTIFACTS_DIR/egern/*.yaml"

echo "=== SYNC DONE ==="
