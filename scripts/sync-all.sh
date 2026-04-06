#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

WORK_TMP_DIR="$ROOT_DIR/.tmp/sync"
BIN_DIR="$ROOT_DIR/.bin"
DOMAIN_BUILD_TMP_DIR="$WORK_TMP_DIR/domain-build"
IP_BUILD_TMP_DIR="$WORK_TMP_DIR/ip-build"
ARTIFACTS_DIR="$ROOT_DIR/.output"
DOMAIN_ARTIFACTS_DIR="$ARTIFACTS_DIR/domain"
IP_ARTIFACTS_DIR="$ARTIFACTS_DIR/ip"

DOMAIN_SOURCE_REPO_URL="https://github.com/v2fly/domain-list-community.git"
CN_IPV4_SOURCE_URL="https://ispip.clang.cn/all_cn.txt"
CN_IPV6_SOURCE_URL="https://ispip.clang.cn/all_cn_ipv6.txt"
GOOGLE_IP_SOURCE_URL="https://www.gstatic.com/ipranges/goog.json"
TELEGRAM_IP_SOURCE_URL="https://core.telegram.org/resources/cidr.txt"
CLOUDFLARE_IPV4_SOURCE_URL="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPV6_SOURCE_URL="https://www.cloudflare.com/ips-v6"
CLOUDFRONT_IP_SOURCE_URL="https://ip-ranges.amazonaws.com/ip-ranges.json"
FASTLY_IP_SOURCE_URL="https://api.fastly.com/public-ip-list"
APPLE_IP_SOURCE_URL="https://support.apple.com/en-us/101555"

source "$ROOT_DIR/scripts/lib/common.sh"
source "$ROOT_DIR/scripts/lib/rules.sh"

rm -rf "$WORK_TMP_DIR"
mkdir -p "$WORK_TMP_DIR" "$BIN_DIR" "$DOMAIN_BUILD_TMP_DIR" "$IP_BUILD_TMP_DIR"
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
  awk 'NF && !seen[$0]++' "$@" > "$output_file"
}

# Domain rules from domain-list-community/data
rm -rf "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/mihomo"
clone_repository_shallow "$DOMAIN_SOURCE_REPO_URL" "$WORK_TMP_DIR/domain-list-community"
python3 "$ROOT_DIR/scripts/export-domain-list-community.py" export \
  "$WORK_TMP_DIR/domain-list-community/data" \
  "$DOMAIN_ARTIFACTS_DIR/surge"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/surge/*.list"

# Domain sing-box and mihomo built locally from the same classical domain lists
build_domain_artifacts_from_rule_dir \
  "$DOMAIN_ARTIFACTS_DIR/surge" \
  "$DOMAIN_BUILD_TMP_DIR" \
  "$DOMAIN_ARTIFACTS_DIR/sing-box" \
  "$DOMAIN_ARTIFACTS_DIR/mihomo"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/sing-box/*.srs"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/mihomo" "$DOMAIN_ARTIFACTS_DIR/mihomo/*.mrs"

# IP rules from curated remote sources
rm -rf "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/mihomo"
mkdir -p "$IP_ARTIFACTS_DIR/surge"

download_file "$CN_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv4.raw.txt"
download_file "$CN_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv6.raw.txt"
download_file "$GOOGLE_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/google.raw.json"
download_file "$TELEGRAM_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/telegram.raw.txt"
download_file "$CLOUDFLARE_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv4.raw.txt"
download_file "$CLOUDFLARE_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv6.raw.txt"
download_file "$CLOUDFRONT_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudfront.raw.json"
download_file "$FASTLY_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/fastly.raw.json"
download_file "$APPLE_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/apple.raw.html"

python3 "$ROOT_DIR/scripts/normalize-ip-source.py" text \
  "$IP_BUILD_TMP_DIR/cn_ipv4.raw.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv4.cidr.txt"
python3 "$ROOT_DIR/scripts/normalize-ip-source.py" text \
  "$IP_BUILD_TMP_DIR/cn_ipv6.raw.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv6.cidr.txt"
merge_cidr_plain_files \
  "$IP_BUILD_TMP_DIR/cn.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv6.cidr.txt"

python3 "$ROOT_DIR/scripts/normalize-ip-source.py" google-json \
  "$IP_BUILD_TMP_DIR/google.raw.json" \
  "$IP_BUILD_TMP_DIR/google.cidr.txt"
python3 "$ROOT_DIR/scripts/normalize-ip-source.py" text \
  "$IP_BUILD_TMP_DIR/telegram.raw.txt" \
  "$IP_BUILD_TMP_DIR/telegram.cidr.txt"
python3 "$ROOT_DIR/scripts/normalize-ip-source.py" text \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv4.raw.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv4.cidr.txt"
python3 "$ROOT_DIR/scripts/normalize-ip-source.py" text \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv6.raw.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv6.cidr.txt"
merge_cidr_plain_files \
  "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv6.cidr.txt"
python3 "$ROOT_DIR/scripts/normalize-ip-source.py" aws-cloudfront-json \
  "$IP_BUILD_TMP_DIR/cloudfront.raw.json" \
  "$IP_BUILD_TMP_DIR/cloudfront.cidr.txt"
python3 "$ROOT_DIR/scripts/normalize-ip-source.py" fastly-json \
  "$IP_BUILD_TMP_DIR/fastly.raw.json" \
  "$IP_BUILD_TMP_DIR/fastly.cidr.txt"
python3 "$ROOT_DIR/scripts/normalize-ip-source.py" html \
  "$IP_BUILD_TMP_DIR/apple.raw.html" \
  "$IP_BUILD_TMP_DIR/apple.cidr.txt"

render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cn.cidr.txt" "$IP_ARTIFACTS_DIR/surge/cn.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/google.cidr.txt" "$IP_ARTIFACTS_DIR/surge/google.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/telegram.cidr.txt" "$IP_ARTIFACTS_DIR/surge/telegram.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" "$IP_ARTIFACTS_DIR/surge/cloudflare.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cloudfront.cidr.txt" "$IP_ARTIFACTS_DIR/surge/cloudfront.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/fastly.cidr.txt" "$IP_ARTIFACTS_DIR/surge/fastly.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/apple.cidr.txt" "$IP_ARTIFACTS_DIR/surge/apple.list"

assert_files_present "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/surge/*.list"
build_ip_artifacts_from_surge_dir \
  "$IP_ARTIFACTS_DIR/surge" \
  "$IP_BUILD_TMP_DIR" \
  "$IP_ARTIFACTS_DIR/sing-box" \
  "$IP_ARTIFACTS_DIR/mihomo"
assert_files_present "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/sing-box/*.srs"
assert_files_present "$IP_ARTIFACTS_DIR/mihomo" "$IP_ARTIFACTS_DIR/mihomo/*.mrs"

echo "=== SYNC DONE ==="
