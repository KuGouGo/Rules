#!/usr/bin/env bash
# Sync upstream pre-built files only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_BASE="$ROOT/.tmp/sync"
BIN_DIR="$ROOT/.bin"
DOMAIN_TMP_DIR="$TMP_BASE/domain-build"
IP_TMP_DIR="$TMP_BASE/ip-build"
ARTIFACT_ROOT="$ROOT/.output"
DOMAIN_ROOT="$ARTIFACT_ROOT/domain"
IP_ROOT="$ARTIFACT_ROOT/ip"

source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/lib/rules.sh"

rm -rf "$TMP_BASE"
mkdir -p "$TMP_BASE" "$BIN_DIR" "$DOMAIN_TMP_DIR" "$IP_TMP_DIR"
trap 'rm -rf "$TMP_BASE"' EXIT

mkdir -p "$DOMAIN_ROOT" "$IP_ROOT"

echo "=== SYNC START ==="

clone_branch() {
  local repo="$1"
  local branch="$2"
  local dest="$3"
  git clone --depth=1 --single-branch --branch "$branch" "$repo" "$dest"
}

copy_txt_tree_as_list() {
  local src_dir="$1"
  local dest_dir="$2"
  local file

  mkdir -p "$dest_dir"
  cp -R "$src_dir"/. "$dest_dir"
  rm -rf "$dest_dir/.git"

  for file in "$dest_dir"/*.txt; do
    [ -f "$file" ] || continue
    mv "$file" "${file%.txt}.list"
  done
}

require_files() {
  local label="$1"
  local glob="$2"
  if ! compgen -G "$glob" >/dev/null; then
    echo "$label is empty: $glob" >&2
    exit 1
  fi
}

merge_cn_operator_lists() {
  local cn_file="$IP_ROOT/surge/cn.list"
  local merged_file="$IP_TMP_DIR/cn.list"
  local operator_files=(
    "$IP_ROOT/surge/cncm.list"
    "$IP_ROOT/surge/cnct.list"
    "$IP_ROOT/surge/cncu.list"
  )
  local existing_sources=("$cn_file")
  local file

  for file in "${operator_files[@]}"; do
    if [ -f "$file" ]; then
      existing_sources+=("$file")
    fi
  done

  awk '!seen[$0]++' "${existing_sources[@]}" > "$merged_file"
  mv "$merged_file" "$cn_file"
  rm -f "${operator_files[@]}"
}

# Domain surge from sing-geosite/domain-set
rm -rf "$DOMAIN_ROOT/surge"
clone_branch https://github.com/nekolsd/sing-geosite.git domain-set "$TMP_BASE/domain-set"
copy_txt_tree_as_list "$TMP_BASE/domain-set" "$DOMAIN_ROOT/surge"
require_files "$DOMAIN_ROOT/surge" "$DOMAIN_ROOT/surge/*.list"

# Domain sing-box and mihomo built locally from the same surge domain-set text
build_domain_artifacts_from_surge_dir \
  "$DOMAIN_ROOT/surge" \
  "$DOMAIN_TMP_DIR" \
  "$DOMAIN_ROOT/sing-box" \
  "$DOMAIN_ROOT/mihomo"
require_files "$DOMAIN_ROOT/sing-box" "$DOMAIN_ROOT/sing-box/*.srs"
require_files "$DOMAIN_ROOT/mihomo" "$DOMAIN_ROOT/mihomo/*.mrs"

# IP from geoip/release
rm -rf "$IP_ROOT/surge" "$IP_ROOT/sing-box" "$IP_ROOT/mihomo"
clone_branch https://github.com/nekolsd/geoip.git release "$TMP_BASE/geoip"
copy_txt_tree_as_list "$TMP_BASE/geoip/surge" "$IP_ROOT/surge"
merge_cn_operator_lists
require_files "$IP_ROOT/surge" "$IP_ROOT/surge/*.list"
build_ip_artifacts_from_surge_dir \
  "$IP_ROOT/surge" \
  "$IP_TMP_DIR" \
  "$IP_ROOT/sing-box" \
  "$IP_ROOT/mihomo"
require_files "$IP_ROOT/sing-box" "$IP_ROOT/sing-box/*.srs"
require_files "$IP_ROOT/mihomo" "$IP_ROOT/mihomo/*.mrs"

echo "=== SYNC DONE ==="
