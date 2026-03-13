#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p custom/domain custom/ip
cp -f custom/domain/*.list domain/surge/ 2>/dev/null || true
cp -f custom/ip/*.list ip/surge/ 2>/dev/null || true

echo "custom rules copied"
