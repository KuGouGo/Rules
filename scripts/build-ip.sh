#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf output/ip
mkdir -p output/ip/surge output/ip/sing-box output/ip/mihomo input

curl -L https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb -o input/Country.mmdb

cd sources/ip
go run . convert -c ../../configs/geoip-convert.json

cp -R dist/geoip/surge/. ../../output/ip/surge/
cp -R dist/geoip/sing-box/. ../../output/ip/sing-box/
cp -R dist/geoip/mihomo/. ../../output/ip/mihomo/

echo "ip build done"
