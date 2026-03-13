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

# IP source: geoip master for build scripts
sync_repo "$ROOT/sources/ip" "https://github.com/nekolsd/geoip.git" "master"

# Domain source: we download dlc.dat directly from releases, no git clone needed
echo "Domain source: dlc.dat will be downloaded during build"

echo "upstream sync done"