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

cat > "$TMP_DIR/bad-domain-publish-policy.json" <<'EOF'
{
  "common": {
    "geographic_roots": ["geolocation-!cn"],
    "geolocation_not_cn": ["telegram", "google", "google"],
    "standalone": []
  },
  "compatibility_replacements": {},
  "default_profile": "common",
  "extended": {
    "geographic_roots": ["geolocation-cn"],
    "geolocation_not_cn": [],
    "standalone": "all"
  },
  "schema_version": 4
}
EOF
assert_lint_fails_with \
  "domain-publish-policy" \
  "domain_publish_policy: common.geolocation_not_cn must be a list of unique non-empty names" \
  --domain-publish-policy "$TMP_DIR/bad-domain-publish-policy.json"

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

config = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))
dlc = config["domain"]["dlc"]
if dlc.get("kind") != "git":
    raise SystemExit("test failed: domain.dlc must use the git source tree to preserve @attribute filters")
if dlc.get("url") != "https://github.com/v2fly/domain-list-community.git":
    raise SystemExit("test failed: domain.dlc URL must point at the domain-list-community source")
if "loyalsoldier-china-list" in config["domain"]:
    raise SystemExit("test failed: DNS-only China List source must remain excluded")
ip_sources = config["ip"]
if "cn-geoip" in ip_sources:
    raise SystemExit("test failed: transitive IPinfo China source must remain excluded")
cn_apnic = ip_sources.get("cn-ipv46-apnic", {})
if cn_apnic.get("trust") != "registry":
    raise SystemExit("test failed: APNIC-derived China IP source must retain registry trust")
if cn_apnic.get("health", {}).get("min_entries", 0) < 5000:
    raise SystemExit("test failed: APNIC China source must reject heavily truncated output")
cn_clang_ipv4 = ip_sources.get("cn-clang-ipv4", {})
if cn_clang_ipv4.get("trust") != "community" or cn_clang_ipv4.get("health", {}).get("family") != "ipv4":
    raise SystemExit("test failed: Clang China IPv4 source must be a community IPv4 source")
if cn_clang_ipv4.get("health", {}).get("min_entries", 0) < 4000:
    raise SystemExit("test failed: Clang China IPv4 source must reject heavily truncated output")
cn_clang_ipv6 = ip_sources.get("cn-clang-ipv6", {})
if cn_clang_ipv6.get("trust") != "community" or cn_clang_ipv6.get("health", {}).get("family") != "ipv6":
    raise SystemExit("test failed: Clang China IPv6 source must be a community IPv6 source")
if cn_clang_ipv6.get("health", {}).get("min_entries", 0) < 1500:
    raise SystemExit("test failed: Clang China IPv6 source must reject heavily truncated output")
if "loyalsoldier-geoip-cn" in ip_sources:
    raise SystemExit("test failed: low-marginal China GeoIP source must remain excluded")
if "loyalsoldier-geoip-private" in ip_sources:
    raise SystemExit("test failed: static private ranges must not depend on a remote source")
if "aws" in ip_sources:
    raise SystemExit("test failed: full AWS IP source must be trimmed to CloudFront CDN only")
if "apple" in ip_sources:
    raise SystemExit("test failed: Apple IP must be a built-in source, not a remote fetch")
cloudfront = ip_sources.get("cloudfront", {})
if cloudfront.get("parser") != "cloudfront-json" or not cloudfront.get("url", "").endswith("ip-ranges.amazonaws.com/ip-ranges.json"):
    raise SystemExit("test failed: CloudFront IP source must use the cloudfront-json parser on AWS ip-ranges")
asn_groups = config["asn_groups"]
if asn_groups["telegram"] != [62041]:
    raise SystemExit("test failed: Telegram must keep only the ASN with coverage beyond its official CIDR list")
PY

python3 - <<'PY'
import json
from pathlib import Path

config = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))
# Every remote upstream must be pinned to its exact URL. Scheme-only
# validation (lint-config.py) blocks http:// but not a merged PR that rewrites
# a host to an attacker-controlled HTTPS endpoint; exact pins close that.
expected_urls = {
    "domain.dlc": "https://github.com/v2fly/domain-list-community.git",
    "domain.shellcrash-fakeip": "https://raw.githubusercontent.com/juewuy/ShellCrash/refs/heads/dev/public/fake_ip_filter.list",
    "ip.cloudfront": "https://ip-ranges.amazonaws.com/ip-ranges.json",
    "ip.cloudflare-ipv4": "https://www.cloudflare.com/ips-v4",
    "ip.cloudflare-ipv6": "https://www.cloudflare.com/ips-v6",
    "ip.cn-ipv46-apnic": "https://ispip.clang.cn/all_cn_ipv46_apnic.txt",
    "ip.cn-clang-ipv4": "https://ispip.clang.cn/all_cn.txt",
    "ip.cn-clang-ipv6": "https://ispip.clang.cn/all_cn_ipv6.txt",
    "ip.fastly": "https://api.fastly.com/public-ip-list",
    "ip.google": "https://www.gstatic.com/ipranges/goog.json",
    "ip.ripe-stat": "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS",
    "ip.telegram": "https://core.telegram.org/resources/cidr.txt",
}
for key, url in expected_urls.items():
    section, _, name = key.partition(".")
    entry = config[section][name]
    actual = entry.get("url") or entry.get("base_url")
    if actual != url:
        raise SystemExit(f"test failed: {key} URL must be pinned exactly, got {actual!r}")
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

expected_apple = {
    "IP-CIDR,17.0.0.0/8",
    "IP-CIDR6,2403:300::/32",
    "IP-CIDR6,2620:149::/32",
    "IP-CIDR6,2a01:b740::/32",
}
actual_apple = set(Path("sources/builtin/ip/apple.list").read_text(encoding="utf-8").splitlines())
if actual_apple != expected_apple:
    raise SystemExit("test failed: built-in Apple IP ranges changed without updating the reviewed baseline")
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
data["domain"]["unused-domain"] = data["domain"]["shellcrash-fakeip"].copy()
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
  "tools_lock.tools.mihomo.platforms.linux-arm64.asset: must equal mihomo-linux-arm64-v1.19.30.gz" \
  --tools-lock "$TMP_DIR/tools-lock.invalid-asset.json"

echo "upstream config tests passed"
