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

has_custom_domain=0
has_custom_ip=0
if [ -d "$CUSTOM_DOMAIN_DIR" ] && find "$CUSTOM_DOMAIN_DIR" -maxdepth 1 -type f -name '*.list' -print -quit | grep -q .; then
  has_custom_domain=1
fi
if [ -d "$CUSTOM_IP_DIR" ] && find "$CUSTOM_IP_DIR" -maxdepth 1 -type f -name '*.list' -print -quit | grep -q .; then
  has_custom_ip=1
fi

if [ "$has_custom_domain" -eq 0 ] && [ "$has_custom_ip" -eq 0 ]; then
  echo "no custom rule lists found, skip"
  exit 0
fi

iter_rule_lists() {
  local dir="$1"

  if [ ! -d "$dir" ]; then
    return 0
  fi

  find "$dir" -maxdepth 1 -type f -name '*.list' | sort
}

resolve_conflict_base_ref() {
  if [ -n "${RULES_CONFLICT_BASE_SHA:-}" ] \
    && git rev-parse --verify "${RULES_CONFLICT_BASE_SHA}^{commit}" >/dev/null 2>&1; then
    printf '%s' "$RULES_CONFLICT_BASE_SHA"
    return 0
  fi

  if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    printf 'HEAD^'
  fi
}

collect_base_custom_sources() {
  local base_ref="$1"

  if [ -z "$base_ref" ]; then
    return 0
  fi

  git ls-tree -r --name-only "$base_ref" -- sources/custom 2>/dev/null || true
}

custom_source_existed_in_base() {
  local rel_path="$1"
  local base_custom_sources="$2"

  printf '%s\n' "$base_custom_sources" | grep -Fxq "$rel_path"
}

assert_no_name_conflict() {
  local base="$1"
  local custom_rel_path="$2"
  local custom_dir="$3"
  local base_custom_sources="$4"
  shift 4
  local conflicts=()
  local tracked_path

  if custom_source_existed_in_base "$custom_rel_path" "$base_custom_sources"; then
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
  local base surge_out plain_out surge_tmp
  base="$(basename "$list_file" .list)"
  surge_out="$DOMAIN_SURGE_DIR/$base.list"
  plain_out="$TMP_DOMAIN_DIR/$base.list"
  surge_tmp="$TMP_DOMAIN_DIR/$base.list.tmp"

  normalize_custom_domain_source "$list_file" "$surge_tmp"
  cp "$surge_tmp" "$plain_out"
  write_if_changed "$surge_tmp" "$surge_out"
}

build_domain_binaries() {
  local plain_list="$1"
  local base json srs_tmp mihomo_text_tmp mihomo_mrs_tmp
  base="$(basename "$plain_list" .list)"
  json="$TMP_DOMAIN_DIR/$base.json"
  srs_tmp="$TMP_DOMAIN_DIR/$base.srs.tmp"
  compile_domain_rule_list_to_artifacts "$plain_list" "$json" "$srs_tmp" || {
    echo "failed to build custom domain binary rules for $base" >&2
    return 1
  }
  write_if_changed "$srs_tmp" "$DOMAIN_SINGBOX_DIR/$base.srs"

  mihomo_text_tmp="$TMP_DOMAIN_DIR/$base.mihomo.txt"
  build_mihomo_domain_text_from_rules "$plain_list" "$mihomo_text_tmp"

  if [ ! -s "$mihomo_text_tmp" ]; then
    echo "custom domain list $base has no DOMAIN/DOMAIN-SUFFIX entries; cannot build mihomo mrs" >&2
    return 1
  fi

  mihomo_mrs_tmp="$TMP_DOMAIN_DIR/$base.mrs.tmp"
  compile_mihomo_domain_plain_to_binary_artifact "$mihomo_text_tmp" "$mihomo_mrs_tmp" || {
    echo "failed to build custom mihomo domain rules for $base" >&2
    return 1
  }
  rm -f "$DOMAIN_MIHOMO_DIR/$base.list"
  write_if_changed "$mihomo_mrs_tmp" "$DOMAIN_MIHOMO_DIR/$base.mrs"
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
  local base json srs_tmp mrs_tmp
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

CONFLICT_BASE_REF="$(resolve_conflict_base_ref)"
BASE_CUSTOM_SOURCES="$(collect_base_custom_sources "$CONFLICT_BASE_REF")"

while IFS= read -r list_file; do
  base="$(basename "$list_file" .list)"
  assert_no_name_conflict \
    "$base" \
    "sources/custom/domain/$base.list" \
    "$CUSTOM_DOMAIN_DIR" \
    "$BASE_CUSTOM_SOURCES" \
    ".output/domain/surge/$base.list" \
    ".output/domain/sing-box/$base.srs" \
    ".output/domain/mihomo/$base.mrs"
  build_domain_plain_and_surge "$list_file"
done < <(iter_rule_lists "$CUSTOM_DOMAIN_DIR")

while IFS= read -r list_file; do
  base="$(basename "$list_file" .list)"
  assert_no_name_conflict \
    "$base" \
    "sources/custom/ip/$base.list" \
    "$CUSTOM_IP_DIR" \
    "$BASE_CUSTOM_SOURCES" \
    ".output/ip/surge/$base.list" \
    ".output/ip/sing-box/$base.srs" \
    ".output/ip/mihomo/$base.mrs"
  build_ip_plain_and_surge "$list_file"
done < <(iter_rule_lists "$CUSTOM_IP_DIR")

if [ "$has_custom_domain" -gt 0 ] || [ "$has_custom_ip" -gt 0 ]; then
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
