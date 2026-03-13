#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf ip
mkdir -p ip/surge ip/sing-box ip/mihomo input

curl -L https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb -o input/Country.mmdb

cd sources/ip
go run . convert -c ../../configs/geoip-convert.json

cp -R dist/geoip/surge/. ../../ip/surge/
cp -R dist/geoip/sing-box/. ../../ip/sing-box/
cp -R dist/geoip/mihomo/. ../../ip/mihomo/

echo "ip build done"
