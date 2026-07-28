#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/target.list" <<'EOF'
DOMAIN,api.example.com
DOMAIN,keep.example.net
EOF
cat > "$TMP_DIR/domain-set.conf" <<'EOF'
# source comment
.example.com
exact.example.org
+ .invalid.example
EOF

if python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/domain-set.conf" "$TMP_DIR/target.list" "$TMP_DIR/normalized.list" \
  --format domain-set >/dev/null 2>&1; then
  echo "test failed: malformed domain-set source was accepted" >&2
  exit 1
fi

cat > "$TMP_DIR/domain-set.conf" <<'EOF'
# source comment
.example.com
exact.example.org
EOF
output="$(python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/domain-set.conf" "$TMP_DIR/target.list" "$TMP_DIR/normalized.list" \
  --format domain-set)"
grep -q 'source=2 skipped=0 excluded=0 added=2 compacted=1' <<<"$output"
grep -qx 'DOMAIN-SUFFIX,example.com' "$TMP_DIR/target.list"
grep -qx 'DOMAIN,keep.example.net' "$TMP_DIR/target.list"
if grep -q 'api.example.com' "$TMP_DIR/target.list"; then
  echo "test failed: suffix-covered exact rule was not compacted" >&2
  exit 1
fi
grep -qx 'DOMAIN,exact.example.org' "$TMP_DIR/normalized.list"

cat > "$TMP_DIR/classical.conf" <<'EOF'
DOMAIN,new.example.net
PROCESS-NAME,unsupported
EOF
if python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/classical.conf" "$TMP_DIR/target.list" "$TMP_DIR/classical.list" \
  --format classical >/dev/null 2>&1; then
  echo "test failed: unsupported classical rule type was accepted" >&2
  exit 1
fi

cat > "$TMP_DIR/filtered.conf" <<'EOF'
DOMAIN,7h1s_rul35et_i5_mad3_by_5ukk4w-ruleset.skk.moe
DOMAIN-SUFFIX,kept.example
DOMAIN-WILDCARD,stun.*.*
EOF
output="$(python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/filtered.conf" "$TMP_DIR/target.list" "$TMP_DIR/filtered.list" \
  --format classical \
  --ignore-domain 7h1s_rul35et_i5_mad3_by_5ukk4w-ruleset.skk.moe \
  --allow-unsupported-rule 'DOMAIN-WILDCARD,stun.*.*')"
grep -q 'source=1 skipped=2 excluded=0 added=1' <<<"$output"
grep -qx 'DOMAIN-SUFFIX,kept.example' "$TMP_DIR/filtered.list"

cat > "$TMP_DIR/unreviewed-unsupported.conf" <<'EOF'
DOMAIN-SUFFIX,kept.example
DOMAIN-WILDCARD,new.*.*
EOF
if python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/unreviewed-unsupported.conf" "$TMP_DIR/target.list" "$TMP_DIR/unreviewed.list" \
  --format classical \
  --allow-unsupported-rule 'DOMAIN-WILDCARD,stun.*.*' >/dev/null 2>&1; then
  echo "test failed: unreviewed rule of an allowlisted unsupported kind was accepted" >&2
  exit 1
fi

cat > "$TMP_DIR/marked-domain-set.conf" <<'EOF'
7h1s_rul35et_i5_mad3_by_5ukk4w-ruleset.skk.moe
.domain-set.example
EOF
output="$(python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/marked-domain-set.conf" "$TMP_DIR/target.list" "$TMP_DIR/marked-domain-set.list" \
  --format domain-set \
  --ignore-domain 7h1s_rul35et_i5_mad3_by_5ukk4w-ruleset.skk.moe)"
grep -q 'source=1 skipped=1 excluded=0 added=1' <<<"$output"
if grep -q '7h1s_rul35et' "$TMP_DIR/marked-domain-set.list" "$TMP_DIR/target.list"; then
  echo "test failed: Sukka marker leaked from domain-set source" >&2
  exit 1
fi

cat > "$TMP_DIR/exclusions.list" <<'EOF'
DOMAIN-SUFFIX,blocked.example
DOMAIN,ad.broad.example
EOF
cat > "$TMP_DIR/excluded-source.conf" <<'EOF'
DOMAIN,sub.blocked.example
DOMAIN-SUFFIX,broad.example
DOMAIN-SUFFIX,allowed.example
EOF
output="$(python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/excluded-source.conf" "$TMP_DIR/target.list" "$TMP_DIR/excluded.list" \
  --format classical --exclude-file "$TMP_DIR/exclusions.list")"
grep -q 'source=3 skipped=0 excluded=2 added=1' <<<"$output"
if grep -q 'blocked.example' "$TMP_DIR/excluded.list"; then
  echo "test failed: excluded rule was normalized" >&2
  exit 1
fi

echo "Sukka domain merge tests passed"
