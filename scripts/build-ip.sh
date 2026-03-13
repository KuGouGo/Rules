#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$ROOT/.tmp/ip-mihomo-input"
rm -rf ip "$TMP_DIR"
mkdir -p ip/surge ip/sing-box ip/mihomo input "$TMP_DIR"

curl -L https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb -o input/Country.mmdb

pushd sources/ip >/dev/null
rm -rf output
go run . convert -c "$ROOT/configs/geoip-convert.json"
cp -R output/surge/. "$ROOT/ip/surge/"
cp -R output/sing-box/. "$ROOT/ip/sing-box/"
cp -R output/mihomo/. "$TMP_DIR/"
popd >/dev/null

echo "ip build done"
