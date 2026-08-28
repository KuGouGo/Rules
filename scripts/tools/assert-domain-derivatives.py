#!/usr/bin/env python3
"""Guard the derivative domain rule sets required by downstream platforms.

Invoked by scripts/commands/sync-upstream.sh.

Per-category regional derivatives (@cn/@!cn) are folded into the geographic
partition, so the only shipped derivative is the geolocation-!cn@cn aggregate
(every @cn rule not already covered by the cn base list). The guard enforces
the common entry points and requires the redundant geolocation-cn compatibility
entry point only for extended publications.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REQUIRED_RULE_SETS = {
    "cn",
    "geolocation-!cn",
    "geolocation-!cn@cn",
}

# Compatibility entry points that only extended publications ship: common
# publishes the cn superset only (it fully covers geolocation-cn and tld-cn),
# so the old names are required to be present only under extended.
PROFILE_REQUIRED_RULE_SETS = {
    "common": frozenset(),
    "extended": frozenset({"geolocation-cn", "tld-cn"}),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest_file")
    parser.add_argument("min_aggregate", type=int)
    parser.add_argument("--profile", choices=("common", "extended"), default="common")
    args = parser.parse_args()

    manifest = json.loads(Path(args.manifest_file).read_text(encoding="utf-8"))
    lists = manifest.get("lists", [])
    names = {entry.get("name", "") for entry in lists}
    aggregate = next(
        (entry for entry in lists if entry.get("name") == "geolocation-!cn@cn"),
        None,
    )
    aggregate_rules = aggregate.get("rules", 0) if aggregate else 0

    print(
        "domain derivative rule sets: "
        f"geolocation-!cn@cn={aggregate_rules} (min {args.min_aggregate})"
    )

    errors = []
    if aggregate is None:
        errors.append("geolocation-!cn@cn aggregate is missing")
    elif aggregate_rules < args.min_aggregate:
        errors.append(
            f"geolocation-!cn@cn rules too low: {aggregate_rules} < {args.min_aggregate}"
        )
    geolocation_regions = set(manifest.get("region_pairs", {}).get("geolocation", []))
    required_regions = {"!cn"}
    if not required_regions.issubset(geolocation_regions):
        errors.append("missing required geolocation regional entry point")

    required_rule_sets = set(REQUIRED_RULE_SETS) | set(
        PROFILE_REQUIRED_RULE_SETS.get(args.profile, frozenset())
    )
    missing = sorted(required_rule_sets - names)
    if missing:
        errors.append("missing required derivative rule sets: " + ", ".join(missing))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
