#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p .bin domain/mihomo ip/mihomo

if ! command -v mihomo >/dev/null 2>&1; then
  if [ ! -x .bin/mihomo ]; then
    ARCHIVE_URL="https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-compatible-v1.19.21.gz"
    curl -L "$ARCHIVE_URL" -o .bin/mihomo.gz
    gzip -df .bin/mihomo.gz
    chmod +x .bin/mihomo
  fi
  export PATH="$ROOT/.bin:$PATH"
fi

convert_dir() {
  local behavior="$1"
  local input_dir="$2"
  local output_dir="$3"
  shopt -s nullglob
  for f in "$input_dir"/*.txt; do
    base="$(basename "$f" .txt)"
    mihomo convert-ruleset "$behavior" text "$f" "$output_dir/$base.mrs"
  done
}

convert_dir domain "$ROOT/domain/mihomo-text" "$ROOT/domain/mihomo"
convert_dir ipcidr "$ROOT/ip/mihomo-text" "$ROOT/ip/mihomo"

echo "mihomo mrs build done"
