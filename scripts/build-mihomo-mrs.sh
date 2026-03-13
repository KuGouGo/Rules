#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DOMAIN_INPUT_DIR="$ROOT/.tmp/domain-mihomo-input"
IP_INPUT_DIR="$ROOT/.tmp/ip-mihomo-input"

mkdir -p .bin domain/mihomo ip/mihomo
rm -rf domain/mihomo/* ip/mihomo/*

if ! command -v mihomo >/dev/null 2>&1; then
  if [ ! -x .bin/mihomo ]; then
    ARCHIVE_URL="https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-compatible-v1.19.21.gz"
    curl -L "$ARCHIVE_URL" -o .bin/mihomo.gz
    gzip -df .bin/mihomo.gz
    chmod +x .bin/mihomo
  fi
  export PATH="$ROOT/.bin:$PATH"
fi

convert_domain_dir() {
  local input_dir="$1"
  local output_dir="$2"
  shopt -s nullglob
  for f in "$input_dir"/*.txt; do
    base="$(basename "$f" .txt)"
    mihomo convert-ruleset domain text "$f" "$output_dir/$base.mrs"
  done
}

convert_ip_dir() {
  local input_dir="$1"
  local output_dir="$2"
  shopt -s nullglob
  for f in "$input_dir"/*; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in
      *.txt)
        out="${base%.txt}.mrs"
        mihomo convert-ruleset ipcidr text "$f" "$output_dir/$out"
        ;;
      *.yaml)
        out="${base%.yaml}.mrs"
        mihomo convert-ruleset ipcidr yaml "$f" "$output_dir/$out"
        ;;
      *.mrs)
        cp -f "$f" "$output_dir/$base"
        ;;
    esac
  done
}

convert_domain_dir "$DOMAIN_INPUT_DIR" "$ROOT/domain/mihomo"
convert_ip_dir "$IP_INPUT_DIR" "$ROOT/ip/mihomo"

echo "mihomo mrs build done"
