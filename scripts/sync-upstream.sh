#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DOMAIN_CUSTOM_TMP=""
IP_CUSTOM_TMP=""

if [ -d "$ROOT/sources/domain/custom" ]; then
  DOMAIN_CUSTOM_TMP="$(mktemp -d)"
  cp -R "$ROOT/sources/domain/custom/." "$DOMAIN_CUSTOM_TMP/"
fi

if [ -d "$ROOT/sources/ip/custom" ]; then
  IP_CUSTOM_TMP="$(mktemp -d)"
  cp -R "$ROOT/sources/ip/custom/." "$IP_CUSTOM_TMP/"
fi

sync_repo() {
  local dir="$1"
  local url="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --depth=1 origin
    git -C "$dir" reset --hard origin/HEAD
  else
    rm -rf "$dir"
    git clone --depth=1 "$url" "$dir"
  fi
}

sync_repo "$ROOT/sources/domain" "https://github.com/nekolsd/sing-geosite.git"
sync_repo "$ROOT/sources/ip" "https://github.com/nekolsd/geoip.git"

rm -rf "$ROOT/sources/domain/surge" "$ROOT/sources/domain/sing-box" "$ROOT/sources/domain/mihomo"
rm -rf "$ROOT/sources/ip/surge" "$ROOT/sources/ip/sing-box" "$ROOT/sources/ip/mihomo"

mkdir -p "$ROOT/sources/domain/custom" "$ROOT/sources/ip/custom"

if [ -n "$DOMAIN_CUSTOM_TMP" ]; then
  cp -R "$DOMAIN_CUSTOM_TMP/." "$ROOT/sources/domain/custom/"
fi

if [ -n "$IP_CUSTOM_TMP" ]; then
  cp -R "$IP_CUSTOM_TMP/." "$ROOT/sources/ip/custom/"
fi

echo "upstream sync done"
