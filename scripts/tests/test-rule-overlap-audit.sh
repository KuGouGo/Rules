#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TMP_DIR="$(mktemp -d)"; trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/domain" "$TMP_DIR/ip"
cat > "$TMP_DIR/domain/sample.list" <<'EOF'
DOMAIN-SUFFIX,example.com
DOMAIN,a.example.com
DOMAIN-SUFFIX,b.example.com
DOMAIN-KEYWORD,example
EOF
cat > "$TMP_DIR/ip/sample.list" <<'EOF'
IP-CIDR,10.0.0.0/8
IP-CIDR,10.1.0.0/16
IP-CIDR6,2001:db8::/32
EOF
cat > "$TMP_DIR/domain/superset.list" <<'EOF'
DOMAIN-SUFFIX,example.org
EOF
cat > "$TMP_DIR/domain/subset.list" <<'EOF'
DOMAIN,api.example.org
EOF
cat > "$TMP_DIR/domain/superset-alias.list" <<'EOF'
DOMAIN-SUFFIX,example.org
EOF
if python3 scripts/tools/audit-rule-overlaps.py "$TMP_DIR" --output "$TMP_DIR/report.json" --fail-internal >/dev/null; then
  echo 'test failed: audit should reject internal semantic redundancy' >&2; exit 1
fi
python3 - "$TMP_DIR/domain/sample.list" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0,'scripts/tools')
from domain_rules import compact_classical_domain_file
before,removed=compact_classical_domain_file(Path(sys.argv[1]))
assert (before,removed)==(4,2),(before,removed)
PY
python3 scripts/tools/normalize-ip-rules.py custom-source "$TMP_DIR/ip/sample.list" "$TMP_DIR/ip/sample.compact"
cat > "$TMP_DIR/ip/sample.list" <<EOF
IP-CIDR,10.0.0.0/8
IP-CIDR6,2001:db8::/32
EOF
python3 scripts/tools/audit-rule-overlaps.py "$TMP_DIR" --output "$TMP_DIR/report.json" --fail-internal >/dev/null
python3 - "$TMP_DIR/report.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert x['schema_version']==2
assert not x['domain']['internal_redundancy'];assert not x['ip']['internal_redundancy']
rows=x['domain']['top_semantic_containments']
assert any(
    row['left']=='subset' and row['right']=='superset'
    and row['covered_rules']==1 and row['coverage_percent']==100.0
    for row in rows
)
assert {'lists':['superset','superset-alias'],'rules':1} in x['domain']['identical_rule_sets']
assert x['domain']['full_semantic_containment_pairs'] >= 1
PY
grep -F -- '--fail-internal' "$ROOT/scripts/commands/build-artifacts-transaction.sh" >/dev/null
echo 'rule overlap audit tests passed'
