#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 "$ROOT/scripts/tools/lint-custom-rules.py" \
  --domain-dir "$ROOT/sources/custom/domain" \
  --ip-dir "$ROOT/sources/custom/ip" \
  --conflicts "$ROOT/config/custom-rule-conflicts.json"

echo "custom rule lint passed"
