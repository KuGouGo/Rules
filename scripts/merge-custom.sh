#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p output/custom
cp -f custom/domain/*.list output/custom/ 2>/dev/null || true

echo "custom rules copied"
