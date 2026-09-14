#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

rm -rf .tmp .output
rm -f .bin/*.download .bin/*.download.*
find scripts -type d -name __pycache__ -prune -exec rm -rf {} +

echo "cleaned generated artifacts"
