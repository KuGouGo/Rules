#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TOOL="$ROOT/scripts/tools/lint-config.py"

assert_lint_fails_with() {
  local label="$1"
  local expected="$2"
  shift 2

  if python3 "$TOOL" "$@" >"$TMP_DIR/${label}.stdout" 2>"$TMP_DIR/${label}.stderr"; then
    echo "test failed: expected config lint to fail for $label" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$TMP_DIR/${label}.stderr"; then
    echo "test failed: missing config lint message for $label: $expected" >&2
    cat "$TMP_DIR/${label}.stderr" >&2
    exit 1
  fi
}

python3 "$TOOL"

cp config/upstreams.json "$TMP_DIR/upstreams.invalid-url.json"
python3 - <<'PY' "$TMP_DIR/upstreams.invalid-url.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["ip"]["google"]["url"] = "http://example.invalid/goog.json"
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-url" \
  "upstreams.ip.google.url: URL must be absolute https" \
  --upstreams "$TMP_DIR/upstreams.invalid-url.json"

cp config/upstreams.json "$TMP_DIR/upstreams.invalid-parser.json"
python3 - <<'PY' "$TMP_DIR/upstreams.invalid-parser.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["ip"]["github"]["parser"] = "unknown-json"
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-parser" \
  "upstreams.ip.github.parser: unsupported parser" \
  --upstreams "$TMP_DIR/upstreams.invalid-parser.json"

cp config/upstream-first-batch-baselines.json "$TMP_DIR/baselines.invalid.json"
python3 - <<'PY' "$TMP_DIR/baselines.invalid.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["telegram"]["secondary_min_total"] = 0
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-baseline" \
  "first_batch_baselines.telegram.secondary_min_total: must be a positive integer" \
  --first-batch-baselines "$TMP_DIR/baselines.invalid.json"

cp config/domain-platform-capabilities.json "$TMP_DIR/capabilities.invalid.json"
python3 - <<'PY' "$TMP_DIR/capabilities.invalid.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["surge"].append("DOMAIN-GLOB")
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-capability" \
  "domain_platform_capabilities.surge[3]: unsupported domain rule type" \
  --domain-platform-capabilities "$TMP_DIR/capabilities.invalid.json"

echo "upstream config tests passed"
