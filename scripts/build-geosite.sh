#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf output/geosite
mkdir -p output/geosite/surge output/geosite/sing-box output/geosite/mihomo

cd sources/geosite
go run .
cp -R domain-set/. ../../output/geosite/surge/
cp -R rule-set/. ../../output/geosite/sing-box/
cp -R domain-set/. ../../output/geosite/mihomo/

echo "geosite build done"
