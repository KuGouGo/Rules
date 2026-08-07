#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Fake-IP is an upstream-synced list (ShellCrash), not a locally maintained
# custom source. It must flow through the unified sync pipeline only.
if [ -e "$ROOT/sources/custom/domain/fakeip-filter.list" ]; then
  echo "test failed: fakeip-filter must not remain a local custom source" >&2
  exit 1
fi
if [ -e "$ROOT/scripts/commands/sync-fakeip-filter.sh" ]; then
  echo "test failed: unused Fake-IP sync wrapper still exists" >&2
  exit 1
fi
if grep -RInE 'wwqgtxx|sync-fakeip-filter' \
  "$ROOT/scripts/commands" "$ROOT/scripts/lib" "$ROOT/scripts/tools" \
  "$ROOT/config" "$ROOT/.github/workflows" "$ROOT/Makefile"; then
  echo "test failed: legacy Fake-IP provider or wrapper reference remains" >&2
  exit 1
fi

# The upstream is declared in the unified upstream configuration.
python3 - "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
config = json.loads((root / "config/upstreams.json").read_text(encoding="utf-8"))
source = config["domain"]["shellcrash-fakeip"]
expected_url = "https://raw.githubusercontent.com/juewuy/ShellCrash/refs/heads/dev/public/fake_ip_filter.list"
assert source["kind"] == "text", source
assert source["parser"] == "domain-set-text", source
assert source["url"] == expected_url, source
assert source["health"]["min_entries"] >= 1, source
PY

# ... and linted through the same SOURCE_IMPLEMENTATIONS registry as every source.
grep -F '"shellcrash-fakeip": ("text", "domain-set-text")' \
  "$ROOT/scripts/tools/lint-config.py" >/dev/null
python3 "$ROOT/scripts/tools/lint-config.py" >/dev/null

# The unified sync pipeline downloads, merges, and records health for the list.
SYNC="$ROOT/scripts/commands/sync-upstream.sh"
# shellcheck disable=SC2016
grep -F 'shellcrash-fakeip required "$SHELLCRASH_FAKEIP_SOURCE_URL"' "$SYNC" >/dev/null
grep -F 'merge-domain-rule-source.py' "$SYNC" >/dev/null
# shellcheck disable=SC2016
grep -F '"$WORK_TMP_DIR/shellcrash-fakeip.raw.list"' "$SYNC" >/dev/null
grep -F 'verify_and_record_upstream_health' "$SYNC" >/dev/null
grep -F 'fakeip-filter.list' "$SYNC" >/dev/null

# Parser contract: ShellCrash uses Clash domain-set syntax. Suffix wildcards
# become DOMAIN-SUFFIX, mid-label wildcards become DOMAIN-REGEX, and category
# labels plus the universal '*' are skipped so no bypass escapes the build.
cat > "$TMP_DIR/upstream.list" <<'EOF'
#LAN
*
*.lan
*.localdomain
time.*.com
time1.*.com
time-ios.apple.com
example.com
Mijia Cloud
EOF
: > "$TMP_DIR/fakeip-filter.list"
output="$(python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/upstream.list" \
  "$TMP_DIR/fakeip-filter.list" \
  "$TMP_DIR/fakeip-filter.normalized.list")"
grep -q 'source=6 skipped=2 added=6' <<<"$output"
grep -qx 'DOMAIN-SUFFIX,lan' "$TMP_DIR/fakeip-filter.list"
grep -qx 'DOMAIN-SUFFIX,localdomain' "$TMP_DIR/fakeip-filter.list"
grep -Fx 'DOMAIN-REGEX,^time\.[^.]+\.com$' "$TMP_DIR/fakeip-filter.list" >/dev/null
grep -Fx 'DOMAIN-REGEX,^time1\.[^.]+\.com$' "$TMP_DIR/fakeip-filter.list" >/dev/null
grep -qx 'DOMAIN,time-ios.apple.com' "$TMP_DIR/fakeip-filter.list"
grep -qx 'DOMAIN,example.com' "$TMP_DIR/fakeip-filter.list"
if grep -Fx '*' "$TMP_DIR/fakeip-filter.list" >/dev/null; then
  echo "test failed: universal Fake-IP bypass must not be published" >&2
  exit 1
fi
if grep -F 'Mijia' "$TMP_DIR/fakeip-filter.list" "$TMP_DIR/fakeip-filter.normalized.list" >/dev/null; then
  echo "test failed: category label leaked from domain-set source" >&2
  exit 1
fi

# Malformed '+ ' prefixes must be rejected, not silently skipped.
cat > "$TMP_DIR/malformed.list" <<'EOF'
example.com
+ .invalid.example
EOF
: > "$TMP_DIR/malformed-target.list"
if python3 "$ROOT/scripts/tools/merge-domain-rule-source.py" \
  "$TMP_DIR/malformed.list" \
  "$TMP_DIR/malformed-target.list" \
  "$TMP_DIR/malformed.normalized.list" >/dev/null 2>&1; then
  echo "test failed: malformed domain-set source was accepted" >&2
  exit 1
fi

# Render the merged list to every text platform: regex survives on Egern and
# sing-box, and is skipped on Surge, QuanX, and mihomo.
mkdir -p "$TMP_DIR/input" "$TMP_DIR/out/surge" "$TMP_DIR/out/quanx" "$TMP_DIR/out/egern"
cp "$TMP_DIR/fakeip-filter.list" "$TMP_DIR/input/fakeip-filter.list"
python3 "$ROOT/scripts/tools/export-domain-rules.py" text-platform-dirs \
  "$TMP_DIR/input" \
  "$TMP_DIR/out/surge" \
  "$TMP_DIR/out/quanx" \
  "$TMP_DIR/out/egern" \
  >/dev/null 2>"$TMP_DIR/render.stderr"

grep -Fx 'DOMAIN-SUFFIX,lan' "$TMP_DIR/out/surge/fakeip-filter.list" >/dev/null
grep -Fx 'DOMAIN,example.com' "$TMP_DIR/out/surge/fakeip-filter.list" >/dev/null
if grep -F 'DOMAIN-REGEX,' "$TMP_DIR/out/surge/fakeip-filter.list" >/dev/null; then
  echo "test failed: Surge output retained unsupported regex rules" >&2
  exit 1
fi

grep -Fx 'HOST-SUFFIX,lan,fakeip-filter' "$TMP_DIR/out/quanx/fakeip-filter.list" >/dev/null
grep -Fx 'HOST,example.com,fakeip-filter' "$TMP_DIR/out/quanx/fakeip-filter.list" >/dev/null
if grep -F 'HOST-REGEX,' "$TMP_DIR/out/quanx/fakeip-filter.list" >/dev/null; then
  echo "test failed: QuanX output retained unsupported regex rules" >&2
  exit 1
fi

grep -Fx "domain_suffix_set:" "$TMP_DIR/out/egern/fakeip-filter.yaml" >/dev/null
grep -Fx "  - 'lan'" "$TMP_DIR/out/egern/fakeip-filter.yaml" >/dev/null
grep -Fx "domain_regex_set:" "$TMP_DIR/out/egern/fakeip-filter.yaml" >/dev/null
grep -Fx "  - '^time\.[^.]+\.com$'" "$TMP_DIR/out/egern/fakeip-filter.yaml" >/dev/null

python3 "$ROOT/scripts/tools/export-domain-rules.py" singbox-json \
  "$TMP_DIR/fakeip-filter.list" \
  "$TMP_DIR/out/fakeip-filter.json" >/dev/null 2>&1
python3 - "$TMP_DIR/out/fakeip-filter.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
rule = payload["rules"][0]
assert "lan" in rule["domain_suffix"], rule
assert "example.com" in rule["domain"], rule
assert r"^time\.[^.]+\.com$" in rule["domain_regex"], rule
PY

python3 "$ROOT/scripts/tools/export-domain-rules.py" mihomo-text \
  "$TMP_DIR/fakeip-filter.list" \
  "$TMP_DIR/out/fakeip-filter.mihomo.txt" >/dev/null 2>&1
grep -Fx '.lan' "$TMP_DIR/out/fakeip-filter.mihomo.txt" >/dev/null
grep -Fx 'example.com' "$TMP_DIR/out/fakeip-filter.mihomo.txt" >/dev/null
if grep -F 'regex' "$TMP_DIR/out/fakeip-filter.mihomo.txt" >/dev/null; then
  echo "test failed: mihomo output retained unsupported regex rules" >&2
  exit 1
fi

echo "Fake-IP filter tests passed"
