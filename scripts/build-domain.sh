#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf domain
mkdir -p domain/surge domain/sing-box domain/mihomo

cd sources/domain
go run .
cp -R domain-set/. ../../domain/surge/
cp -R rule-set/. ../../domain/sing-box/
cp -R domain-set/. ../../domain/mihomo/

echo "domain build done"
