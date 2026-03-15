#!/usr/bin/env bash
# Sync upstream pre-built files only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_BASE="$ROOT/.tmp/sync"
BIN_DIR="$ROOT/.bin"
rm -rf "$TMP_BASE"
mkdir -p "$TMP_BASE" "$BIN_DIR"
trap 'rm -rf "$TMP_BASE"' EXIT

mkdir -p domain ip

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

ensure_mihomo() {
  if command -v mihomo >/dev/null 2>&1; then
    return 0
  fi

  if [ ! -x "$BIN_DIR/mihomo" ] && [ ! -x "$BIN_DIR/mihomo.exe" ]; then
    local raw_os os arch asset archive
    raw_os="$(uname -s)"
    os="$(printf '%s' "$raw_os" | tr '[:upper:]' '[:lower:]')"
    case "$raw_os" in
      MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    esac
    arch="$(uname -m)"
    if [ "$os" = "windows" ]; then
      case "$arch" in
        x86_64) asset="mihomo-windows-amd64-compatible-v1.19.21.zip" ;;
        arm64|aarch64) asset="mihomo-windows-arm64-v1.19.21.zip" ;;
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
      esac
      archive="$BIN_DIR/mihomo.zip"
      curl -fL -o "$archive" "https://github.com/MetaCubeX/mihomo/releases/latest/download/${asset}"
      unzip -oq "$archive" -d "$BIN_DIR/mihomo-extract"
      mv "$BIN_DIR/mihomo-extract/mihomo.exe" "$BIN_DIR/mihomo.exe"
      chmod +x "$BIN_DIR/mihomo.exe"
      rm -rf "$BIN_DIR/mihomo-extract" "$archive"
    else
      case "$arch" in
        x86_64) asset="mihomo-${os}-amd64-compatible-v1.19.21.gz" ;;
        arm64|aarch64) asset="mihomo-${os}-arm64-v1.19.21.gz" ;;
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
      esac
      archive="$BIN_DIR/mihomo.gz"
      curl -fL -o "$archive" "https://github.com/MetaCubeX/mihomo/releases/latest/download/${asset}"
      gzip -df "$archive"
      chmod +x "$BIN_DIR/mihomo"
    fi
  fi

  export PATH="$BIN_DIR:$PATH"
}

build_mihomo_from_surge() {
  ensure_mihomo
  rm -rf domain/mihomo
  mkdir -p domain/mihomo

  local list base out
  for list in domain/surge/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    out="domain/mihomo/$base.mrs"
    mihomo convert-ruleset domain text "$list" "$out" >/dev/null 2>&1
  done

  require_files "domain/mihomo" "domain/mihomo/*.mrs"
}

# Domain surge from sing-geosite/domain-set
rm -rf domain/surge
clone_branch https://github.com/nekolsd/sing-geosite.git domain-set "$TMP_BASE/domain-set"
mkdir -p domain/surge
cp -R "$TMP_BASE/domain-set"/. domain/surge
rm -rf domain/surge/.git domain/surge/.github
for file in domain/surge/*.txt; do
  [ -f "$file" ] || continue
  mv "$file" "${file%.txt}.list"
done
require_files "domain/surge" "domain/surge/*.list"

# Domain sing-box from sing-geosite/rule-set
rm -rf domain/sing-box
clone_branch https://github.com/nekolsd/sing-geosite.git rule-set "$TMP_BASE/rule-set"
mkdir -p domain/sing-box
cp -R "$TMP_BASE/rule-set"/. domain/sing-box
rm -rf domain/sing-box/.git domain/sing-box/.github
require_files "domain/sing-box" "domain/sing-box/*.srs"

# Domain mihomo built locally from surge domain-set text
build_mihomo_from_surge

# IP from geoip/release
rm -rf ip/surge ip/sing-box ip/mihomo
clone_branch https://github.com/nekolsd/geoip.git release "$TMP_BASE/geoip"
cp -R "$TMP_BASE/geoip/surge" ip/surge
cp -R "$TMP_BASE/geoip/srs" ip/sing-box
cp -R "$TMP_BASE/geoip/mrs" ip/mihomo
rm -rf ip/surge/.git ip/sing-box/.git ip/mihomo/.git
for file in ip/surge/*.txt; do
  [ -f "$file" ] || continue
  mv "$file" "${file%.txt}.list"
done
require_files "ip/surge" "ip/surge/*.list"
require_files "ip/sing-box" "ip/sing-box/*.srs"
require_files "ip/mihomo" "ip/mihomo/*.mrs"

echo "=== SYNC DONE ==="
