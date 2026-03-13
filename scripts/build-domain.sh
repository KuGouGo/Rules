#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf domain
mkdir -p domain/surge domain/sing-box domain/mihomo-text domain/mihomo

pushd sources/domain >/dev/null
go run .
cp -R domain-set/. "$ROOT/domain/surge/"
cp -R rule-set/. "$ROOT/domain/sing-box/"
cp -R domain-set/. "$ROOT/domain/mihomo-text/"
popd >/dev/null

echo "domain build done"
