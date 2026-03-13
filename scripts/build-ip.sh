#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf ip
mkdir -p ip/surge ip/sing-box ip/mihomo input

# Download GeoIP MMDB for building surge/mihomo rules
curl -L https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb -o input/Country.mmdb

# Build surge and mihomo rules from source
pushd sources/ip >/dev/null
rm -rf output
go run . convert -c "$ROOT/configs/geoip-convert.json"
cp -R output/surge/. "$ROOT/ip/surge/"
cp -R output/mihomo/. "$ROOT/ip/mihomo/"
popd >/dev/null

# Download pre-built sing-box .srs from upstream release branch
echo "Downloading sing-box .srs from upstream release..."
TMP_RELEASE="$ROOT/.tmp/geoip-release"
rm -rf "$TMP_RELEASE"
git clone --depth=1 --branch release https://github.com/nekolsd/geoip.git "$TMP_RELEASE"
cp -R "$TMP_RELEASE/srs/." "$ROOT/ip/sing-box/"
rm -rf "$TMP_RELEASE"

echo "ip build done"