#!/usr/bin/env python3
"""Audit canonical rule-set redundancy and cross-list overlap."""
from __future__ import annotations

import argparse
import ipaddress
import json
from collections import defaultdict
from pathlib import Path

from domain_rules import (
    compact_domain_rules,
    parse_classical_domain_file,
)
from ip_rules import parse_classical_ip_file
from platform_capabilities import load_platform_capabilities


def domain_audit(root: Path) -> dict:
    owners: dict[tuple[str, str], list[str]] = defaultdict(list)
    lists: dict[str, int] = {}
    rules_by_list: dict[str, set[tuple[str, str]]] = {}
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
        rules_by_list[path.stem] = keys
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
    # Semantic containment via an inverted rule-owner index instead of the
    # former O(lists² × rules) pairwise scan: for every rule, one owner lookup
    # per suffix label yields every list whose rules cover it. Work stays
    # near-linear in total rules (times label count) rather than multiplying
    # by the list count, which matters as the canonical tree grows.
    covered_counts: dict[tuple[str, str], int] = defaultdict(int)
    suffix_owner_cache: dict[str, list[str]] = {}
    for left, left_keys in rules_by_list.items():
        for kind, value in left_keys:
            covering = set(owners.get((kind, value), ()))
            if kind in {"DOMAIN", "DOMAIN-SUFFIX"}:
                labels = value.split(".")
                for index in range(len(labels)):
                    suffix = ".".join(labels[index:])
                    cached = suffix_owner_cache.get(suffix)
                    if cached is None:
                        cached = owners.get(("DOMAIN-SUFFIX", suffix), ())
                        suffix_owner_cache[suffix] = cached
                    if cached:
                        covering.update(cached)
            covering.discard(left)
            for right in covering:
                covered_counts[(left, right)] += 1

    containments = []
    for (left, right), covered in covered_counts.items():
        if not covered:
            continue
        left_rules = rules_by_list[left]
        exact = len(left_rules & rules_by_list[right])
        containments.append(
            {
                "additional_semantic_rules": covered - exact,
                "coverage_percent": round(covered * 100 / len(left_rules), 2),
                "covered_rules": covered,
                "exact_rules": exact,
                "left": left,
                "left_rules": len(left_rules),
                "right": right,
            }
        )
    containments.sort(
        key=lambda item: (
            -item["coverage_percent"],
            -item["covered_rules"],
            -item["additional_semantic_rules"],
            item["left"],
            item["right"],
        )
    )
    identical_groups: dict[frozenset[tuple[str, str]], list[str]] = defaultdict(list)
    for name, rules in rules_by_list.items():
        identical_groups[frozenset(rules)].append(name)
    identical = [
        {"lists": sorted(names), "rules": len(rules)}
        for rules, names in identical_groups.items()
        if len(names) > 1
    ]
    identical.sort(key=lambda item: (-item["rules"], item["lists"]))
    return {
        "full_semantic_containment_pairs": sum(
            item["covered_rules"] == item["left_rules"] for item in containments
        ),
        "identical_rule_sets": identical,
        "lists": len(lists),
        "rules": sum(lists.values()),
        "semantic_containment_pairs": len(containments),
        "internal_redundancy": internal,
        "top_exact_overlaps": top,
        "top_semantic_containments": containments[:100],
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
        "schema_version": 2,
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
        f"domain_internal={domain_internal} ip_internal={ip_internal} "
        f"domain_full_containments={result['domain']['full_semantic_containment_pairs']} "
        f"domain_identical_groups={len(result['domain']['identical_rule_sets'])}"
    )

    if args.fail_internal and (result["domain"]["internal_redundancy"] or result["ip"]["internal_redundancy"]):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
