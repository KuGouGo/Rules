#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

sync_repo() {
  local dir="$1"
  local url="$2"
  local branch="$3"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --depth=1 origin "$branch"
    git -C "$dir" reset --hard "origin/$branch"
  else
    rm -rf "$dir"
    git clone --depth=1 --branch "$branch" "$url" "$dir"
  fi
}

sync_repo "$ROOT/sources/domain" "https://github.com/nekolsd/sing-geosite.git" "main"
sync_repo "$ROOT/sources/ip" "https://github.com/nekolsd/geoip.git" "master"

rm -rf "$ROOT/sources/domain/surge" "$ROOT/sources/domain/sing-box" "$ROOT/sources/domain/mihomo"
rm -rf "$ROOT/sources/ip/surge" "$ROOT/sources/ip/sing-box" "$ROOT/sources/ip/mihomo"

echo "upstream sync done"