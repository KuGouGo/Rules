#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$ROOT/.tmp/upstream"
mkdir -p "$TMP_DIR"

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

sync_repo "$ROOT/sources/geosite" "https://github.com/nekolsd/sing-geosite.git"
sync_repo "$ROOT/sources/geoip" "https://github.com/nekolsd/geoip.git"

echo "upstream sync done"
