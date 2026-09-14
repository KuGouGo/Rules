#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

entries = {}
for section_name in ("domain", "ip"):
    for name, spec in config[section_name].items():
        entries[f"{section_name}.{name}.url"] = spec["url"]
        entries[f"{section_name}.{name}.parser"] = spec["parser"]
        entries[f"{section_name}.{name}.min_entries"] = str(spec["health"]["min_entries"])
        entries[f"{section_name}.{name}.min_raw_bytes"] = str(spec["health"]["min_raw_bytes"])
for _group, _asns in config.get("asn_groups", {}).items():
    entries[f"asn.{_group}"] = " ".join(str(asn) for asn in _asns)
for key, value in entries.items():
    print(f"{key}\t{value}")
PY
)

DLC_MIN_AGGREGATE_CN_RULES="${DLC_MIN_AGGREGATE_CN_RULES:-500}"
DOMAIN_PUBLISH_POLICY="$ROOT_DIR/config/domain-publish-policy.json"

# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=scripts/lib/rules.sh
source "$ROOT_DIR/scripts/lib/rules.sh"
setup_tool_cache

slug_of() {
  printf '%s' "$1" | tr '-' '_'
}

declare -a IP_TEXT_SOURCE_NAMES=() IP_ASN_SOURCE_NAMES=()
declare -A IP_SOURCE_EXTENSIONS=()
while IFS= read -r settings_key; do
  section="${settings_key%%.*}"
  name="${settings_key#*.}"
  name="${name%.parser}"
  parser="${UPSTREAM_SETTINGS[$settings_key]}"
  case "$section:$parser" in
    ip:cidr-text)
      IP_TEXT_SOURCE_NAMES+=("$name")
      IP_SOURCE_EXTENSIONS["$name"]="txt"
      ;;
    ip:iptoasn-tsv)
      IP_ASN_SOURCE_NAMES+=("$name")
      IP_SOURCE_EXTENSIONS["$name"]="tsv.gz"
      ;;
    domain:git-tree|domain:domain-set-text) ;;
    *)
      echo "unsupported IP source parser for $name: $parser" >&2
      exit 1
      ;;
  esac
done < <(printf '%s\n' "${!UPSTREAM_SETTINGS[@]}" | grep '\.parser$' | sort)

for settings_key in $(printf '%s\n' "${!UPSTREAM_SETTINGS[@]}" | grep '\.url$' | sort); do
  if [ -z "${UPSTREAM_SETTINGS[${settings_key%.url}.parser]:-}" ]; then
    echo "configured source is missing a parser classification: ${settings_key%.url}" >&2
    exit 1
  fi
done

declare -a ASN_GROUP_NAMES=() ASN_GROUP_SPECS=()
while IFS= read -r settings_key; do
  group="${settings_key#asn.}"
  ASN_GROUP_NAMES+=("$group")
  ASN_GROUP_SPECS+=("${group}=$(printf '%s' "${UPSTREAM_SETTINGS[$settings_key]}" | tr ' ' ',')")
done < <(printf '%s\n' "${!UPSTREAM_SETTINGS[@]}" | grep '^asn\.' | sort)

for group in "${ASN_GROUP_NAMES[@]}"; do
  case " ${IP_TEXT_ARTIFACTS[*]} " in
    *" $group "*) ;;
    *)
      echo "asn group $group is missing from IP_TEXT_ARTIFACTS" >&2
      exit 1
      ;;
  esac
done
for artifact_name in "${IP_TEXT_ARTIFACTS[@]}"; do
  if [ "$artifact_name" = "cn" ]; then
    continue
  fi
  case " ${ASN_GROUP_NAMES[*]:-} " in
    *" $artifact_name "*) ;;
    *)
      echo "IP text artifact $artifact_name has no matching asn group in config" >&2
      exit 1
      ;;
  esac
done

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

extract_asn_group_cidrs() {
  local name slug family raw_file output_template

  for name in "${IP_ASN_SOURCE_NAMES[@]}"; do
    slug="$(slug_of "$name")"
    case "$name" in
      *ipv6*) family="v6" ;;
      *ipv4*) family="v4" ;;
      *)
        echo "cannot determine address family for ASN source: $name" >&2
        return 1
        ;;
    esac
    raw_file="$IP_BUILD_TMP_DIR/${slug}.raw.${IP_SOURCE_EXTENSIONS[$name]}"
    output_template="$IP_BUILD_TMP_DIR/{name}_asn_${family}.cidr.txt"
    if ! python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" iptoasn-tsv-multi \
      "$raw_file" "$output_template" "${ASN_GROUP_SPECS[@]}"; then
      echo "iptoasn ${family} extraction failed for groups: ${ASN_GROUP_NAMES[*]}" >&2
      return 1
    fi
  done
}

sync_pure_asn_ip_list() {
  local group v4_out v6_out asn_file

  for group in "$@"; do
    v4_out="$IP_BUILD_TMP_DIR/${group}_asn_v4.cidr.txt"
    v6_out="$IP_BUILD_TMP_DIR/${group}_asn_v6.cidr.txt"
    if [ ! -s "$v4_out" ] && [ ! -s "$v6_out" ]; then
      echo "iptoasn group $group produced no prefixes (ASNs: ${UPSTREAM_SETTINGS[asn.${group}]})" >&2
      return 1
    fi
    asn_file="$IP_BUILD_TMP_DIR/${group}_asn.cidr.txt"
    merge_cidr_plain_files "$asn_file" "$v4_out" "$v6_out"
    mv "$asn_file" "$IP_BUILD_TMP_DIR/${group}.cidr.txt"
  done
}

download_ip_sources() {
  local name slug extension
  local -a download_args=()

  for name in "${IP_TEXT_SOURCE_NAMES[@]}" "${IP_ASN_SOURCE_NAMES[@]}"; do
    slug="$(slug_of "$name")"
    extension="${IP_SOURCE_EXTENSIONS[$name]}"
    download_args+=(
      "$name" "${UPSTREAM_SETTINGS[ip.${name}.url]}" "$IP_BUILD_TMP_DIR/${slug}.raw.${extension}"
    )
  done
  download_files_parallel "${download_args[@]}"
}

generate_ip_normalize_manifest() {
  local manifest_file="$1"
  local name slug
  local -a triplets=()

  for name in "${IP_TEXT_SOURCE_NAMES[@]}"; do
    slug="$(slug_of "$name")"
    triplets+=(
      text "$IP_BUILD_TMP_DIR/${slug}.raw.txt" "$IP_BUILD_TMP_DIR/${slug}.cidr.txt"
    )
  done
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" generate-manifest "$manifest_file" "${triplets[@]}"
}

check_asn_source_gates() {
  local name slug raw_file min_lines min_bytes line_count raw_bytes

  for name in "${IP_ASN_SOURCE_NAMES[@]}"; do
    slug="$(slug_of "$name")"
    raw_file="$IP_BUILD_TMP_DIR/${slug}.raw.${IP_SOURCE_EXTENSIONS[$name]}"
    min_lines="${UPSTREAM_SETTINGS[ip.${name}.min_entries]}"
    min_bytes="${UPSTREAM_SETTINGS[ip.${name}.min_raw_bytes]}"
    if [ "${IP_SOURCE_EXTENSIONS[$name]}" = "tsv.gz" ]; then
      if ! line_count="$(gzip -dc "$raw_file" | wc -l)"; then
        echo "failed to read ASN source snapshot: $raw_file" >&2
        return 1
      fi
    else
      line_count="$(wc -l < "$raw_file")"
    fi
    raw_bytes="$(wc -c < "$raw_file")"
    echo "iptoasn snapshot health gate: $name lines=$line_count/$min_lines bytes=$raw_bytes/$min_bytes"
    if [ "$line_count" -lt "$min_lines" ] || [ "$raw_bytes" -lt "$min_bytes" ]; then
      echo "iptoasn snapshot health gate failed: $name" >&2
      return 1
    fi
  done
}

check_ip_text_source_health() {
  local name slug

  for name in "${IP_TEXT_SOURCE_NAMES[@]}"; do
    slug="$(slug_of "$name")"
    check_upstream_health ip "$name" \
      "$IP_BUILD_TMP_DIR/${slug}.raw.txt" "$IP_BUILD_TMP_DIR/${slug}.cidr.txt"
  done
}

merge_cn_cidr_sources() {
  local name slug
  local -a merge_inputs=()

  for name in "${IP_TEXT_SOURCE_NAMES[@]}"; do
    slug="$(slug_of "$name")"
    merge_inputs+=("$IP_BUILD_TMP_DIR/${slug}.cidr.txt")
  done
  merge_cidr_plain_files "$IP_BUILD_TMP_DIR/cn.cidr.txt" "${merge_inputs[@]}"
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
    shellcrash-fakeip "${UPSTREAM_SETTINGS[domain.shellcrash-fakeip.url]}" "$WORK_TMP_DIR/shellcrash-fakeip.raw.list"

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

  download_ip_sources
  check_asn_source_gates

  IP_NORMALIZE_MANIFEST="$IP_BUILD_TMP_DIR/normalize-tasks.json"
  generate_ip_normalize_manifest "$IP_NORMALIZE_MANIFEST"
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" batch "$IP_NORMALIZE_MANIFEST"

  check_ip_text_source_health
  merge_cn_cidr_sources
  extract_asn_group_cidrs
  sync_pure_asn_ip_list "${ASN_GROUP_NAMES[@]}"
  render_ip_text_artifacts "${IP_TEXT_ARTIFACTS[@]}"

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
