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

# Production capability config must be accepted by both the lint schema and the
# runtime loader so the two independently maintained validators cannot drift.
python3 - <<'PY'
from scripts.tools.platform_capabilities import load_platform_capabilities

capabilities = load_platform_capabilities()
assert capabilities.platforms
PY

python3 - <<'PY'
import json
from pathlib import Path

dlc = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))["domain"]["dlc"]
if dlc.get("kind") != "git":
    raise SystemExit("test failed: domain.dlc must use the git source tree to preserve @attribute filters")
if dlc.get("url") != "https://github.com/v2fly/domain-list-community.git":
    raise SystemExit("test failed: domain.dlc URL must point at domain-list-community.git")
PY

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
  "upstreams.ip.github.parser: unsupported or missing parser 'unknown-json'" \
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
data["platforms"]["surge"]["domain"]["unsupported_kinds"].append("DOMAIN-GLOB")
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-capability" \
  "platforms.surge.domain must classify every declared domain kind" \
  --domain-platform-capabilities "$TMP_DIR/capabilities.invalid.json"

cp config/tools-lock.json "$TMP_DIR/tools-lock.invalid-sha.json"
python3 - <<'PY' "$TMP_DIR/tools-lock.invalid-sha.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["tools"]["sing-box"]["platforms"]["linux-amd64"]["sha256"] = "not-a-sha"
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-tool-sha" \
  "tools_lock.tools.sing-box.platforms.linux-amd64.sha256: must be a lowercase 64-character SHA-256" \
  --tools-lock "$TMP_DIR/tools-lock.invalid-sha.json"

cp config/tools-lock.json "$TMP_DIR/tools-lock.invalid-commit.json"
python3 - <<'PY' "$TMP_DIR/tools-lock.invalid-commit.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["tools"]["mihomo"]["tag_commit"] = "not-a-commit"
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-tool-commit" \
  "tools_lock.tools.mihomo.tag_commit: must be a lowercase 40-character Git commit" \
  --tools-lock "$TMP_DIR/tools-lock.invalid-commit.json"

cp config/tools-lock.json "$TMP_DIR/tools-lock.invalid-asset.json"
python3 - <<'PY' "$TMP_DIR/tools-lock.invalid-asset.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["tools"]["mihomo"]["platforms"]["linux-arm64"]["asset"] = "mihomo-linux-arm64-latest.gz"
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-tool-asset" \
  "tools_lock.tools.mihomo.platforms.linux-arm64.asset: must equal mihomo-linux-arm64-v1.19.28.gz" \
  --tools-lock "$TMP_DIR/tools-lock.invalid-asset.json"

echo "upstream config tests passed"
