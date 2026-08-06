#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

rm -rf .tmp .output .artifacts
rm -f .bin/*.new .bin/*.new.* .bin/.*.provenance.* .bin/sing-box.new.tar.gz .bin/mihomo.new.gz
find scripts -type d -name __pycache__ -prune -exec rm -rf {} +

echo "cleaned generated artifacts"
