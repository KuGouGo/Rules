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
china = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))["domain"]["loyalsoldier-china-list"]
if china.get("parser") != "domain-suffix-text":
    raise SystemExit("test failed: China List must use domain-suffix-text parser")
if not china.get("url", "").endswith("/release/china-list.txt"):
    raise SystemExit("test failed: China List URL must use the narrow release text artifact")
domain_sources = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))["domain"]
for name in ("sukka-apple-intelligence", "sukka-icloud-private-relay", "sukka-game-download",
             "sukka-domestic", "sukka-ai", "sukka-apple-cdn", "sukka-apple-cn", "sukka-microsoft-cdn"):
    if name in domain_sources:
        raise SystemExit(f"test failed: low-value Sukka domain source was reintroduced: {name}")
ip_sources = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))["ip"]
if ip_sources.get("cn-ipv46", {}).get("trust") != "community":
    raise SystemExit("test failed: IPNetDB-derived China IP source must use community trust")
if ip_sources.get("cn-ipv46-apnic", {}).get("trust") != "registry":
    raise SystemExit("test failed: APNIC-derived China IP source must retain registry trust")
if "loyalsoldier-geoip-cn" in ip_sources:
    raise SystemExit("test failed: low-marginal China GeoIP source must remain excluded")
if "loyalsoldier-geoip-private" in ip_sources:
    raise SystemExit("test failed: static private ranges must not depend on a remote source")
if "sukka-apple-services" in ip_sources:
    raise SystemExit("test failed: low-value Sukka Apple IP source was reintroduced")
for excluded in ("sukka-china-ipv4", "sukka-china-ipv6"):
    if excluded in ip_sources:
        raise SystemExit(f"test failed: low-marginal Sukka China IP source was reintroduced: {excluded}")
asn_groups = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))["asn_groups"]
if asn_groups["telegram"] != [62041]:
    raise SystemExit("test failed: Telegram must keep only the ASN with coverage beyond its official CIDR list")
PY

python3 - <<'PY'
from pathlib import Path

expected = {
    "IP-CIDR,0.0.0.0/8",
    "IP-CIDR,10.0.0.0/8",
    "IP-CIDR,100.64.0.0/10",
    "IP-CIDR,127.0.0.0/8",
    "IP-CIDR,169.254.0.0/16",
    "IP-CIDR,172.16.0.0/12",
    "IP-CIDR,192.0.0.0/24",
    "IP-CIDR,192.0.2.0/24",
    "IP-CIDR,192.88.99.0/24",
    "IP-CIDR,192.168.0.0/16",
    "IP-CIDR,198.18.0.0/15",
    "IP-CIDR,198.51.100.0/24",
    "IP-CIDR,203.0.113.0/24",
    "IP-CIDR,224.0.0.0/3",
    "IP-CIDR6,::/127",
    "IP-CIDR6,fc00::/7",
    "IP-CIDR6,fe80::/10",
    "IP-CIDR6,ff00::/8",
}
actual = set(Path("sources/builtin/ip/private.list").read_text(encoding="utf-8").splitlines())
if actual != expected:
    raise SystemExit("test failed: built-in private ranges changed without updating the reviewed baseline")
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

cp config/upstreams.json "$TMP_DIR/upstreams.unused.json"
python3 - <<'PY' "$TMP_DIR/upstreams.unused.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["domain"]["unused-domain"] = data["domain"]["loyalsoldier-china-list"].copy()
data["ip"]["unused-ip"] = data["ip"]["cloudflare-ipv4"].copy()
data["asn_groups"]["unused-group"] = [64512]
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "unused-domain" \
  "upstreams.domain: unsupported sources: ['unused-domain']" \
  --upstreams "$TMP_DIR/upstreams.unused.json"
assert_lint_fails_with \
  "unused-ip" \
  "upstreams.ip: unsupported sources: ['unused-ip']" \
  --upstreams "$TMP_DIR/upstreams.unused.json"
assert_lint_fails_with \
  "unused-asn-group" \
  "upstreams.asn_groups: unsupported groups: ['unused-group']" \
  --upstreams "$TMP_DIR/upstreams.unused.json"

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
  "tools_lock.tools.mihomo.platforms.linux-arm64.asset: must equal mihomo-linux-arm64-v1.19.29.gz" \
  --tools-lock "$TMP_DIR/tools-lock.invalid-asset.json"

echo "upstream config tests passed"
