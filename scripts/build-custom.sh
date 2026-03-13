#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p domain/custom-surge domain/custom-sing-box domain/custom-mihomo .tmp/custom .bin
rm -f domain/custom-surge/* domain/custom-sing-box/* domain/custom-mihomo/* .tmp/custom/*

# convert *.list -> custom-surge + plain list
for lf in sources/domain/custom/*.list; do
  [ -f "$lf" ] || continue
  base="$(basename "$lf" .list)"
  surgeOut="$ROOT/domain/custom-surge/$base.txt"
  plainOut="$ROOT/.tmp/custom/$base.txt"
  awk -F, 'NF>=2 {
    type=$1; domain=$2;
    if (type=="DOMAIN") { print domain >> surge; print domain >> plain }
    else if (type=="DOMAIN-SUFFIX") { print "." domain >> surge; print domain >> plain }
  }' surge="$surgeOut" plain="$plainOut" "$lf"
done

# sing-box binary
if ! command -v sing-box >/dev/null 2>&1; then
  if [ ! -x "$ROOT/.bin/sing-box" ]; then
    VER="1.13.2"
    curl -Lo "$ROOT/.bin/sing-box.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-amd64.tar.gz"
    tar -xzf "$ROOT/.bin/sing-box.tar.gz" -C "$ROOT/.bin" --strip-components=1
    chmod +x "$ROOT/.bin/sing-box"
    rm -f "$ROOT/.bin/sing-box.tar.gz"
  fi
  export PATH="$ROOT/.bin:$PATH"
fi

# mihomo binary
if ! command -v mihomo >/dev/null 2>&1; then
  if [ ! -x "$ROOT/.bin/mihomo" ]; then
    curl -L "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-compatible-v1.19.21.gz" -o "$ROOT/.bin/mihomo.gz"
    gzip -df "$ROOT/.bin/mihomo.gz"
    chmod +x "$ROOT/.bin/mihomo"
  fi
  export PATH="$ROOT/.bin:$PATH"
fi

# plain -> custom-sing-box + custom-mihomo
for txt in .tmp/custom/*.txt; do
  [ -f "$txt" ] || continue
  base="$(basename "$txt" .txt)"
  json=".tmp/custom/$base.json"
  domains=$(awk 'NF {printf "\"%s\",", $0}' "$txt" | sed 's/,$//')
  cat > "$json" <<JSON
{"version":3,"rules":[{"domain_suffix":[$domains]}]}
JSON
  sing-box rule-set compile "$json" --output "$ROOT/domain/custom-sing-box/$base.srs"
  mihomo convert-ruleset domain text "$txt" "$ROOT/domain/custom-mihomo/$base.mrs" 2>/dev/null || cp "$txt" "$ROOT/domain/custom-mihomo/$base.txt"
done

echo "custom build done"
