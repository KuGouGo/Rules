#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CUSTOM_DOMAIN_DIR="$ROOT/sources/custom/domain"
CUSTOM_IP_DIR="$ROOT/sources/custom/ip"
TMP_DIR="$ROOT/.tmp/custom"
TMP_DOMAIN_DIR="$TMP_DIR/domain"
TMP_IP_DIR="$TMP_DIR/ip"
BIN_DIR="$ROOT/.bin"
ARTIFACT_ROOT="$ROOT/.output"
DOMAIN_SURGE_DIR="$ARTIFACT_ROOT/domain/surge"
DOMAIN_SINGBOX_DIR="$ARTIFACT_ROOT/domain/sing-box"
DOMAIN_MIHOMO_DIR="$ARTIFACT_ROOT/domain/mihomo"
IP_SURGE_DIR="$ARTIFACT_ROOT/ip/surge"
IP_SINGBOX_DIR="$ARTIFACT_ROOT/ip/sing-box"
IP_MIHOMO_DIR="$ARTIFACT_ROOT/ip/mihomo"

source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/lib/rules.sh"

mkdir -p \
  "$DOMAIN_SURGE_DIR" \
  "$DOMAIN_SINGBOX_DIR" \
  "$DOMAIN_MIHOMO_DIR" \
  "$IP_SURGE_DIR" \
  "$IP_SINGBOX_DIR" \
  "$IP_MIHOMO_DIR" \
  "$BIN_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DOMAIN_DIR" "$TMP_IP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

shopt -s nullglob
custom_domain_lists=("$CUSTOM_DOMAIN_DIR"/*.list)
custom_ip_lists=("$CUSTOM_IP_DIR"/*.list)
if [ ${#custom_domain_lists[@]} -eq 0 ] && [ ${#custom_ip_lists[@]} -eq 0 ]; then
  echo "no custom rule lists found, skip"
  exit 0
fi

collect_tracked_bases() {
  local dir="$1"

  if [ ! -d "$dir" ]; then
    return 0
  fi

  find "$dir" -maxdepth 1 -type f -name '*.list' -exec basename {} .list \; | sort
}

is_tracked_base() {
  local name="$1"
  local tracked_bases="$2"
  printf '%s\n' "$tracked_bases" | grep -Fxq "$name"
}

assert_no_name_conflict() {
  local base="$1"
  local tracked_bases="$2"
  local custom_dir="$3"
  shift 3
  local conflicts=()
  local tracked_path

  if is_tracked_base "$base" "$tracked_bases"; then
    return 0
  fi

  for tracked_path in "$@"; do
    if [ -e "$ROOT/$tracked_path" ]; then
      conflicts+=("$tracked_path")
    fi
  done

  if [ ${#conflicts[@]} -gt 0 ]; then
    echo "custom rule name conflict detected for base '$base'" >&2
    printf 'conflicting generated files:\n' >&2
    printf '  - %s\n' "${conflicts[@]}" >&2
    echo "rename $custom_dir/$base.list to a unique name and retry" >&2
    return 1
  fi
}

build_domain_plain_and_surge() {
  local list_file="$1"
  local base surge_out plain_out surge_tmp plain_tmp
  base="$(basename "$list_file" .list)"
  surge_out="$DOMAIN_SURGE_DIR/$base.list"
  plain_out="$TMP_DOMAIN_DIR/$base.list"
  surge_tmp="$TMP_DOMAIN_DIR/$base.surge.tmp"
  plain_tmp="$TMP_DOMAIN_DIR/$base.plain.tmp"

  normalize_custom_domain_source "$list_file" "$surge_tmp" "$plain_tmp"
  write_if_changed "$surge_tmp" "$surge_out"
  mv "$plain_tmp" "$plain_out"
  rm -f "$surge_tmp"
}

build_domain_binaries() {
  local plain_list="$1"
  local base json srs_tmp mrs_tmp domains suffixes
  base="$(basename "$plain_list" .list)"
  json="$TMP_DOMAIN_DIR/$base.json"
  srs_tmp="$TMP_DOMAIN_DIR/$base.srs.tmp"
  mrs_tmp="$TMP_DOMAIN_DIR/$base.mrs.tmp"
  compile_domain_plain_to_binary_artifacts "$plain_list" "$json" "$srs_tmp" "$mrs_tmp" || {
    echo "failed to build custom domain binary rules for $base" >&2
    return 1
  }
  write_if_changed "$srs_tmp" "$DOMAIN_SINGBOX_DIR/$base.srs"
  write_if_changed "$mrs_tmp" "$DOMAIN_MIHOMO_DIR/$base.mrs"
}

build_ip_plain_and_surge() {
  local list_file="$1"
  local base surge_out plain_out surge_tmp plain_tmp
  base="$(basename "$list_file" .list)"
  surge_out="$IP_SURGE_DIR/$base.list"
  plain_out="$TMP_IP_DIR/$base.txt"
  surge_tmp="$TMP_IP_DIR/$base.surge.tmp"
  plain_tmp="$TMP_IP_DIR/$base.plain.tmp"

  normalize_ip_rule_source "$list_file" "$surge_tmp" "$plain_tmp"
  write_if_changed "$surge_tmp" "$surge_out"
  mv "$plain_tmp" "$plain_out"
  rm -f "$surge_tmp"
}

build_ip_binaries() {
  local plain_list="$1"
  local base json srs_tmp mrs_tmp cidrs
  base="$(basename "$plain_list" .txt)"
  json="$TMP_IP_DIR/$base.json"
  srs_tmp="$TMP_IP_DIR/$base.srs.tmp"
  mrs_tmp="$TMP_IP_DIR/$base.mrs.tmp"
  compile_ip_plain_to_binary_artifacts "$plain_list" "$json" "$srs_tmp" "$mrs_tmp" || {
    echo "failed to build custom IP binary rules for $base" >&2
    return 1
  }
  write_if_changed "$srs_tmp" "$IP_SINGBOX_DIR/$base.srs"
  write_if_changed "$mrs_tmp" "$IP_MIHOMO_DIR/$base.mrs"
}

tracked_custom_domain_bases="$(collect_tracked_bases "$CUSTOM_DOMAIN_DIR")"
tracked_custom_ip_bases="$(collect_tracked_bases "$CUSTOM_IP_DIR")"

for list_file in "${custom_domain_lists[@]}"; do
  base="$(basename "$list_file" .list)"
  assert_no_name_conflict \
    "$base" \
    "$tracked_custom_domain_bases" \
    "$CUSTOM_DOMAIN_DIR" \
    ".output/domain/surge/$base.list" \
    ".output/domain/sing-box/$base.srs" \
    ".output/domain/mihomo/$base.mrs"
  build_domain_plain_and_surge "$list_file"
done

for list_file in "${custom_ip_lists[@]}"; do
  base="$(basename "$list_file" .list)"
  assert_no_name_conflict \
    "$base" \
    "$tracked_custom_ip_bases" \
    "$CUSTOM_IP_DIR" \
    ".output/ip/surge/$base.list" \
    ".output/ip/sing-box/$base.srs" \
    ".output/ip/mihomo/$base.mrs"
  build_ip_plain_and_surge "$list_file"
done

if [ ${#custom_domain_lists[@]} -gt 0 ] || [ ${#custom_ip_lists[@]} -gt 0 ]; then
  ensure_rule_build_tools
fi

for plain_list in "$TMP_DOMAIN_DIR"/*.list; do
  [ -f "$plain_list" ] || continue
  build_domain_binaries "$plain_list"
done

for plain_list in "$TMP_IP_DIR"/*.txt; do
  [ -f "$plain_list" ] || continue
  build_ip_binaries "$plain_list"
done

echo "custom build done"
