#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cp -f sources/domain/custom/*.list domain/surge/ 2>/dev/null || true

echo "custom rules copied"
