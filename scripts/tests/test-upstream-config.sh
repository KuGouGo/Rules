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
  "compatibility_replacements": {},
  "geographic_roots": ["geolocation-!cn"],
  "geolocation_not_cn": ["telegram", "google", "google"],
  "schema_version": 5,
  "standalone": []
}
EOF
assert_lint_fails_with \
  "domain-publish-policy" \
  "domain_publish_policy: geolocation_not_cn must be a list of unique non-empty names" \
  --domain-publish-policy "$TMP_DIR/bad-domain-publish-policy.json"

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
ip_sources = config["ip"]
if "cn-geoip" in ip_sources:
    raise SystemExit("test failed: transitive IPinfo China source must remain excluded")
cn_apnic = ip_sources.get("cn-ipv46-apnic", {})
if cn_apnic.get("trust") != "registry":
    raise SystemExit("test failed: APNIC-derived China IP source must retain registry trust")
if cn_apnic.get("health", {}).get("min_entries", 0) < 5000:
    raise SystemExit("test failed: APNIC China source must reject heavily truncated output")
cn_clang_ipv46 = ip_sources.get("cn-clang-ipv46", {})
if cn_clang_ipv46.get("trust") != "community" or cn_clang_ipv46.get("health", {}).get("family") != "dual":
    raise SystemExit("test failed: Clang China combined source must be a community dual-family source")
if cn_clang_ipv46.get("health", {}).get("min_entries", 0) < 5500:
    raise SystemExit("test failed: Clang China combined source must reject heavily truncated output")
if "cn-clang-ipv4" in ip_sources or "cn-clang-ipv6" in ip_sources:
    raise SystemExit(
        "test failed: Clang per-family sources must stay folded into the combined "
        "all_cn_ipv46.txt source (verified byte-for-byte equivalent upstream)"
    )
cn_17mon = ip_sources.get("cn-17mon-ipv4", {})
if cn_17mon.get("trust") != "community" or cn_17mon.get("health", {}).get("family") != "ipv4":
    raise SystemExit("test failed: 17mon China source must be a community IPv4 source")
if cn_17mon.get("health", {}).get("min_entries", 0) < 7000:
    raise SystemExit("test failed: 17mon China source must reject heavily truncated output")
if "geoip-asn-ipv4" in ip_sources or "geoip-asn-ipv6" in ip_sources:
    raise SystemExit(
        "test failed: GeoLite2-ASN CSV sources were replaced by iptoasn.com snapshots "
        "(hourly updates, PDDL license, BGP routing-table view)"
    )
for asn_source_name, expected_family, expected_min in (("iptoasn-ipv4", "ipv4", 500000), ("iptoasn-ipv6", "ipv6", 150000)):
    asn_source = ip_sources.get(asn_source_name, {})
    if asn_source.get("parser") != "iptoasn-tsv":
        raise SystemExit(f"test failed: {asn_source_name} must use the iptoasn-tsv parser")
    if asn_source.get("health", {}).get("family") != expected_family:
        raise SystemExit(f"test failed: {asn_source_name} must be a {expected_family} snapshot")
    if asn_source.get("health", {}).get("min_entries", 0) < expected_min:
        raise SystemExit(f"test failed: {asn_source_name} must reject heavily truncated snapshots")
if "aws" in ip_sources:
    raise SystemExit("test failed: full AWS IP source must be trimmed to CloudFront CDN only")
if "apple" in ip_sources:
    raise SystemExit("test failed: Apple IP must be a built-in source, not a remote fetch")
asn_groups = config["asn_groups"]
if asn_groups["telegram"] != [62041, 62014, 59930, 44907, 211157]:
    raise SystemExit("test failed: Telegram ASN group must cover all self-owned ASNs")
if asn_groups["apple"] != [714, 6185]:
    raise SystemExit("test failed: Apple ASN group must be [714, 6185]")
if 16591 in asn_groups["google"] or 19527 in asn_groups["google"]:
    raise SystemExit("test failed: Google ASN group must exclude Google Fiber AS16591/AS19527")
if len(asn_groups["google"]) < 20:
    raise SystemExit("test failed: Google ASN group unexpectedly small")
PY

python3 - <<'PY'
import json
from pathlib import Path

config = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))
expected_urls = {
    "domain.dlc": "https://github.com/v2fly/domain-list-community.git",
    "domain.shellcrash-fakeip": "https://raw.githubusercontent.com/juewuy/ShellCrash/refs/heads/dev/public/fake_ip_filter.list",
    "ip.cn-ipv46-apnic": "https://ispip.clang.cn/all_cn_ipv46_apnic.txt",
    "ip.cn-17mon-ipv4": "https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt",
    "ip.cn-clang-ipv46": "https://ispip.clang.cn/all_cn_ipv46.txt",
    "ip.gaoyifan-cn-ipv4": "https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt",
    "ip.gaoyifan-cn-ipv6": "https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt",
    "ip.chnroutes-bgp-ipv4": "https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt",
    "ip.iptoasn-ipv4": "https://iptoasn.com/data/ip2asn-v4-u32.tsv.gz",
    "ip.iptoasn-ipv6": "https://iptoasn.com/data/ip2asn-v6.tsv.gz",
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
actual = set(Path("sources/custom/ip/private.list").read_text(encoding="utf-8").splitlines())
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
data["ip"]["gaoyifan-cn-ipv4"]["url"] = "http://example.invalid/china.txt"
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "invalid-url" \
  "upstreams.ip.gaoyifan-cn-ipv4.url: URL must be absolute https" \
  --upstreams "$TMP_DIR/upstreams.invalid-url.json"

cp config/upstreams.json "$TMP_DIR/upstreams.unused.json"
python3 - <<'PY' "$TMP_DIR/upstreams.unused.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["domain"]["unused-domain"] = data["domain"]["shellcrash-fakeip"].copy()
data["ip"]["unused-ip"] = data["ip"]["cn-clang-ipv46"].copy()
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

python3 - <<'PY'
import json
import re
from pathlib import Path

config = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))
discovery = config.get("asn_discovery")
if not isinstance(discovery, dict) or not discovery:
    raise SystemExit("test failed: asn_discovery must be declared for automated ASN expansion")
if set(discovery) != set(config["asn_groups"]):
    raise SystemExit(
        "test failed: asn_discovery must cover exactly the declared asn_groups: "
        f"{sorted(discovery)} vs {sorted(config['asn_groups'])}"
    )
for group, rules in discovery.items():
    if not rules["include"]:
        raise SystemExit(f"test failed: asn_discovery.{group}.include must not be empty")
    for pattern in rules["include"] + rules["exclude"]:
        re.compile(pattern, re.IGNORECASE)
    if not isinstance(rules["max_auto_add"], int) or rules["max_auto_add"] < 1:
        raise SystemExit(f"test failed: asn_discovery.{group}.max_auto_add must be a positive integer")
apple_rules = discovery["apple"]
if "HOSTMYAPPLE" not in apple_rules["exclude"] and not any(
    p.startswith("^") for p in apple_rules["include"]
):
    raise SystemExit("test failed: apple discovery must anchor patterns to reject same-name impostors")
google_rules = discovery["google"]
if "FIBER" not in google_rules["exclude"] or "PEER" not in google_rules["exclude"]:
    raise SystemExit("test failed: google discovery must exclude Google Fiber and peer/PNI networks")
PY

cp config/upstreams.json "$TMP_DIR/upstreams.bad-discovery.json"
python3 - <<'PY' "$TMP_DIR/upstreams.bad-discovery.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["asn_discovery"]["apple"]["include"].append("(")
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "bad-discovery-regex" \
  "invalid regex '('" \
  --upstreams "$TMP_DIR/upstreams.bad-discovery.json"

cp config/upstreams.json "$TMP_DIR/upstreams.unknown-discovery-group.json"
python3 - <<'PY' "$TMP_DIR/upstreams.unknown-discovery-group.json"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["asn_discovery"]["ghost"] = {"include": ["X"], "exclude": [], "max_auto_add": 1}
path.write_text(json.dumps(data), encoding="utf-8")
PY
assert_lint_fails_with \
  "unknown-discovery-group" \
  "upstreams.asn_discovery.ghost: references an unknown asn group" \
  --upstreams "$TMP_DIR/upstreams.unknown-discovery-group.json"

echo "upstream config tests passed"
