#!/usr/bin/env bash
# Super simple: just copy upstream pre-built files
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== SYNC START ==="

# Domain Surge files - from not-sing-geosite release
echo "Cloning surge files..."
rm -rf domain/surge
git clone --depth=1 --branch release https://github.com/nekolsd/not-sing-geosite.git /tmp/nsg
cp -R /tmp/nsg/surge domain/surge
rm -rf /tmp/nsg

# Domain sing-box files - from sing-geosite rule-set  
echo "Cloning sing-box files..."
rm -rf domain/sing-box
git clone --depth=1 --branch rule-set https://github.com/nekolsd/sing-geosite.git /tmp/srs
cp -R /tmp/srs domain/sing-box
rm -rf /tmp/srs

# Domain mihomo - copy surge files as txt (mihomo can use txt)
echo "Setting up mihomo..."
mkdir -p domain/mihomo
cp domain/surge/*.txt domain/mihomo/

# IP files - from geoip release
echo "Cloning IP files..."
rm -rf ip/surge ip/sing-box ip/mihomo
git clone --depth=1 --branch release https://github.com/nekolsd/geoip.git /tmp/geoip
cp -R /tmp/geoip/surge ip/surge
cp -R /tmp/geoip/srs ip/sing-box
cp -R /tmp/geoip/mrs ip/mihomo
rm -rf /tmp/geoip

echo "=== SYNC DONE ==="