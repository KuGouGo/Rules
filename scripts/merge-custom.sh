#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p output/custom/domain output/custom/ip
cp -f custom/domain/*.list output/custom/domain/ 2>/dev/null || true
cp -f custom/ip/*.list output/custom/ip/ 2>/dev/null || true

echo "custom rules copied"
