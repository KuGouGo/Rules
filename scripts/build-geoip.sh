#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf output/geoip
mkdir -p output/geoip/surge output/geoip/sing-box output/geoip/mihomo input

curl -L https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb -o input/Country.mmdb

cd sources/geoip
go run . convert -c ../../configs/geoip-convert.json

cp -R dist/geoip/surge/. ../../output/geoip/surge/
cp -R dist/geoip/sing-box/. ../../output/geoip/sing-box/
cp -R dist/geoip/mihomo/. ../../output/geoip/mihomo/

echo "geoip build done"
