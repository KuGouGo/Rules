#!/usr/bin/env python3
"""Apply the fail-closed health contract declared for an upstream."""
import argparse, ipaddress, json, sys
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("config"); p.add_argument("section"); p.add_argument("name")
    p.add_argument("raw"); p.add_argument("normalized")
    a = p.parse_args()
    source = json.loads(Path(a.config).read_text(encoding="utf-8"))[a.section][a.name]
    policy = source["health"]
    raw, normalized = Path(a.raw), Path(a.normalized)
    errors = []
    raw_bytes = raw.stat().st_size if raw.exists() and raw.is_file() else sum(x.stat().st_size for x in raw.rglob("*") if x.is_file()) if raw.is_dir() else 0
    if raw_bytes < policy["min_raw_bytes"]:
        errors.append(f"raw bytes {raw_bytes} < {policy['min_raw_bytes']}")
    entries = []
    if normalized.is_dir():
        entries = [x for x in normalized.rglob("*") if x.is_file()]
    elif normalized.is_file():
        entries = [line.strip() for line in normalized.read_text(encoding="utf-8", errors="ignore").splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if len(entries) < policy["min_entries"]:
        errors.append(f"normalized entries {len(entries)} < {policy['min_entries']}")
    family = policy["family"]
    if family != "any" and normalized.is_file():
        versions = set()
        for line in entries:
            value = line.split(",", 1)[-1].split(",", 1)[0] if line.startswith("IP-CIDR") else line
            try: versions.add(ipaddress.ip_network(value, strict=False).version)
            except ValueError: pass
        expected = {"ipv4": {4}, "ipv6": {6}, "dual": {4, 6}}[family]
        if not expected.issubset(versions): errors.append(f"address family {family} not satisfied; found {sorted(versions)}")
    status = "ok" if not errors else "semantic_regression"
    print(json.dumps({"source": a.name, "status": status, "raw_bytes": raw_bytes, "entries": len(entries), "errors": errors}, sort_keys=True))
    if errors and policy["requirement"] == "required":
        print(f"required upstream {a.name} failed health: {'; '.join(errors)}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__": raise SystemExit(main())
