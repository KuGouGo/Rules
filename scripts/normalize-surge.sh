#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

normalize_domain_dir() {
  local dir="$1"
  shopt -s nullglob
  for f in "$dir"/*.txt; do
    tmp="${f}.tmp"
    awk 'NF {print "DOMAIN-SUFFIX," $0}' "$f" > "$tmp"
    mv "$tmp" "$f"
  done
}

normalize_ip_dir() {
  local dir="$1"
  shopt -s nullglob
  for f in "$dir"/*.txt; do
    tmp="${f}.tmp"
    awk 'NF && $1 !~ /^#/ { if ($0 ~ /^IP-CIDR,/) print $0 ",no-resolve"; else print $0 }' "$f" > "$tmp"
    mv "$tmp" "$f"
  done
}

normalize_domain_dir "$ROOT/domain/surge"
normalize_ip_dir "$ROOT/ip/surge"

echo "surge rules normalized"
