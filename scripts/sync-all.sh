#!/usr/bin/env bash
# Sync upstream pre-built files only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_BASE="$ROOT/.tmp/sync"
rm -rf "$TMP_BASE"
mkdir -p "$TMP_BASE"

mkdir -p domain ip

echo "=== SYNC START ==="

# Domain surge from sing-geosite/domain-set
rm -rf domain/surge
mkdir -p "$TMP_BASE/domain-set"
git clone --depth=1 --branch domain-set https://github.com/nekolsd/sing-geosite.git "$TMP_BASE/domain-set"
cp -R "$TMP_BASE/domain-set/." domain/surge
rm -rf domain/surge/.git domain/surge/.github

# Domain sing-box from sing-geosite/rule-set
rm -rf domain/sing-box
mkdir -p "$TMP_BASE/rule-set"
git clone --depth=1 --branch rule-set https://github.com/nekolsd/sing-geosite.git "$TMP_BASE/rule-set"
cp -R "$TMP_BASE/rule-set/." domain/sing-box
rm -rf domain/sing-box/.git domain/sing-box/.github

# Domain mihomo: temporary compatibility copy from surge txt
rm -rf domain/mihomo
mkdir -p domain/mihomo
cp domain/surge/*.txt domain/mihomo/

# IP from geoip/release
rm -rf ip/surge ip/sing-box ip/mihomo
mkdir -p "$TMP_BASE/geoip"
git clone --depth=1 --branch release https://github.com/nekolsd/geoip.git "$TMP_BASE/geoip"
cp -R "$TMP_BASE/geoip/surge" ip/surge
cp -R "$TMP_BASE/geoip/srs" ip/sing-box
cp -R "$TMP_BASE/geoip/mrs" ip/mihomo
rm -rf ip/surge/.git ip/sing-box/.git ip/mihomo/.git

rm -rf "$TMP_BASE"

echo "=== SYNC DONE ==="
