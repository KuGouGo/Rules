#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if [ -z "${RULES_ARTIFACT_ROOT:-}" ]; then
  RULES_BUILD_SCOPE=full exec "$ROOT_DIR/scripts/commands/build-artifacts-transaction.sh"
fi

WORK_TMP_DIR="$ROOT_DIR/.tmp/sync"
BIN_DIR="$ROOT_DIR/.bin"
DOMAIN_BUILD_TMP_DIR="$WORK_TMP_DIR/domain-build"
DOMAIN_RULE_TMP_DIR="$WORK_TMP_DIR/domain-rules"
IP_BUILD_TMP_DIR="$WORK_TMP_DIR/ip-build"
ARTIFACTS_DIR="${RULES_ARTIFACT_ROOT:-$ROOT_DIR/.output}"
DIAGNOSTICS_DIR="${RULES_ARTIFACT_DIAGNOSTICS_ROOT:-$ROOT_DIR/.tmp/artifact-diagnostics}"
DOMAIN_ARTIFACTS_DIR="$ARTIFACTS_DIR/domain"
IP_ARTIFACTS_DIR="$ARTIFACTS_DIR/ip"
CANONICAL_ARTIFACTS_DIR="$ARTIFACTS_DIR/.canonical"
DOMAIN_RULE_MANIFEST_FILE="$DOMAIN_ARTIFACTS_DIR/rule-manifest.json"
IP_TEXT_ARTIFACTS=(cn private google telegram cloudflare cloudfront fastly apple)

UPSTREAMS_CONFIG_FILE="$ROOT_DIR/config/upstreams.json"
UPSTREAM_PINS_FILE="$ROOT_DIR/config/upstream-pins.json"
UPSTREAM_SUMMARY_FILE="$WORK_TMP_DIR/upstream-summary.jsonl"
BUILTIN_PRIVATE_SOURCE_FILE="$ROOT_DIR/sources/builtin/ip/private.list"
BUILTIN_APPLE_SOURCE_FILE="$ROOT_DIR/sources/builtin/ip/apple.list"

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
    "ip.cn-clang-ipv4.url": config["ip"]["cn-clang-ipv4"]["url"],
    "ip.cn-clang-ipv6.url": config["ip"]["cn-clang-ipv6"]["url"],
    "ip.google.url": config["ip"]["google"]["url"],
    "ip.telegram.url": config["ip"]["telegram"]["url"],
    "ip.cloudflare-ipv4.url": config["ip"]["cloudflare-ipv4"]["url"],
    "ip.cloudflare-ipv6.url": config["ip"]["cloudflare-ipv6"]["url"],
    "ip.cloudfront.url": config["ip"]["cloudfront"]["url"],
    "ip.fastly.url": config["ip"]["fastly"]["url"],
    "ip.ripe-stat.base_url": config["ip"]["ripe-stat"]["base_url"],
    "asn.telegram": " ".join(str(asn) for asn in config["asn_groups"]["telegram"]),
}
for key, value in entries.items():
    print(f"{key}\t{value}")
PY
)

require_upstream_settings() {
  local missing=0
  local key
  for key in "$@"; do
    if [ -z "${UPSTREAM_SETTINGS[$key]:-}" ]; then
      echo "failed to load upstream setting: $key" >&2
      missing=1
    fi
  done
  [ "$missing" -eq 0 ]
}

require_upstream_settings \
  domain.dlc.url domain.shellcrash-fakeip.url \
  ip.cn-ipv46-apnic.url ip.cn-clang-ipv4.url ip.cn-clang-ipv6.url \
  ip.google.url ip.telegram.url ip.cloudflare-ipv4.url ip.cloudflare-ipv6.url \
  ip.cloudfront.url ip.fastly.url ip.ripe-stat.base_url \
  asn.telegram

DOMAIN_SOURCE_REPO_URL="${UPSTREAM_SETTINGS[domain.dlc.url]}"
SHELLCRASH_FAKEIP_SOURCE_URL="${UPSTREAM_SETTINGS[domain.shellcrash-fakeip.url]}"
CN_IPV46_APNIC_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cn-ipv46-apnic.url]}"
CN_CLANG_IPV4_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cn-clang-ipv4.url]}"
CN_CLANG_IPV6_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cn-clang-ipv6.url]}"
GOOGLE_IP_SOURCE_URL="${UPSTREAM_SETTINGS[ip.google.url]}"
TELEGRAM_IP_SOURCE_URL="${UPSTREAM_SETTINGS[ip.telegram.url]}"
CLOUDFLARE_IPV4_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cloudflare-ipv4.url]}"
CLOUDFLARE_IPV6_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cloudflare-ipv6.url]}"
CLOUDFRONT_IP_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cloudfront.url]}"
FASTLY_IP_SOURCE_URL="${UPSTREAM_SETTINGS[ip.fastly.url]}"
RIPE_STAT_BASE_URL="${UPSTREAM_SETTINGS[ip.ripe-stat.base_url]}"
DLC_MIN_AGGREGATE_CN_RULES="${DLC_MIN_AGGREGATE_CN_RULES:-500}"
DOMAIN_PUBLISH_POLICY="$ROOT_DIR/config/domain-publish-policy.json"
read -r -a TELEGRAM_ASNS <<< "${UPSTREAM_SETTINGS[asn.telegram]}"

# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=scripts/lib/rules.sh
source "$ROOT_DIR/scripts/lib/rules.sh"
setup_tool_cache

rm -rf "$WORK_TMP_DIR"
mkdir -p "$WORK_TMP_DIR" "$BIN_DIR" "$DOMAIN_BUILD_TMP_DIR" "$DOMAIN_RULE_TMP_DIR" "$IP_BUILD_TMP_DIR"
preserve_sync_diagnostics() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    mkdir -p "$DIAGNOSTICS_DIR"
    [ ! -s "$UPSTREAM_SUMMARY_FILE" ] || cp "$UPSTREAM_SUMMARY_FILE" "$DIAGNOSTICS_DIR/upstream-summary.jsonl"
    [ ! -f "$ARTIFACTS_DIR/upstream-summary.json" ] || cp "$ARTIFACTS_DIR/upstream-summary.json" "$DIAGNOSTICS_DIR/upstream-summary.json"
  fi
  rm -rf "$WORK_TMP_DIR"
  return "$status"
}
trap preserve_sync_diagnostics EXIT

rm -rf "$CANONICAL_ARTIFACTS_DIR"
mkdir -p "$DOMAIN_ARTIFACTS_DIR" "$IP_ARTIFACTS_DIR" "$CANONICAL_ARTIFACTS_DIR"
: > "$UPSTREAM_SUMMARY_FILE"


inject_sync_failure() {
  local point="$1"
  if [ "${RULES_SYNC_FAIL_AT:-}" = "$point" ]; then
    echo "injected upstream sync failure at $point" >&2
    return 1
  fi
}

record_upstream_summary() {
  local category="$1"
  local name="$2"
  local status="$3"
  local url="$4"
  local raw_file="${5:-}"
  local normalized_file="${6:-}"
  local fallback_used="${7:-0}"
  local detail="${8:-}"

  python3 "$ROOT_DIR/scripts/tools/upstream_summary.py" record \
    "$UPSTREAMS_CONFIG_FILE" "$UPSTREAM_SUMMARY_FILE" \
    "$category" "$name" "$status" "$url" \
    "$raw_file" "$normalized_file" "$fallback_used" "$detail"
}

verify_and_record_upstream_health() {
  local category="$1"
  local name="$2"
  local url="$3"
  local raw_file="$4"
  local normalized_file="$5"
  local fallback_used="${6:-0}"
  local context="${7:-}"
  local health_json status detail health_detail verifier_failed=0
  local -a health_fields=()

  if health_json="$(python3 "$ROOT_DIR/scripts/tools/verify-upstream-health.py" \
    "$UPSTREAMS_CONFIG_FILE" "$category" "$name" "$raw_file" "$normalized_file")"; then
    :
  else
    verifier_failed=1
  fi
  mapfile -t health_fields < <(
    printf '%s' "$health_json" \
      | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data["status"]); print("; ".join(data.get("errors", [])))' \
        2>/dev/null
  )
  if [ "${#health_fields[@]}" -ne 2 ]; then
    status=semantic_regression
    health_detail="health verifier failed"
    verifier_failed=1
  else
    status="${health_fields[0]}"
    health_detail="${health_fields[1]}"
  fi
  case "$status" in
    ok|semantic_regression) ;;
    *) status=semantic_regression; verifier_failed=1 ;;
  esac
  if [ "$status" = "semantic_regression" ] && [ "$verifier_failed" -eq 0 ]; then
    detail="optional source failed health policy"
  else
    detail=""
  fi
  detail="${health_detail:-$detail}"
  if [ -n "$context" ]; then
    detail="${context}${detail:+; $detail}"
  fi
  record_upstream_summary \
    "$category" "$name" "$status" "$url" "$raw_file" "$normalized_file" "$fallback_used" "$detail"
  if [ "$verifier_failed" -ne 0 ]; then
    echo "required upstream $name failed configured health policy: $detail" >&2
    return 1
  fi
}

write_upstream_summary_json() {
  local json_file="$ARTIFACTS_DIR/upstream-summary.json"
  python3 "$ROOT_DIR/scripts/tools/upstream_summary.py" finalize \
    "$UPSTREAM_SUMMARY_FILE" "$json_file"
  rm -f "$UPSTREAM_SUMMARY_FILE"
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

# Run the RIPE Stat health verifier for a raw/normalized pair; sets
# ripe_health_status and ripe_health_detail for the caller to record.
run_ripe_stat_health() {
  local raw_file="$1"
  local normalized_file="$2"
  local health_json
  if health_json="$(python3 "$ROOT_DIR/scripts/tools/verify-upstream-health.py" \
    "$UPSTREAMS_CONFIG_FILE" ip ripe-stat "$raw_file" "$normalized_file")"; then
    ripe_health_status=ok
  else
    ripe_health_status=semantic_regression
  fi
  ripe_health_detail="$(printf '%s' "$health_json" | python3 -c 'import json,sys; print("; ".join(json.load(sys.stdin).get("errors", [])))' 2>/dev/null || printf 'health verifier failed')"
}

prepare_ripe_stat_asns() {
  local -A seen=()
  local -a unique_asns=() download_args=()
  local asn raw_json cidr_txt

  for asn in "$@"; do
    if [ -n "${seen[$asn]:-}" ]; then
      continue
    fi
    seen[$asn]=1
    unique_asns+=("$asn")
    raw_json="$IP_BUILD_TMP_DIR/ripe_as${asn}.raw.json"
    download_args+=("ripe-stat-as${asn}" required "${RIPE_STAT_BASE_URL}${asn}" "$raw_json")
  done
  download_files_parallel "${download_args[@]}"

  for asn in "${unique_asns[@]}"; do
    raw_json="$IP_BUILD_TMP_DIR/ripe_as${asn}.raw.json"
    cidr_txt="$IP_BUILD_TMP_DIR/ripe_as${asn}.cidr.txt"
    if ! python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" single ripe-stat-json "$raw_json" "$cidr_txt"; then
      : > "$cidr_txt"
      record_upstream_summary ip "ripe-stat-as${asn}" semantic_regression "${RIPE_STAT_BASE_URL}${asn}" "$raw_json" "$cidr_txt" 0 "invalid RIPE Stat response"
      echo "RIPE Stat response AS${asn} is invalid" >&2
      return 1
    fi

    run_ripe_stat_health "$raw_json" "$cidr_txt"
    record_upstream_summary ip "ripe-stat-as${asn}" "$ripe_health_status" "${RIPE_STAT_BASE_URL}${asn}" "$raw_json" "$cidr_txt" 0 "$ripe_health_detail"
    if [ "$ripe_health_status" != "ok" ]; then
      echo "RIPE Stat response AS${asn} failed configured health policy: $ripe_health_detail" >&2
      return 1
    fi
  done
}

sync_asn_ip_cidrs() {
  local name="$1"
  shift
  local -a asns=("$@") cidr_files=()
  local asn raw_json cidr_txt

  for asn in "${asns[@]}"; do
    raw_json="$IP_BUILD_TMP_DIR/ripe_as${asn}.raw.json"
    cidr_txt="$IP_BUILD_TMP_DIR/ripe_as${asn}.cidr.txt"
    if [ ! -s "$raw_json" ] || [ ! -s "$cidr_txt" ]; then
      echo "RIPE Stat AS${asn} was not prepared" >&2
      return 1
    fi
    cidr_files+=("$cidr_txt")
  done

  merge_cidr_plain_files "$IP_BUILD_TMP_DIR/${name}.cidr.txt" "${cidr_files[@]}"

  if [ ! -s "$IP_BUILD_TMP_DIR/${name}.cidr.txt" ]; then
    echo "RIPE Stat group $name produced no prefixes (ASNs: ${asns[*]})" >&2
    record_upstream_summary ip "ripe-stat-group-${name}" semantic_regression "$RIPE_STAT_BASE_URL" "" "$IP_BUILD_TMP_DIR/${name}.cidr.txt" 0 "empty normalized group"
    return 1
  fi

  local group_raw="$IP_BUILD_TMP_DIR/${name}.ripe-group.raw"
  : > "$group_raw"
  for asn in "${asns[@]}"; do
    cat "$IP_BUILD_TMP_DIR/ripe_as${asn}.raw.json" >> "$group_raw"
  done
  run_ripe_stat_health "$group_raw" "$IP_BUILD_TMP_DIR/${name}.cidr.txt"
  record_upstream_summary ip "ripe-stat-group-${name}" "$ripe_health_status" "$RIPE_STAT_BASE_URL" "$group_raw" "$IP_BUILD_TMP_DIR/${name}.cidr.txt" 0 "asns=${asns[*]}${ripe_health_detail:+; $ripe_health_detail}"
  if [ "$ripe_health_status" != "ok" ]; then
    echo "RIPE Stat group $name failed configured health policy: $ripe_health_detail" >&2
    return 1
  fi
}

# sync_merged_asn_ip_list <name> <asn> [<asn> ...]
# Download RIPEstat announced-prefix data for each ASN, merge it with the
# direct source, and render the public IP text artifact for the named ruleset.
sync_merged_asn_ip_list() {
  local name="$1"
  shift
  local source_file="$IP_BUILD_TMP_DIR/${name}.cidr.txt"
  local asn_file="$IP_BUILD_TMP_DIR/${name}_asn.cidr.txt"
  local merged_file="$IP_BUILD_TMP_DIR/${name}_merged.cidr.txt"

  sync_asn_ip_cidrs "${name}_asn" "$@"

  if [ ! -s "$asn_file" ]; then
    echo "warning: no ASN prefixes found for $name, keeping direct source only" >&2
    return 0
  fi

  # ASN prefixes are still parsed to CIDR, then collapsed with the official
  # list so redundant child prefixes do not bloat published rules.
  merge_cidr_plain_files "$merged_file" "$source_file" "$asn_file"
  mv "$merged_file" "$source_file"
  render_ip_text_artifact "$name"
  record_upstream_summary ip "${name}-merged" ok "$RIPE_STAT_BASE_URL" "" "$source_file" 0 "official+asn-collapsed"
}

generate_ip_normalize_manifest() {
  local manifest_file="$1"
  local tmp_dir="$IP_BUILD_TMP_DIR"

  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" generate-manifest "$manifest_file" \
    text "$tmp_dir/cn_ipv46_apnic.raw.txt" "$tmp_dir/cn_ipv46_apnic.cidr.txt" \
    text "$tmp_dir/cn_clang_ipv4.raw.txt" "$tmp_dir/cn_clang_ipv4.cidr.txt" \
    text "$tmp_dir/cn_clang_ipv6.raw.txt" "$tmp_dir/cn_clang_ipv6.cidr.txt" \
    text "$tmp_dir/cloudflare_ipv4.raw.txt" "$tmp_dir/cloudflare_ipv4.cidr.txt" \
    text "$tmp_dir/cloudflare_ipv6.raw.txt" "$tmp_dir/cloudflare_ipv6.cidr.txt" \
    cloudfront-json "$tmp_dir/cloudfront.raw.json" "$tmp_dir/cloudfront.cidr.txt" \
    fastly-json "$tmp_dir/fastly.raw.json" "$tmp_dir/fastly.cidr.txt"
}

declare -A FIRST_BATCH_RAW_FILE=(
  [google-json]="$IP_BUILD_TMP_DIR/google.raw.json"
  [telegram]="$IP_BUILD_TMP_DIR/telegram.raw.txt"
)
declare -A FIRST_BATCH_OUTPUT_FILE=(
  [google-json]="$IP_BUILD_TMP_DIR/google.cidr.txt"
  [telegram]="$IP_BUILD_TMP_DIR/telegram.cidr.txt"
)
declare -A FIRST_BATCH_SOURCE_TYPE=([google-json]="google-json" [telegram]="text")
declare -A FIRST_BATCH_CONFIG_NAME=([google-json]="google" [telegram]="telegram")
declare -A FIRST_BATCH_SOURCE_URL=(
  [google-json]="$GOOGLE_IP_SOURCE_URL"
  [telegram]="$TELEGRAM_IP_SOURCE_URL"
)

# google-json / telegram are required upstreams: a missing or empty raw
# payload is a transport incident and must fail the build fail-closed.
# Semantic content checks are handled later by verify-upstream-health, which
# runs against the same raw + normalized files with stronger contract floors.
ensure_first_batch_raw() {
  local source="$1"
  local raw_file

  raw_file="${FIRST_BATCH_RAW_FILE[$source]:-}"
  if [ -z "$raw_file" ]; then
    echo "unsupported first-batch source: $source" >&2
    return 1
  fi
  if [ ! -s "$raw_file" ]; then
    record_upstream_summary \
      ip \
      "${FIRST_BATCH_CONFIG_NAME[$source]}" \
      transport_incident \
      "${FIRST_BATCH_SOURCE_URL[$source]}" \
      "$raw_file" \
      "" \
      0 \
      "raw payload missing or empty"
    echo "required first-batch source $source missing or empty: $raw_file" >&2
    return 1
  fi
}

normalize_first_batch_source() {
  local source="$1"
  local raw_file output_file source_type

  if [ -z "${FIRST_BATCH_RAW_FILE[$source]:-}" ]; then
    echo "unsupported first-batch source: $source" >&2
    return 1
  fi

  raw_file="${FIRST_BATCH_RAW_FILE[$source]:-}"
  output_file="${FIRST_BATCH_OUTPUT_FILE[$source]:-}"
  source_type="${FIRST_BATCH_SOURCE_TYPE[$source]:-}"
  if [ -z "$raw_file" ] || [ -z "$output_file" ] || [ -z "$source_type" ]; then
    echo "unsupported first-batch source: $source" >&2
    return 1
  fi

  if ! python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" single "$source_type" "$raw_file" "$output_file"; then
    record_upstream_summary \
      ip \
      "${FIRST_BATCH_CONFIG_NAME[$source]}" \
      semantic_regression \
      "${FIRST_BATCH_SOURCE_URL[$source]}" \
      "$raw_file" \
      "$output_file" \
      0 \
      "normalization failed"
    return 1
  fi
}


assert_domain_attr_derivatives() {
  local manifest_file="$1"

  python3 "$ROOT_DIR/scripts/tools/assert-domain-derivatives.py" \
    "$manifest_file" \
    "$DLC_MIN_AGGREGATE_CN_RULES" \
    --profile "${DOMAIN_PUBLISH_PROFILE:-common}"
}


main() {
  echo "=== SYNC START ==="
  # Domain rules from domain-list-community/data. The source tree preserves
  # upstream @attributes and -cn/-!cn regional source names, which are required
  # for closing the geographic partition and the geolocation-!cn@cn aggregate.
  rm -rf "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/mihomo"
  clone_repository_shallow "$DOMAIN_SOURCE_REPO_URL" "$WORK_TMP_DIR/domain-list-community"
  # Consume the audited pinned commit, not the upstream's moving master, so a
  # poisoned or merely unexpected upstream push cannot ship without review.
  "$ROOT_DIR/scripts/commands/apply-upstream-pins.sh" \
    "$UPSTREAM_PINS_FILE" \
    "$WORK_TMP_DIR/domain-list-community" \
    domain.dlc
  python3 "$ROOT_DIR/scripts/tools/audit-dlc-data.py" "$WORK_TMP_DIR/domain-list-community/data"
  python3 "$ROOT_DIR/scripts/tools/export-domain-rules.py" export \
    "$WORK_TMP_DIR/domain-list-community/data" \
    "$DOMAIN_RULE_TMP_DIR" \
    --publish-policy "$DOMAIN_PUBLISH_POLICY" \
    --publish-profile "${DOMAIN_PUBLISH_PROFILE:-common}"
  # Verify the DLC export before any supplemental source mutates the rule tree.
  verify_and_record_upstream_health \
    domain \
    dlc \
    "$DOMAIN_SOURCE_REPO_URL" \
    "$WORK_TMP_DIR/domain-list-community/data" \
    "$DOMAIN_RULE_TMP_DIR" \
    0 \
    "commit=$(git -C "$WORK_TMP_DIR/domain-list-community" rev-parse HEAD)"

  # Fetch the Fake-IP filter from ShellCrash upstream.
  download_files_parallel \
    shellcrash-fakeip required "$SHELLCRASH_FAKEIP_SOURCE_URL" "$WORK_TMP_DIR/shellcrash-fakeip.raw.list"

  # Fake-IP filter: download from ShellCrash upstream and convert to classical.
  : > "$DOMAIN_RULE_TMP_DIR/fakeip-filter.list"
  python3 "$ROOT_DIR/scripts/tools/merge-domain-rule-source.py" \
    "$WORK_TMP_DIR/shellcrash-fakeip.raw.list" \
    "$DOMAIN_RULE_TMP_DIR/fakeip-filter.list" \
    "$WORK_TMP_DIR/shellcrash-fakeip.normalized.list"
  verify_and_record_upstream_health \
    domain shellcrash-fakeip "$SHELLCRASH_FAKEIP_SOURCE_URL" \
    "$WORK_TMP_DIR/shellcrash-fakeip.raw.list" \
    "$WORK_TMP_DIR/shellcrash-fakeip.normalized.list" 0

  # Build the manifest and canonical tree once from the final merged rule set.
  python3 "$ROOT_DIR/scripts/tools/export-domain-rules.py" domain-rule-manifest \
    "$DOMAIN_RULE_TMP_DIR" \
    "$DOMAIN_RULE_MANIFEST_FILE"
  stage_domain_canonical_rules \
    "$DOMAIN_RULE_TMP_DIR" \
    "$CANONICAL_ARTIFACTS_DIR/domain"
  assert_domain_attr_derivatives "$DOMAIN_RULE_MANIFEST_FILE"
  assert_files_present "$DOMAIN_RULE_TMP_DIR" "$DOMAIN_RULE_TMP_DIR/*.list"
  render_domain_rule_dir_to_text_platform_dirs \
    "$DOMAIN_RULE_TMP_DIR" \
    "$DOMAIN_ARTIFACTS_DIR/surge" \
    "$DOMAIN_ARTIFACTS_DIR/quanx" \
    "$DOMAIN_ARTIFACTS_DIR/egern"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/surge/*.list"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/quanx/*.list"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/egern/*.yaml"
  inject_sync_failure late-domain

  build_domain_artifacts_from_rule_dir \
    "$DOMAIN_RULE_TMP_DIR" \
    "$DOMAIN_BUILD_TMP_DIR/domain-compile" \
    "$DOMAIN_ARTIFACTS_DIR/sing-box" \
    "$DOMAIN_ARTIFACTS_DIR/mihomo"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/sing-box/*.srs"
  assert_files_present "$DOMAIN_ARTIFACTS_DIR/mihomo" "$DOMAIN_ARTIFACTS_DIR/mihomo/*.mrs"

  # IP rules from curated remote sources
  rm -rf "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/egern" "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/mihomo"
  mkdir -p "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/egern"

  download_files_parallel \
    cn-ipv46-apnic required "$CN_IPV46_APNIC_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv46_apnic.raw.txt" \
    cn-clang-ipv4 required "$CN_CLANG_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_clang_ipv4.raw.txt" \
    cn-clang-ipv6 required "$CN_CLANG_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_clang_ipv6.raw.txt" \
    google classified "$GOOGLE_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/google.raw.json" \
    telegram classified "$TELEGRAM_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/telegram.raw.txt" \
    cloudflare-ipv4 required "$CLOUDFLARE_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv4.raw.txt" \
    cloudflare-ipv6 required "$CLOUDFLARE_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv6.raw.txt" \
    cloudfront required "$CLOUDFRONT_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudfront.raw.json" \
    fastly required "$FASTLY_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/fastly.raw.json"
  ensure_first_batch_raw google-json
  ensure_first_batch_raw telegram

  IP_NORMALIZE_MANIFEST="$IP_BUILD_TMP_DIR/normalize-tasks.json"

  generate_ip_normalize_manifest "$IP_NORMALIZE_MANIFEST"
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" batch "$IP_NORMALIZE_MANIFEST"
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" custom-source \
    "$BUILTIN_PRIVATE_SOURCE_FILE" \
    "$IP_BUILD_TMP_DIR/private.cidr.txt"
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" custom-source \
    "$BUILTIN_APPLE_SOURCE_FILE" \
    "$IP_BUILD_TMP_DIR/apple.cidr.txt"
  normalize_first_batch_source "google-json"
  normalize_first_batch_source "telegram"
  while IFS='|' read -r health_name health_url health_raw health_normalized fallback_used; do
    verify_and_record_upstream_health \
      ip \
      "$health_name" \
      "$health_url" \
      "$IP_BUILD_TMP_DIR/$health_raw" \
      "$IP_BUILD_TMP_DIR/$health_normalized" \
      "$fallback_used"
  done <<EOF
cn-ipv46-apnic|$CN_IPV46_APNIC_SOURCE_URL|cn_ipv46_apnic.raw.txt|cn_ipv46_apnic.cidr.txt|0
cn-clang-ipv4|$CN_CLANG_IPV4_SOURCE_URL|cn_clang_ipv4.raw.txt|cn_clang_ipv4.cidr.txt|0
cn-clang-ipv6|$CN_CLANG_IPV6_SOURCE_URL|cn_clang_ipv6.raw.txt|cn_clang_ipv6.cidr.txt|0
google|$GOOGLE_IP_SOURCE_URL|google.raw.json|google.cidr.txt|0
telegram|$TELEGRAM_IP_SOURCE_URL|telegram.raw.txt|telegram.cidr.txt|0
cloudflare-ipv4|$CLOUDFLARE_IPV4_SOURCE_URL|cloudflare_ipv4.raw.txt|cloudflare_ipv4.cidr.txt|0
cloudflare-ipv6|$CLOUDFLARE_IPV6_SOURCE_URL|cloudflare_ipv6.raw.txt|cloudflare_ipv6.cidr.txt|0
cloudfront|$CLOUDFRONT_IP_SOURCE_URL|cloudfront.raw.json|cloudfront.cidr.txt|0
fastly|$FASTLY_IP_SOURCE_URL|fastly.raw.json|fastly.cidr.txt|0
EOF
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" merge \
    "$IP_BUILD_TMP_DIR/cn.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cn_ipv46_apnic.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cn_clang_ipv4.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cn_clang_ipv6.cidr.txt"
  merge_cidr_plain_files \
    "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cloudflare_ipv4.cidr.txt" \
    "$IP_BUILD_TMP_DIR/cloudflare_ipv6.cidr.txt"
  render_ip_text_artifacts "${IP_TEXT_ARTIFACTS[@]}"

  # Supplement Telegram's direct source with ASN-derived prefixes.
  prepare_ripe_stat_asns \
    "${TELEGRAM_ASNS[@]}"
  sync_merged_asn_ip_list telegram "${TELEGRAM_ASNS[@]}"

  rm -rf "$CANONICAL_ARTIFACTS_DIR/ip"
  mkdir -p "$CANONICAL_ARTIFACTS_DIR/ip"
  for name in "${IP_TEXT_ARTIFACTS[@]}"; do
    render_ip_plain_to_canonical_list \
      "$IP_BUILD_TMP_DIR/${name}.cidr.txt" \
      "$CANONICAL_ARTIFACTS_DIR/ip/${name}.list"
  done

  assert_files_present "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/surge/*.list"
  assert_files_present "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/quanx/*.list"
  inject_sync_failure late-ip
  build_ip_artifacts_from_surge_dir \
    "$IP_ARTIFACTS_DIR/surge" \
    "$IP_BUILD_TMP_DIR/binary-compile" \
    "$IP_ARTIFACTS_DIR/sing-box" \
    "$IP_ARTIFACTS_DIR/mihomo"
  assert_files_present "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/sing-box/*.srs"
  assert_files_present "$IP_ARTIFACTS_DIR/mihomo" "$IP_ARTIFACTS_DIR/mihomo/*.mrs"
  assert_files_present "$IP_ARTIFACTS_DIR/egern" "$IP_ARTIFACTS_DIR/egern/*.yaml"
  inject_sync_failure late-compiler
  write_upstream_summary_json
  python3 "$ROOT_DIR/scripts/tools/artifact_origins.py" reset \
    "$ARTIFACTS_DIR" \
    generated-upstream

  echo "=== SYNC DONE ==="
}

main
