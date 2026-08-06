#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
for target in one two; do
  cat > "$TMP/$target.list" <<'EOF'
DOMAIN-SUFFIX,example.cn
DOMAIN,exact.cn
EOF
done
cat > "$TMP/source.txt" <<'EOF'
example.cn
www.example.cn
new.cn
sub.new.cn
INVALID DOMAIN
EOF
out=$(PYTHONPATH="$ROOT_DIR/scripts/tools" python3 "$ROOT_DIR/scripts/tools/merge-domain-suffixes.py" \
  "$TMP/source.txt" "$TMP/one.list" "$TMP/two.list" --normalized-output "$TMP/normalized.list")
grep -q 'candidate=4 invalid=1' <<<"$out"
[ "$(grep -c 'added=1' <<<"$out")" -eq 2 ]
for target in one two; do
  grep -qx 'DOMAIN-SUFFIX,new.cn' "$TMP/$target.list"
  if grep -q 'www.example.cn\|sub.new.cn\|INVALID' "$TMP/$target.list"; then
    echo 'covered or invalid domain unexpectedly present' >&2; exit 1
  fi
done
grep -qx 'DOMAIN-SUFFIX,sub.new.cn' "$TMP/normalized.list"
python3 - "$TMP/one.list" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0,'scripts/tools')
from domain_rules import parse_classical_domain_file
_,e=parse_classical_domain_file(Path(sys.argv[1]),require_canonical=True,allow_single_label_suffix=True)
assert not e,e
PY
echo PASS
