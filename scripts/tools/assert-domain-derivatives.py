#!/usr/bin/env python3
"""Guard the derivative domain rule sets required by downstream platforms.

Invoked by scripts/commands/sync-upstream.sh.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REQUIRED_RULE_SETS = {
    "alibaba@!cn",
    "apple@cn",
    "cn",
    "geolocation-!cn",
    "geolocation-cn",
    "google@cn",
    "tld-!cn",
    "tld-cn",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest_file")
    parser.add_argument("min_attr", type=int)
    parser.add_argument("min_cn", type=int)
    parser.add_argument("min_not_cn", type=int)
    parser.add_argument("min_regional", type=int)
    args = parser.parse_args()

    manifest = json.loads(Path(args.manifest_file).read_text(encoding="utf-8"))
    lists = manifest.get("lists", [])
    names = {entry.get("name", "") for entry in lists}
    attr_rule_sets = [entry for entry in lists if entry.get("kind") == "attr"]
    cn_attr = [entry for entry in lists if entry.get("attr") == "cn"]
    not_cn_attr = [entry for entry in lists if entry.get("attr") == "!cn"]
    regional = [entry for entry in lists if entry.get("kind") == "regional"]

    print(
        "domain derivative rule sets: "
        f"attr={len(attr_rule_sets)} (min {args.min_attr}), "
        f"@cn={len(cn_attr)} (min {args.min_cn}), "
        f"@!cn={len(not_cn_attr)} (min {args.min_not_cn}), "
        f"regional={len(regional)} (min {args.min_regional})"
    )

    errors = []
    if len(attr_rule_sets) < args.min_attr:
        errors.append(f"attribute derivative rule sets too low: {len(attr_rule_sets)} < {args.min_attr}")
    if len(cn_attr) < args.min_cn:
        errors.append(f"@cn derivative rule sets too low: {len(cn_attr)} < {args.min_cn}")
    if len(not_cn_attr) < args.min_not_cn:
        errors.append(f"@!cn derivative rule sets too low: {len(not_cn_attr)} < {args.min_not_cn}")
    if len(regional) < args.min_regional:
        errors.append(f"regional -cn/-!cn rule sets too low: {len(regional)} < {args.min_regional}")
    geolocation_regions = set(manifest.get("region_pairs", {}).get("geolocation", []))
    if not {"cn", "!cn"}.issubset(geolocation_regions):
        errors.append("missing geolocation -cn/-!cn regional pair")

    missing = sorted(REQUIRED_RULE_SETS - names)
    if missing:
        errors.append("missing required derivative rule sets: " + ", ".join(missing))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
