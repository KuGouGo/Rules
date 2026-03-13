#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$ROOT/.tmp/domain-mihomo-input"
CUSTOM_TMP_DIR="$ROOT/.tmp/domain-custom-plain"
rm -rf domain "$TMP_DIR" "$CUSTOM_TMP_DIR"
mkdir -p domain/surge domain/sing-box domain/mihomo "$TMP_DIR" "$CUSTOM_TMP_DIR"

# Build surge rules from source
pushd sources/domain >/dev/null
go run .
cp -R domain-set/. "$ROOT/domain/surge/"
cp -R domain-set/. "$TMP_DIR/"
popd >/dev/null

# Download pre-built sing-box .srs from upstream rule-set branch
echo "Downloading sing-box .srs from upstream rule-set branch..."
TMP_RULESET="$ROOT/.tmp/sing-geosite-ruleset"
rm -rf "$TMP_RULESET"
git clone --depth=1 --branch rule-set https://github.com/nekolsd/sing-geosite.git "$TMP_RULESET"
cp -R "$TMP_RULESET/." "$ROOT/domain/sing-box/"
rm -rf "$TMP_RULESET"

# Convert custom *.list files to Surge DOMAIN-SET and plain domain files.
chmod +x "$ROOT/scripts/convert-custom-list.sh"
"$ROOT/scripts/convert-custom-list.sh" "$CUSTOM_TMP_DIR"

# Custom plain domain files join mihomo source inputs.
cp -f "$CUSTOM_TMP_DIR"/*.txt "$TMP_DIR/" 2>/dev/null || true

echo "domain build done"