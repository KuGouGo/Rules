#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gzip
import json
import re
import sys
from pathlib import Path


def load_snapshot_asns(paths: list[Path]) -> dict[str, set[str]]:
    descriptions: dict[str, set[str]] = {}
    for path in paths:
        opener = gzip.open if path.suffix == ".gz" else open
        with opener(path, "rt", encoding="utf-8") as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 5 or parts[2].strip() == "0":
                    continue
                descriptions.setdefault(parts[2].strip(), set()).add(parts[4].strip())
    return descriptions


def compile_patterns(patterns: list[str]) -> list[re.Pattern[str]]:
    compiled: list[re.Pattern[str]] = []
    for pattern in patterns:
        try:
            compiled.append(re.compile(pattern, re.IGNORECASE))
        except re.error as exc:
            raise ValueError(f"invalid ASN discovery pattern {pattern!r}: {exc}") from exc
    return compiled


def discover_group(
    seed: list[int],
    rules: dict,
    descriptions: dict[str, set[str]],
) -> dict:
    include = compile_patterns(rules["include"])
    exclude = compile_patterns(rules.get("exclude", []))
    max_auto_add = rules["max_auto_add"]
    seed_set = {str(asn) for asn in seed}

    candidates: list[tuple[int, str]] = []
    for asn, asn_descriptions in descriptions.items():
        if asn in seed_set:
            continue
        if not any(rx.search(text) for rx in include for text in asn_descriptions):
            continue
        if any(rx.search(text) for rx in exclude for text in asn_descriptions):
            continue
        candidates.append((int(asn), "/".join(sorted(asn_descriptions))))

    if len(candidates) > max_auto_add:
        preview = "; ".join(f"AS{asn} ({desc[:50]})" for asn, desc in sorted(candidates))
        raise ValueError(
            f"ASN discovery anomaly: {len(candidates)} candidates exceed "
            f"max_auto_add={max_auto_add}; refusing to auto-apply any: {preview}"
        )

    candidates.sort()
    discovered = [asn for asn, _ in candidates]
    for asn, desc in candidates:
        print(f"asn discovery: auto-added AS{asn} ({desc})")

    return {
        "seed": sorted(seed),
        "discovered": discovered,
        "effective": sorted(set(seed) | set(discovered)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Expand pinned asn_groups with strict-pattern discovery from iptoasn snapshots."
    )
    parser.add_argument("config", type=Path)
    parser.add_argument("snapshots", nargs="+", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    asn_groups = config.get("asn_groups", {})
    discovery_rules = config.get("asn_discovery", {})
    unknown_groups = sorted(set(discovery_rules) - set(asn_groups))
    if unknown_groups:
        raise ValueError(f"asn_discovery references unknown groups: {', '.join(unknown_groups)}")

    descriptions = load_snapshot_asns(args.snapshots)
    groups: dict[str, dict] = {}
    for group, seed in asn_groups.items():
        rules = discovery_rules.get(group)
        if rules is None:
            effective = sorted(seed)
            groups[group] = {"seed": sorted(seed), "discovered": [], "effective": effective}
            continue
        groups[group] = discover_group(seed, rules, descriptions)

    for group in sorted(groups):
        entry = groups[group]
        print(
            f"asn groups effective: {group} seed={len(entry['seed'])} "
            f"discovered={len(entry['discovered'])} effective={len(entry['effective'])}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps({"groups": groups}, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"asn group discovery failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from None
