#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

sync_repo() {
  local name="$1"
  local url="$2"

  if [ -d "$name/.git" ]; then
    git -C "$name" fetch --depth=1 origin
    git -C "$name" reset --hard origin/HEAD
  else
    git clone --depth=1 "$url" "$name"
  fi
}

sync_repo "sing-geosite" "https://github.com/nekolsd/sing-geosite.git"
sync_repo "geoip" "https://github.com/nekolsd/geoip.git"

echo "upstream sync done"
