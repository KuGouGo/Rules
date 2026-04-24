#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p \
  "$TMP_DIR/.output/domain/surge" \
  "$TMP_DIR/.output/domain/egern" \
  "$TMP_DIR/.output/ip/surge"

cat > "$TMP_DIR/.output/domain/surge/sample.list" <<'RULES'
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,example
RULES

cat > "$TMP_DIR/.output/domain/egern/sample.yaml" <<'RULES'
domain_set:
  - 'api.example.com'

domain_regex_set:
  - '^example$'
RULES

cat > "$TMP_DIR/.output/ip/surge/sample.list" <<'RULES'
IP-CIDR,1.2.3.0/24,no-resolve
IP-CIDR6,2001:db8::/32,no-resolve
RULES

python3 "$ROOT/scripts/tools/summarize-artifacts.py" \
  "$TMP_DIR/.output" \
  --output "$TMP_DIR/.output/build-summary.json" >/dev/null

python3 - "$TMP_DIR/.output/build-summary.json" <<'PY'
import json
import sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert summary["domain"]["surge"]["files"] == 1
assert summary["domain"]["surge"]["rules"] == 3
assert summary["domain"]["surge"]["by_kind"]["DOMAIN-KEYWORD"] == 1
assert summary["domain"]["egern"]["rules"] == 2
assert summary["domain"]["egern"]["by_kind"]["YAML-ENTRY"] == 2
assert summary["ip"]["surge"]["rules"] == 2
assert summary["ip"]["surge"]["by_kind"]["IP-CIDR6"] == 1
PY

echo "artifact summary tests passed"
