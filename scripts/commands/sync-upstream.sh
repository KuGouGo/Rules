#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/commands/check-runtime.sh"

WORK_TMP_DIR="$ROOT_DIR/.tmp/sync"
BIN_DIR="$ROOT_DIR/.bin"
DOMAIN_BUILD_TMP_DIR="$WORK_TMP_DIR/domain-build"
DOMAIN_RULE_TMP_DIR="$WORK_TMP_DIR/domain-rules"
IP_BUILD_TMP_DIR="$WORK_TMP_DIR/ip-build"
ARTIFACTS_DIR="${RULES_ARTIFACT_ROOT:-$ROOT_DIR/.output}"
DOMAIN_ARTIFACTS_DIR="$ARTIFACTS_DIR/domain"
IP_ARTIFACTS_DIR="$ARTIFACTS_DIR/ip"
CANONICAL_ARTIFACTS_DIR="$ARTIFACTS_DIR/.canonical"
DOMAIN_RULE_MANIFEST_FILE="$DOMAIN_ARTIFACTS_DIR/rule-manifest.json"

IP_TEXT_ARTIFACTS=(cn google telegram apple)

UPSTREAMS_CONFIG_FILE="$ROOT_DIR/config/upstreams.json"

declare -A UPSTREAM_SETTINGS=()
while IFS=$'\t' read -r key value; do
  UPSTREAM_SETTINGS["$key"]="$value"
done < <(python3 - "$UPSTREAMS_CONFIG_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

entries = {
    "domain.dlc.url": config["domain"]["dlc"]["url"],
    "domain.shellcrash-fakeip.url": config["domain"]["shellcrash-fakeip"]["url"],
    "ip.cn-ipv46-apnic.url": config["ip"]["cn-ipv46-apnic"]["url"],
    "ip.cn-17mon-ipv4.url": config["ip"]["cn-17mon-ipv4"]["url"],
    "ip.cn-clang-ipv4.url": config["ip"]["cn-clang-ipv4"]["url"],
    "ip.cn-clang-ipv6.url": config["ip"]["cn-clang-ipv6"]["url"],
    "ip.google.url": config["ip"]["google"]["url"],
    "ip.loyalsoldier-geoip-cn.url": config["ip"]["loyalsoldier-geoip-cn"]["url"],
    "ip.telegram.url": config["ip"]["telegram"]["url"],
    "ip.gaoyifan-cn-ipv4.url": config["ip"]["gaoyifan-cn-ipv4"]["url"],
    "ip.gaoyifan-cn-ipv6.url": config["ip"]["gaoyifan-cn-ipv6"]["url"],
    "ip.chnroutes-bgp-ipv4.url": config["ip"]["chnroutes-bgp-ipv4"]["url"],
    "ip.geoip-asn-ipv4.url": config["ip"]["geoip-asn-ipv4"]["url"],
    "ip.geoip-asn-ipv6.url": config["ip"]["geoip-asn-ipv6"]["url"],
}
for _group, _asns in config.get("asn_groups", {}).items():
    entries[f"asn.{_group}"] = " ".join(str(asn) for asn in _asns)
for key, value in entries.items():
    print(f"{key}\t{value}")
PY
)

DLC_MIN_AGGREGATE_CN_RULES="${DLC_MIN_AGGREGATE_CN_RULES:-500}"
DOMAIN_PUBLISH_POLICY="$ROOT_DIR/config/domain-publish-policy.json"
read -r -a TELEGRAM_ASNS <<< "${UPSTREAM_SETTINGS[asn.telegram]}"
read -r -a APPLE_ASNS <<< "${UPSTREAM_SETTINGS[asn.apple]:-}"
read -r -a GOOGLE_ASNS <<< "${UPSTREAM_SETTINGS[asn.google]:-}"

# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=scripts/lib/rules.sh
source "$ROOT_DIR/scripts/lib/rules.sh"
setup_tool_cache

rm -rf "$WORK_TMP_DIR"
mkdir -p "$WORK_TMP_DIR" "$BIN_DIR" "$DOMAIN_BUILD_TMP_DIR" "$DOMAIN_RULE_TMP_DIR" "$IP_BUILD_TMP_DIR"
trap 'rm -rf "$WORK_TMP_DIR"' EXIT

rm -rf "$CANONICAL_ARTIFACTS_DIR" "$DOMAIN_ARTIFACTS_DIR" "$IP_ARTIFACTS_DIR"
mkdir -p "$DOMAIN_ARTIFACTS_DIR" "$IP_ARTIFACTS_DIR" "$CANONICAL_ARTIFACTS_DIR"

check_upstream_health() {
  local category="$1"
  local name="$2"
  local raw_file="$3"
  local normalized_file="$4"

  if ! python3 "$ROOT_DIR/scripts/tools/verify-upstream-health.py" \
    "$UPSTREAMS_CONFIG_FILE" "$category" "$name" "$raw_file" "$normalized_file"; then
    echo "upstream $name failed health policy" >&2
    return 1
  fi
}

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
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" merge "$output_file" "$@"
}

render_ip_text_artifact() {
  local name="$1"
  local plain_file="$IP_BUILD_TMP_DIR/${name}.cidr.txt"

  render_ip_plain_to_surge_list \
    "$plain_file" \
    "$IP_ARTIFACTS_DIR/surge/${name}.list"
  render_ip_plain_to_quanx_list \
    "$plain_file" \
    "$IP_ARTIFACTS_DIR/quanx/${name}.list" \
    "$name"
  render_ip_plain_to_egern_yaml \
    "$plain_file" \
    "$IP_ARTIFACTS_DIR/egern/${name}.yaml"
}

render_ip_text_artifacts() {
  local name

  for name in "$@"; do
    render_ip_text_artifact "$name"
  done
}

extract_geoip_asn_group_cidrs() {
  local name="$1"
  shift
  local -a asns=("$@")
  local asn_filter v4_out v6_out asn_file

  asn_filter="$(IFS=,; echo "${asns[*]}")"
  v4_out="$IP_BUILD_TMP_DIR/${name}_geoipasn_v4.cidr.txt"
  v6_out="$IP_BUILD_TMP_DIR/${name}_geoipasn_v6.cidr.txt"

  if ! python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" asn-csv \
    "$IP_BUILD_TMP_DIR/geoip_asn_v4.raw.csv" "$v4_out" "$asn_filter"; then
    echo "GeoLite2-ASN IPv4 extraction failed for group $name" >&2
    return 1
  fi
  if ! python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" asn-csv \
    "$IP_BUILD_TMP_DIR/geoip_asn_v6.raw.csv" "$v6_out" "$asn_filter"; then
    echo "GeoLite2-ASN IPv6 extraction failed for group $name" >&2
    return 1
  fi

  asn_file="$IP_BUILD_TMP_DIR/${name}_asn.cidr.txt"
  if [ ! -s "$v4_out" ] && [ ! -s "$v6_out" ]; then
    echo "GeoLite2-ASN group $name produced no prefixes (ASNs: ${asns[*]})" >&2
    return 1
  fi
  merge_cidr_plain_files "$asn_file" "$v4_out" "$v6_out"
}

sync_merged_asn_ip_list() {
  local name="$1"
  shift
  local source_file="$IP_BUILD_TMP_DIR/${name}.cidr.txt"
  local asn_file="$IP_BUILD_TMP_DIR/${name}_asn.cidr.txt"
  local merged_file="$IP_BUILD_TMP_DIR/${name}_merged.cidr.txt"

  extract_geoip_asn_group_cidrs "$name" "$@"

  merge_cidr_plain_files "$merged_file" "$source_file" "$asn_file"
  mv "$merged_file" "$source_file"
  render_ip_text_artifact "$name"
}

sync_pure_asn_ip_list() {
  local name="$1"
  shift
  extract_geoip_asn_group_cidrs "$name" "$@"
  mv "$IP_BUILD_TMP_DIR/${name}_asn.cidr.txt" "$IP_BUILD_TMP_DIR/${name}.cidr.txt"
  render_ip_text_artifact "$name"
}

generate_ip_normalize_manifest() {
  local manifest_file="$1"
  local tmp_dir="$IP_BUILD_TMP_DIR"

  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" generate-manifest "$manifest_file" \
    text "$tmp_dir/cn_ipv46_apnic.raw.txt" "$tmp_dir/cn_ipv46_apnic.cidr.txt" \
    text "$tmp_dir/cn_clang_ipv4.raw.txt" "$tmp_dir/cn_clang_ipv4.cidr.txt" \
    text "$tmp_dir/cn_clang_ipv6.raw.txt" "$tmp_dir/cn_clang_ipv6.cidr.txt" \
    text "$tmp_dir/cn_17mon_ipv4.raw.txt" "$tmp_dir/cn_17mon_ipv4.cidr.txt" \
    text "$tmp_dir/gaoyifan_cn_ipv4.raw.txt" "$tmp_dir/gaoyifan_cn_ipv4.cidr.txt" \
    text "$tmp_dir/gaoyifan_cn_ipv6.raw.txt" "$tmp_dir/gaoyifan_cn_ipv6.cidr.txt" \
    text "$tmp_dir/chnroutes_bgp_ipv4.raw.txt" "$tmp_dir/chnroutes_bgp_ipv4.cidr.txt" \
    text "$tmp_dir/loyalsoldier-geoip-cn.raw.txt" "$tmp_dir/loyalsoldier-geoip-cn.cidr.txt"
}

normalize_first_batch_source() {
  local source="$1"
  local raw_file="$IP_BUILD_TMP_DIR/${source}.raw"
  local output_file="$IP_BUILD_TMP_DIR/${source}.cidr.txt"
  local source_type

  case "$source" in
    google) raw_file="$IP_BUILD_TMP_DIR/google.raw.json"; source_type="google-json" ;;
    telegram) raw_file="$IP_BUILD_TMP_DIR/telegram.raw.txt"; source_type="text" ;;
    *) echo "unsupported first-batch source: $source" >&2; return 1 ;;
  esac

  if [ ! -s "$raw_file" ]; then
    echo "required first-batch source $source missing or empty: $raw_file" >&2
    return 1
  fi
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" single "$source_type" "$raw_file" "$output_file"
}

main() {
  echo "=== SYNC START ==="

  mkdir -p "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/egern"
  clone_repository_shallow "${UPSTREAM_SETTINGS[domain.dlc.url]}" "$WORK_TMP_DIR/domain-list-community"

  python3 "$ROOT_DIR/scripts/tools/audit-dlc-data.py" "$WORK_TMP_DIR/domain-list-community/data"
  python3 "$ROOT_DIR/scripts/tools/export-domain-rules.py" export \
    "$WORK_TMP_DIR/domain-list-community/data" \
    "$DOMAIN_RULE_TMP_DIR" \
    --publish-policy "$DOMAIN_PUBLISH_POLICY"

  check_upstream_health \
    domain \
    dlc \
    "$WORK_TMP_DIR/domain-list-community/data" \
    "$DOMAIN_RULE_TMP_DIR"

  download_files_parallel \
    shellcrash-fakeip required "${UPSTREAM_SETTINGS[domain.shellcrash-fakeip.url]}" "$WORK_TMP_DIR/shellcrash-fakeip.raw.list"

  : > "$DOMAIN_RULE_TMP_DIR/fakeip-filter.list"
  python3 "$ROOT_DIR/scripts/tools/merge-domain-rule-source.py" \
    "$WORK_TMP_DIR/shellcrash-fakeip.raw.list" \
    "$DOMAIN_RULE_TMP_DIR/fakeip-filter.list" \
    "$WORK_TMP_DIR/shellcrash-fakeip.normalized.list"
  check_upstream_health \
    domain shellcrash-fakeip \
    "$WORK_TMP_DIR/shellcrash-fakeip.raw.list" \
    "$WORK_TMP_DIR/shellcrash-fakeip.normalized.list"

  python3 "$ROOT_DIR/scripts/tools/export-domain-rules.py" domain-rule-manifest \
    "$DOMAIN_RULE_TMP_DIR" \
    "$DOMAIN_RULE_MANIFEST_FILE"
  stage_domain_canonical_rules \
    "$DOMAIN_RULE_TMP_DIR" \
    "$CANONICAL_ARTIFACTS_DIR/domain"
  python3 "$ROOT_DIR/scripts/tools/verify-domain-derivatives.py" \
    "$DOMAIN_RULE_MANIFEST_FILE" \
    "$DLC_MIN_AGGREGATE_CN_RULES"
  assert_files_present "$DOMAIN_RULE_TMP_DIR" "$DOMAIN_RULE_TMP_DIR/*.list"
  render_domain_rule_dir_to_text_platform_dirs \
    "$DOMAIN_RULE_TMP_DIR" \
    "$DOMAIN_ARTIFACTS_DIR/surge" \
    "$DOMAIN_ARTIFACTS_DIR/quanx" \
    "$DOMAIN_ARTIFACTS_DIR/egern"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/surge/*.list"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/quanx/*.list"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/egern/*.yaml"

  build_domain_artifacts_from_rule_dir \
    "$DOMAIN_RULE_TMP_DIR" \
    "$DOMAIN_BUILD_TMP_DIR/domain-compile" \
    "$DOMAIN_ARTIFACTS_DIR/sing-box" \
    "$DOMAIN_ARTIFACTS_DIR/mihomo"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/sing-box/*.srs"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/mihomo" "$DOMAIN_ARTIFACTS_DIR/mihomo/*.mrs"

  download_files_parallel \
    cn-ipv46-apnic required "${UPSTREAM_SETTINGS[ip.cn-ipv46-apnic.url]}" "$IP_BUILD_TMP_DIR/cn_ipv46_apnic.raw.txt" \
    cn-clang-ipv4 required "${UPSTREAM_SETTINGS[ip.cn-clang-ipv4.url]}" "$IP_BUILD_TMP_DIR/cn_clang_ipv4.raw.txt" \
    cn-clang-ipv6 required "${UPSTREAM_SETTINGS[ip.cn-clang-ipv6.url]}" "$IP_BUILD_TMP_DIR/cn_clang_ipv6.raw.txt" \
    cn-17mon-ipv4 required "${UPSTREAM_SETTINGS[ip.cn-17mon-ipv4.url]}" "$IP_BUILD_TMP_DIR/cn_17mon_ipv4.raw.txt" \
    gaoyifan-cn-ipv4 required "${UPSTREAM_SETTINGS[ip.gaoyifan-cn-ipv4.url]}" "$IP_BUILD_TMP_DIR/gaoyifan_cn_ipv4.raw.txt" \
    gaoyifan-cn-ipv6 required "${UPSTREAM_SETTINGS[ip.gaoyifan-cn-ipv6.url]}" "$IP_BUILD_TMP_DIR/gaoyifan_cn_ipv6.raw.txt" \
    chnroutes-bgp-ipv4 required "${UPSTREAM_SETTINGS[ip.chnroutes-bgp-ipv4.url]}" "$IP_BUILD_TMP_DIR/chnroutes_bgp_ipv4.raw.txt" \
    loyalsoldier-geoip-cn required "${UPSTREAM_SETTINGS[ip.loyalsoldier-geoip-cn.url]}" "$IP_BUILD_TMP_DIR/loyalsoldier-geoip-cn.raw.txt" \
    geoip-asn-ipv4 required "${UPSTREAM_SETTINGS[ip.geoip-asn-ipv4.url]}" "$IP_BUILD_TMP_DIR/geoip_asn_v4.raw.csv" \
    geoip-asn-ipv6 required "${UPSTREAM_SETTINGS[ip.geoip-asn-ipv6.url]}" "$IP_BUILD_TMP_DIR/geoip_asn_v6.raw.csv" \
    google classified "${UPSTREAM_SETTINGS[ip.google.url]}" "$IP_BUILD_TMP_DIR/google.raw.json" \
    telegram classified "${UPSTREAM_SETTINGS[ip.telegram.url]}" "$IP_BUILD_TMP_DIR/telegram.raw.txt"

  IP_NORMALIZE_MANIFEST="$IP_BUILD_TMP_DIR/normalize-tasks.json"
  generate_ip_normalize_manifest "$IP_NORMALIZE_MANIFEST"
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" batch "$IP_NORMALIZE_MANIFEST"
  normalize_first_batch_source "google"
  normalize_first_batch_source "telegram"
  while IFS='|' read -r health_name health_raw health_normalized; do
    check_upstream_health ip "$health_name" "$IP_BUILD_TMP_DIR/$health_raw" "$IP_BUILD_TMP_DIR/$health_normalized"
  done <<EOF
cn-ipv46-apnic|cn_ipv46_apnic.raw.txt|cn_ipv46_apnic.cidr.txt
cn-clang-ipv4|cn_clang_ipv4.raw.txt|cn_clang_ipv4.cidr.txt
cn-clang-ipv6|cn_clang_ipv6.raw.txt|cn_clang_ipv6.cidr.txt
cn-17mon-ipv4|cn_17mon_ipv4.raw.txt|cn_17mon_ipv4.cidr.txt
gaoyifan-cn-ipv4|gaoyifan_cn_ipv4.raw.txt|gaoyifan_cn_ipv4.cidr.txt
gaoyifan-cn-ipv6|gaoyifan_cn_ipv6.raw.txt|gaoyifan_cn_ipv6.cidr.txt
chnroutes-bgp-ipv4|chnroutes_bgp_ipv4.raw.txt|chnroutes_bgp_ipv4.cidr.txt
loyalsoldier-geoip-cn|loyalsoldier-geoip-cn.raw.txt|loyalsoldier-geoip-cn.cidr.txt
google|google.raw.json|google.cidr.txt
telegram|telegram.raw.txt|telegram.cidr.txt
EOF

  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" merge \
    "$IP_BUILD_TMP_DIR/cn.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cn_ipv46_apnic.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cn_clang_ipv4.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cn_clang_ipv6.cidr.txt" \
    "$IP_BUILD_TMP_DIR/gaoyifan_cn_ipv4.cidr.txt" \
    "$IP_BUILD_TMP_DIR/gaoyifan_cn_ipv6.cidr.txt" \
    "$IP_BUILD_TMP_DIR/chnroutes_bgp_ipv4.cidr.txt" \
    "$IP_BUILD_TMP_DIR/loyalsoldier-geoip-cn.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cn_17mon_ipv4.cidr.txt"
  if [ "${#APPLE_ASNS[@]}" -gt 0 ]; then
    sync_pure_asn_ip_list apple "${APPLE_ASNS[@]}"
  fi
  render_ip_text_artifacts "${IP_TEXT_ARTIFACTS[@]}"
  if [ "${#GOOGLE_ASNS[@]}" -gt 0 ]; then
    sync_merged_asn_ip_list google "${GOOGLE_ASNS[@]}"
  fi
  if [ "${#TELEGRAM_ASNS[@]}" -gt 0 ]; then
    sync_merged_asn_ip_list telegram "${TELEGRAM_ASNS[@]}"
  fi

  mkdir -p "$CANONICAL_ARTIFACTS_DIR/ip"
  for name in "${IP_TEXT_ARTIFACTS[@]}"; do
    render_ip_plain_to_canonical_list \
      "$IP_BUILD_TMP_DIR/${name}.cidr.txt" \
      "$CANONICAL_ARTIFACTS_DIR/ip/${name}.list"
  done

  assert_files_present "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/surge/*.list"
  assert_files_present "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/quanx/*.list"
  build_ip_artifacts_from_surge_dir \
    "$IP_ARTIFACTS_DIR/surge" \
    "$IP_BUILD_TMP_DIR/binary-compile" \
    "$IP_ARTIFACTS_DIR/sing-box" \
    "$IP_ARTIFACTS_DIR/mihomo"
  assert_files_present "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/sing-box/*.srs"
  assert_files_present "$IP_ARTIFACTS_DIR/mihomo" "$IP_ARTIFACTS_DIR/mihomo/*.mrs"
  assert_files_present "$IP_ARTIFACTS_DIR/egern" "$IP_ARTIFACTS_DIR/egern/*.yaml"

  echo "=== SYNC DONE ==="
}

main
