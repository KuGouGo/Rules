#!/usr/bin/env python3
"""Audit canonical rule-set redundancy and cross-list overlap."""
from __future__ import annotations

import argparse
import ipaddress
import json
from collections import defaultdict
from pathlib import Path

from domain_rules import compact_domain_rules, parse_classical_domain_file
from ip_rules import parse_classical_ip_file
from platform_capabilities import load_platform_capabilities


def domain_audit(root: Path) -> dict:
    owners: dict[tuple[str, str], list[str]] = defaultdict(list)
    lists: dict[str, int] = {}
    internal: dict[str, int] = {}

    for path in sorted(root.glob("*.list")):
        rules, errors = parse_classical_domain_file(path, allow_single_label_suffix=True)
        if errors:
            raise ValueError("\n".join(errors))
        compacted, removed = compact_domain_rules(rules)
        if removed:
            internal[path.stem] = removed
        keys = {(rule.kind, rule.value) for rule in compacted}
        lists[path.stem] = len(keys)
        for key in keys:
            owners[key].append(path.stem)

    pairs: dict[tuple[str, str], int] = defaultdict(int)
    for names in owners.values():
        for i, name_a in enumerate(names):
            for name_b in names[i + 1:]:
                pairs[(name_a, name_b)] += 1

    top = [
        {"left": name_a, "right": name_b, "exact_rules": count}
        for (name_a, name_b), count in sorted(pairs.items(), key=lambda item: (-item[1], item[0]))[:100]
    ]
    return {
        "lists": len(lists),
        "rules": sum(lists.values()),
        "internal_redundancy": internal,
        "top_exact_overlaps": top,
    }


def ip_audit(root: Path) -> dict:
    lists: dict[str, int] = {}
    internal: dict[str, int] = {}
    owners: dict[str, list[str]] = defaultdict(list)

    for path in sorted(root.glob("*.list")):
        rules, errors = parse_classical_ip_file(path, require_canonical=True)
        if errors:
            raise ValueError("\n".join(errors))
        values = [ipaddress.ip_network(rule.value) for rule in rules]
        compact: list[ipaddress._BaseNetwork] = []
        for version in (4, 6):
            compact.extend(ipaddress.collapse_addresses(n for n in values if n.version == version))
        if len(values) != len(compact):
            internal[path.stem] = len(values) - len(compact)
        keys = {str(network) for network in compact}
        lists[path.stem] = len(keys)
        for key in keys:
            owners[key].append(path.stem)

    pairs: dict[tuple[str, str], int] = defaultdict(int)
    for names in owners.values():
        for i, name_a in enumerate(names):
            for name_b in names[i + 1:]:
                pairs[(name_a, name_b)] += 1

    top = [
        {"left": name_a, "right": name_b, "exact_prefixes": count}
        for (name_a, name_b), count in sorted(pairs.items(), key=lambda item: (-item[1], item[0]))[:100]
    ]
    return {
        "lists": len(lists),
        "prefixes": sum(lists.values()),
        "internal_redundancy": internal,
        "top_exact_overlaps": top,
    }


def platform_loss_audit(root: Path) -> dict:
    capabilities = load_platform_capabilities().platforms
    by_platform: dict[str, dict] = {
        name: {"unsupported_rules": 0, "affected_lists": 0, "by_kind": {}}
        for name in capabilities
    }

    for path in sorted((root / "domain").glob("*.list")):
        rules, errors = parse_classical_domain_file(path, allow_single_label_suffix=True)
        if errors:
            raise ValueError("\n".join(errors))
        for platform, capability in capabilities.items():
            counts: dict[str, int] = defaultdict(int)
            for rule in rules:
                if rule.kind in capability.domain.unsupported_kinds:
                    counts[rule.kind] += 1
            if counts:
                entry = by_platform[platform]
                entry["affected_lists"] += 1
                entry["unsupported_rules"] += sum(counts.values())
                for kind, count in counts.items():
                    entry["by_kind"][kind] = entry["by_kind"].get(kind, 0) + count

    return by_platform


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit canonical rule-set redundancy and cross-list overlap.")
    parser.add_argument("canonical_root")
    parser.add_argument("--output", required=True)
    parser.add_argument("--fail-internal", action="store_true")
    args = parser.parse_args()

    root = Path(args.canonical_root)
    result = {
        "schema_version": 1,
        "domain": domain_audit(root / "domain"),
        "ip": ip_audit(root / "ip"),
        "platform_conversion_losses": platform_loss_audit(root),
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    domain_internal = sum(result["domain"]["internal_redundancy"].values())
    ip_internal = sum(result["ip"]["internal_redundancy"].values())
    print(
        f"overlap audit: domain_lists={result['domain']['lists']} "
        f"ip_lists={result['ip']['lists']} "
        f"domain_internal={domain_internal} ip_internal={ip_internal}"
    )

    if args.fail_internal and (result["domain"]["internal_redundancy"] or result["ip"]["internal_redundancy"]):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
