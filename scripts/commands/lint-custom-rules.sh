#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 "$ROOT/scripts/tools/lint-custom-rules.py" \
  --domain-dir "$ROOT/sources/custom/domain" \
  --ip-dir "$ROOT/sources/custom/ip"

python3 "$ROOT/scripts/tools/lint-custom-rules.py" \
  --ip-dir "$ROOT/sources/builtin/ip"

echo "custom and built-in rule lint passed"
