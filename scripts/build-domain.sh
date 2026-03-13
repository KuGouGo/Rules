#!/usr/bin/env bash
# Build domain rules from nekolsd/not-sing-geosite (release branch)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf domain
mkdir -p domain/surge domain/sing-box domain/mihomo

# Get surge files from not-sing-geosite release
echo "Getting surge files from upstream..."
TMP_NS="$ROOT/.tmp/not-sing-geosite"
rm -rf "$TMP_NS"
git clone --depth=1 --branch release https://github.com/nekolsd/not-sing-geosite.git "$TMP_NS"
cp -R "$TMP_NS/surge/." "$ROOT/domain/surge/"
rm -rf "$TMP_NS"

# Get sing-box .srs from sing-geosite rule-set branch (still needed)
echo "Getting sing-box .srs from upstream..."
TMP_RS="$ROOT/.tmp/sing-geosite-rs"
rm -rf "$TMP_RS"
git clone --depth=1 --branch rule-set https://github.com/nekolsd/sing-geosite.git "$TMP_RS"
cp -R "$TMP_RS/." "$ROOT/domain/sing-box/"
rm -rf "$TMP_RS"

# Setup mihomo
mkdir -p "$ROOT/.bin"
if ! command -v mihomo >/dev/null 2>&1; then
  curl -L "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-compatible-v1.19.21.gz" -o "$ROOT/.bin/mihomo.gz"
  gzip -df "$ROOT/.bin/mihomo.gz"
  chmod +x "$ROOT/.bin/mihomo"
fi
export PATH="$ROOT/.bin:$PATH"

# Generate mihomo .mrs from surge files
echo "Generating mihomo .mrs..."
for f in "$ROOT/domain/surge"/*.txt; do
  [ -f "$f" ] || continue
  base=$(basename "$f" .txt)
  mihomo convert-ruleset domain text "$f" "$ROOT/domain/mihomo/$base.mrs" 2>/dev/null || \
    cp "$f" "$ROOT/domain/mihomo/$base.txt"
done

# Custom rules
echo "Adding custom rules..."
for lf in "$ROOT/sources/domain/custom"/*.list; do
  [ -f "$lf" ] || continue
  base=$(basename "$lf" .list)
  awk -F, 'NF>=2{print $2}' "$lf" >> "$ROOT/domain/surge/$base.txt"
done

echo "Done"