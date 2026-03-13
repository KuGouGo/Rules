#!/usr/bin/env bash
# Super simple: just copy upstream pre-built files
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_BASE="$ROOT/.tmp/sync"
rm -rf "$TMP_BASE"
mkdir -p "$TMP_BASE"

echo "=== SYNC START ==="

mkdir -p domain ip

# Domain Surge files - from not-sing-geosite release
echo "Cloning surge files..."
rm -rf domain/surge
mkdir -p "$TMP_BASE/nsg"
git clone --depth=1 --branch release https://github.com/nekolsd/not-sing-geosite.git "$TMP_BASE/nsg"
cp -R "$TMP_BASE/nsg/surge" domain/surge

# Domain sing-box files - from sing-geosite rule-set
echo "Cloning sing-box files..."
rm -rf domain/sing-box
mkdir -p "$TMP_BASE/srs"
git clone --depth=1 --branch rule-set https://github.com/nekolsd/sing-geosite.git "$TMP_BASE/srs"
cp -R "$TMP_BASE/srs" domain/sing-box
rm -rf domain/sing-box/.git

# Domain mihomo - copy surge files as txt (temporary compatibility mode)
echo "Setting up mihomo..."
rm -rf domain/mihomo
mkdir -p domain/mihomo
cp domain/surge/*.txt domain/mihomo/

# IP files - from geoip release
echo "Cloning IP files..."
rm -rf ip/surge ip/sing-box ip/mihomo
mkdir -p "$TMP_BASE/geoip"
git clone --depth=1 --branch release https://github.com/nekolsd/geoip.git "$TMP_BASE/geoip"
cp -R "$TMP_BASE/geoip/surge" ip/surge
cp -R "$TMP_BASE/geoip/srs" ip/sing-box
cp -R "$TMP_BASE/geoip/mrs" ip/mihomo
rm -rf ip/sing-box/.git ip/mihomo/.git ip/surge/.git

rm -rf "$TMP_BASE"

echo "=== SYNC DONE ==="