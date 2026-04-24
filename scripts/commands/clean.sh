#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

rm -rf .tmp .output
rm -f .bin/*.new .bin/*.new.* .bin/sing-box.new.tar.gz .bin/mihomo.new.gz

echo "cleaned generated artifacts"
