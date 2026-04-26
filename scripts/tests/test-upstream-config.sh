#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json
from pathlib import Path

config = json.loads(Path("config/upstreams.json").read_text(encoding="utf-8"))
required_domain = {"dlc", "anti-ad"}
required_ip = {
    "cn-ipv4",
    "cn-ipv6",
    "cn-asn-ipv4",
    "cn-asn-ipv6",
    "google",
    "telegram",
    "cloudflare-ipv4",
    "cloudflare-ipv6",
    "aws",
    "fastly",
    "github",
    "apple",
    "ripe-stat",
}
missing_domain = required_domain - set(config.get("domain", {}))
missing_ip = required_ip - set(config.get("ip", {}))
if missing_domain or missing_ip:
    raise SystemExit(f"missing upstream config entries: domain={sorted(missing_domain)} ip={sorted(missing_ip)}")
anti_ad_required_keys = {
    "sing_box_srs_min_bytes",
    "sing_box_srs_url",
    "sing_box_srs_fallback_url",
    "mihomo_mrs_min_bytes",
    "mihomo_mrs_url",
    "mihomo_mrs_fallback_url",
}
missing_anti_ad_keys = anti_ad_required_keys - set(config["domain"]["anti-ad"])
if missing_anti_ad_keys:
    raise SystemExit(f"domain.anti-ad missing native artifact config keys: {sorted(missing_anti_ad_keys)}")
for key in anti_ad_required_keys:
    if not config["domain"]["anti-ad"].get(key):
        raise SystemExit(f"domain.anti-ad {key} must be non-empty")
for section in ("domain", "ip"):
    for name, item in config[section].items():
        if "trust" not in item or "kind" not in item:
            raise SystemExit(f"{section}.{name} must declare trust and kind")
        if "url" not in item and "base_url" not in item:
            raise SystemExit(f"{section}.{name} must declare url or base_url")
for name in ("netflix", "spotify", "disney"):
    values = config.get("asn_groups", {}).get(name)
    if not values or not all(isinstance(item, int) for item in values):
        raise SystemExit(f"asn group {name} must be a non-empty integer list")
PY

echo "upstream config tests passed"
