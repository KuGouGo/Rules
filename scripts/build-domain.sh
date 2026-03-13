#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$ROOT/.tmp/domain-mihomo-input"
rm -rf domain "$TMP_DIR"
mkdir -p domain/surge domain/sing-box domain/mihomo "$TMP_DIR"

pushd sources/domain >/dev/null
go run .
cp -R domain-set/. "$ROOT/domain/surge/"
cp -R rule-set/. "$ROOT/domain/sing-box/"
cp -R domain-set/. "$TMP_DIR/"
popd >/dev/null

echo "domain build done"
