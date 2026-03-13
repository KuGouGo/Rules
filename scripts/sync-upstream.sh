#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$ROOT/.tmp"
UPSTREAM_DIR="$TMP_DIR/upstream"
mkdir -p "$UPSTREAM_DIR"

sync_repo() {
  local name="$1"
  local url="$2"
  local dir="$UPSTREAM_DIR/$name"

  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --depth=1 origin
    git -C "$dir" reset --hard origin/HEAD
  else
    rm -rf "$dir"
    git clone --depth=1 "$url" "$dir"
  fi
}

sync_repo "geosite-src" "https://github.com/nekolsd/sing-geosite.git"
sync_repo "geoip-src" "https://github.com/nekolsd/geoip.git"

rm -rf geosite geoip
mkdir -p geosite/mihomo geosite/surge geosite/sing-box
mkdir -p geoip/mihomo geoip/surge geoip/sing-box

cp -R "$UPSTREAM_DIR/geosite-src"/. geosite-src
cp -R "$UPSTREAM_DIR/geoip-src"/. geoip-src

# keep source snapshots for reference
rm -rf geosite-source geoip-source
mv geosite-src geosite-source
mv geoip-src geoip-source

# preserve custom rules
mkdir -p custom-rules

echo "upstream sync prepared"
echo "note: workflow should build artifacts into geosite/* and geoip/* afterwards"
