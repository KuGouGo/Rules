#!/usr/bin/env python3
"""Apply the fail-closed health contract declared for an upstream."""
from __future__ import annotations

import argparse
import ipaddress
import json
import sys
from pathlib import Path

FAMILY_VERSIONS = {
    "ipv4": {4},
    "ipv6": {6},
    "dual": {4, 6},
}


def _raw_byte_count(raw: Path) -> int:
    if raw.is_file():
        return raw.stat().st_size
    if raw.is_dir():
        return sum(entry.stat().st_size for entry in raw.rglob("*") if entry.is_file())
    return 0


def _normalized_entries(normalized: Path) -> list[str] | list[Path]:
    if normalized.is_dir():
        return [entry for entry in normalized.rglob("*") if entry.is_file()]
    if normalized.is_file():
        return [
            line.strip()
            for line in normalized.read_text(encoding="utf-8", errors="ignore").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
    return []


def _check_address_family(entries: list[str], family: str) -> list[str]:
    if family == "any":
        return []
    versions: set[int] = set()
    for line in entries:
        value = line.split(",", 1)[-1].split(",", 1)[0] if line.startswith("IP-CIDR") else line
        try:
            versions.add(ipaddress.ip_network(value, strict=False).version)
        except ValueError:
            pass
    expected = FAMILY_VERSIONS.get(family, set())
    if not expected.issubset(versions):
        return [f"address family {family} not satisfied; found {sorted(versions)}"]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config")
    parser.add_argument("section")
    parser.add_argument("name")
    parser.add_argument("raw")
    parser.add_argument("normalized")
    args = parser.parse_args()

    source = json.loads(Path(args.config).read_text(encoding="utf-8"))[args.section][args.name]
    policy = source["health"]
    raw, normalized = Path(args.raw), Path(args.normalized)

    errors: list[str] = []
    raw_bytes = _raw_byte_count(raw)
    if raw_bytes < policy["min_raw_bytes"]:
        errors.append(f"raw bytes {raw_bytes} < {policy['min_raw_bytes']}")

    entries = _normalized_entries(normalized)
    if len(entries) < policy["min_entries"]:
        errors.append(f"normalized entries {len(entries)} < {policy['min_entries']}")

    if normalized.is_file():
        errors.extend(_check_address_family(entries, policy["family"]))

    status = "ok" if not errors else "semantic_regression"
    print(
        json.dumps(
            {"source": args.name, "status": status, "raw_bytes": raw_bytes,
             "entries": len(entries), "errors": errors},
            sort_keys=True,
        )
    )
    if errors and policy["requirement"] == "required":
        print(f"required upstream {args.name} failed health: {'; '.join(errors)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
