#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - <<'PY' "$ROOT"
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "tools"))
from platform_capabilities import load_platform_capabilities, shell_registry_rows

registry = load_platform_capabilities()
rows = [row.split("\t") for row in shell_registry_rows()]
assert len(rows) == len(registry.platforms) * 2
assert list(registry.platforms) == ["surge", "quanx", "egern", "sing-box", "mihomo"]
assert [row[0] for row in rows[1::2]] == list(registry.platforms)
for key, platform in registry.platforms.items():
    selected = [row for row in rows if row[0] == key]
    assert [row[3] for row in selected] == ["domain", "ip"]
    assert all(row[2] == platform.branch for row in selected)
    assert selected[0][4] == platform.domain.extension
    assert selected[1][4] == platform.ip.extension
PY

python3 - <<'PY' "$ROOT/config/domain-platform-capabilities.json" "$TMP/invalid.json"
import json, sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
data = json.loads(source.read_text(encoding="utf-8"))
data["platforms"]["surge"]["ip"]["compiler"] = "not-implemented"
target.write_text(json.dumps(data), encoding="utf-8")
PY

if python3 "$ROOT/scripts/tools/platform_capabilities.py" --config "$TMP/invalid.json" shell-registry >"$TMP/out" 2>"$TMP/err"; then
  echo "unsupported implementation unexpectedly accepted" >&2
  exit 1
fi
grep -q "unsupported implementation" "$TMP/err"

python3 - <<'PY' "$ROOT/config/domain-platform-capabilities.json" "$TMP/extra.json"
import json, sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
data = json.loads(source.read_text(encoding="utf-8"))
data["platforms"]["extra"] = data["platforms"]["surge"]
target.write_text(json.dumps(data), encoding="utf-8")
PY
if python3 "$ROOT/scripts/tools/platform_capabilities.py" --config "$TMP/extra.json" shell-registry >/dev/null 2>&1; then
  echo "runtime loader accepted extra platform" >&2; exit 1
fi
if python3 "$ROOT/scripts/tools/lint-config.py" --domain-platform-capabilities "$TMP/extra.json" >/dev/null 2>&1; then
  echo "lint accepted runtime-invalid capability structure" >&2; exit 1
fi

echo "platform capability registry tests passed"
