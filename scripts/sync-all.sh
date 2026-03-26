#!/usr/bin/env bash
# Sync upstream pre-built files only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_BASE="$ROOT/.tmp/sync"
BIN_DIR="$ROOT/.bin"
IP_TMP_DIR="$TMP_BASE/ip-build"
ARTIFACT_ROOT="$ROOT/.output"
DOMAIN_ROOT="$ARTIFACT_ROOT/domain"
IP_ROOT="$ARTIFACT_ROOT/ip"

source "$ROOT/scripts/lib/common.sh"

rm -rf "$TMP_BASE"
mkdir -p "$TMP_BASE" "$BIN_DIR" "$IP_TMP_DIR"
trap 'rm -rf "$TMP_BASE"' EXIT

mkdir -p "$DOMAIN_ROOT" "$IP_ROOT"

echo "=== SYNC START ==="

clone_branch() {
  local repo="$1"
  local branch="$2"
  local dest="$3"
  git clone --depth=1 --single-branch --branch "$branch" "$repo" "$dest"
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

build_ip_binaries_from_surge() {
  ensure_sing_box
  ensure_mihomo
  rm -rf "$IP_ROOT/sing-box" "$IP_ROOT/mihomo"
  mkdir -p "$IP_ROOT/sing-box" "$IP_ROOT/mihomo"

  local list base plain_txt json srs_out mrs_out cidrs
  for list in "$IP_ROOT"/surge/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    plain_txt="$IP_TMP_DIR/$base.txt"
    json="$IP_TMP_DIR/$base.json"
    srs_out="$IP_ROOT/sing-box/$base.srs"
    mrs_out="$IP_ROOT/mihomo/$base.mrs"

    awk -F, '
      /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
      $1 == "IP-CIDR" || $1 == "IP-CIDR6" {
        value=$2
        gsub(/\r$/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value != "") print value
      }
    ' "$list" > "$plain_txt"

    cidrs="$(awk 'NF { printf "\"%s\",", $0 }' "$plain_txt" | sed 's/,$//')"
    cat > "$json" <<JSON
{"version":3,"rules":[{"ip_cidr":[${cidrs}]}]}
JSON

    sing-box rule-set compile "$json" --output "$srs_out"
    mihomo convert-ruleset ipcidr text "$plain_txt" "$mrs_out" >/dev/null 2>&1
  done

  require_files "$IP_ROOT/sing-box" "$IP_ROOT/sing-box/*.srs"
  require_files "$IP_ROOT/mihomo" "$IP_ROOT/mihomo/*.mrs"
}

build_mihomo_from_surge() {
  ensure_mihomo
  rm -rf "$DOMAIN_ROOT/mihomo"
  mkdir -p "$DOMAIN_ROOT/mihomo"

  local list base out
  for list in "$DOMAIN_ROOT"/surge/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    out="$DOMAIN_ROOT/mihomo/$base.mrs"
    mihomo convert-ruleset domain text "$list" "$out" >/dev/null 2>&1
  done

  require_files "$DOMAIN_ROOT/mihomo" "$DOMAIN_ROOT/mihomo/*.mrs"
}

# Domain surge from sing-geosite/domain-set
rm -rf "$DOMAIN_ROOT/surge"
clone_branch https://github.com/nekolsd/sing-geosite.git domain-set "$TMP_BASE/domain-set"
mkdir -p "$DOMAIN_ROOT/surge"
cp -R "$TMP_BASE/domain-set"/. "$DOMAIN_ROOT/surge"
rm -rf "$DOMAIN_ROOT/surge/.git" "$DOMAIN_ROOT/surge/.github"
for file in "$DOMAIN_ROOT"/surge/*.txt; do
  [ -f "$file" ] || continue
  mv "$file" "${file%.txt}.list"
done
require_files "$DOMAIN_ROOT/surge" "$DOMAIN_ROOT/surge/*.list"

# Domain sing-box from sing-geosite/rule-set
rm -rf "$DOMAIN_ROOT/sing-box"
clone_branch https://github.com/nekolsd/sing-geosite.git rule-set "$TMP_BASE/rule-set"
mkdir -p "$DOMAIN_ROOT/sing-box"
cp -R "$TMP_BASE/rule-set"/. "$DOMAIN_ROOT/sing-box"
rm -rf "$DOMAIN_ROOT/sing-box/.git" "$DOMAIN_ROOT/sing-box/.github"
require_files "$DOMAIN_ROOT/sing-box" "$DOMAIN_ROOT/sing-box/*.srs"

# Domain mihomo built locally from surge domain-set text
build_mihomo_from_surge

# IP from geoip/release
rm -rf "$IP_ROOT/surge" "$IP_ROOT/sing-box" "$IP_ROOT/mihomo"
clone_branch https://github.com/nekolsd/geoip.git release "$TMP_BASE/geoip"
cp -R "$TMP_BASE/geoip/surge" "$IP_ROOT/surge"
rm -rf "$IP_ROOT/surge/.git"
for file in "$IP_ROOT"/surge/*.txt; do
  [ -f "$file" ] || continue
  mv "$file" "${file%.txt}.list"
done
merge_cn_operator_lists
require_files "$IP_ROOT/surge" "$IP_ROOT/surge/*.list"
build_ip_binaries_from_surge

echo "=== SYNC DONE ==="
