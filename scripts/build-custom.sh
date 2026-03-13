#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p domain/mihomo

# Ensure mihomo binary
if ! command -v mihomo >/dev/null 2>&1; then
  if [ ! -x "$ROOT/.bin/mihomo" ]; then
    mkdir -p "$ROOT/.bin"
    ARCHIVE_URL="https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-compatible-v1.19.21.gz"
    curl -L "$ARCHIVE_URL" -o "$ROOT/.bin/mihomo.gz"
    gzip -df "$ROOT/.bin/mihomo.gz"
    chmod +x "$ROOT/.bin/mihomo"
  fi
  export PATH="$ROOT/.bin:$PATH"
fi

# Convert custom domain lists to .mrs
for src in sources/domain/custom/*-domain.txt; do
  [ -f "$src" ] || continue
  base="$(basename "$src" -domain.txt)"
  mihomo convert-ruleset domain text "$src" "$ROOT/domain/mihomo/$base.mrs"
done

echo "custom domain rules converted"