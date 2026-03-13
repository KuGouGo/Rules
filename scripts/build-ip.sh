#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf ip
mkdir -p ip/surge ip/sing-box ip/mihomo-input ip/mihomo input

curl -L https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb -o input/Country.mmdb

pushd sources/ip >/dev/null
rm -rf output
go run . convert -c "$ROOT/configs/geoip-convert.json"
cp -R output/surge/. "$ROOT/ip/surge/"
cp -R output/sing-box/. "$ROOT/ip/sing-box/"
cp -R output/mihomo/. "$ROOT/ip/mihomo-input/"
popd >/dev/null

echo "ip build done"
