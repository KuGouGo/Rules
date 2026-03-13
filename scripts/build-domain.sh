#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf output/domain
mkdir -p output/domain/surge output/domain/sing-box output/domain/mihomo

cd sources/domain
go run .
cp -R domain-set/. ../../output/domain/surge/
cp -R rule-set/. ../../output/domain/sing-box/
cp -R domain-set/. ../../output/domain/mihomo/

echo "domain build done"
