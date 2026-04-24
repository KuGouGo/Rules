#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

URL="https://raw.githubusercontent.com/wwqgtxx/clash-rules/release/fakeip-filter.mrs"
OUT=".output/domain/mihomo/fakeip-filter.mrs"
TMP="${OUT}.tmp"

mkdir -p "$(dirname "$OUT")"

curl --retry 3 --retry-all-errors --connect-timeout 20 --max-time 120 -fL "$URL" -o "$TMP"

if [ -f "$OUT" ] && cmp -s "$TMP" "$OUT"; then
  rm -f "$TMP"
  echo "fakeip-filter.mrs unchanged"
  exit 0
fi

mv "$TMP" "$OUT"
echo "updated $OUT"
