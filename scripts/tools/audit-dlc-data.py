#!/usr/bin/env python3
"""Audit a DLC data tree using the same invariants as nekolsd/dlc2's dataaudit.

Run against the raw domain-list-community data directory (v2fly source;
the dlc2 fork used the same layout) before the rules are exported. Enforces:

- every ``include:`` target exists and the include graph is acyclic
- the effective geographic roots are disjoint after attribute filtering and
  deterministic CN precedence

Raw include graphs may overlap intentionally: ``@cn`` rules reached from the
foreign root are exported to its CN derivative, not its base list. Untagged
exact overlaps are owned by the explicit CN root and removed from the foreign
base list by the exporter.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

from domain_rules import GEOGRAPHIC_BASE_EXCLUDED_ATTRS

GEO_CN = "geolocation-cn"
GEO_NOT_CN = "geolocation-!cn"


@dataclass(frozen=True)
class Rule:
    kind: str
    value: str
    attrs: frozenset[str]


@dataclass
class Inclusion:
    target: str
    must: frozenset[str] = frozenset()
    ban: frozenset[str] = frozenset()
    line: int = 0


@dataclass
class SourceList:
    name: str
    path: Path
    rules: list[Rule] = field(default_factory=list)
    includes: list[Inclusion] = field(default_factory=list)


def split_rule_token(token: str) -> tuple[str, str]:
    if ":" in token:
        prefix, value = token.split(":", 1)
        return prefix, value
    return "domain", token


def parse_source(name: str, path: Path) -> SourceList:
    source = SourceList(name, path)
    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        head, _, tail_text = line.partition(" ")
        attrs = [token[1:] for token in tail_text.split() if token.startswith("@") and len(token) > 1]
        if head.startswith("include:"):
            source.includes.append(
                Inclusion(head.split(":", 1)[1], frozenset(attrs), frozenset(), line_no)
            )
            continue
        kind, value = split_rule_token(head)
        source.rules.append(Rule(kind, value, frozenset(attrs)))
    return source


def resolve(lists: dict[str, SourceList], name: str, visiting: set[str]) -> tuple[list[Rule], list[str]]:
    if name not in lists:
        return [], [f"include target does not exist: {name}"]
    errors: list[str] = []
    if name in visiting:
        return [], [f"include cycle detected at {name}"]
    source = lists[name]
    resolved: list[Rule] = list(source.rules)
    for inclusion in source.includes:
        if inclusion.target in visiting:
            errors.append(f"include cycle detected at {name} -> {inclusion.target}")
            continue
        child, child_errors = resolve(lists, inclusion.target, visiting | {name})
        errors.extend(child_errors)
        for rule in child:
            if inclusion.must.issubset(rule.attrs) and inclusion.ban.isdisjoint(rule.attrs):
                resolved.append(rule)
    return resolved, errors


def audit(data_dir: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    lists: dict[str, SourceList] = {}
    for path in sorted(data_dir.iterdir()):
        if path.is_file():
            lists[path.name] = parse_source(path.name, path)

    if not lists:
        errors.append("data directory is empty")
        return errors, warnings

    # Soft: naming contract for regional categories. v2fly is the canonical
    # source and freely mixes plain global categories (category-ads,
    # category-game-platforms-download) with regional variants
    # (category-ai-cn, category-ai-ru, category-media-ru-blocked), so naming
    # is not audited here. Only reachability and resolution invariants below.

    # Hard: include targets exist and the graph is acyclic.
    for name, source in lists.items():
        for inclusion in source.includes:
            if inclusion.target not in lists:
                errors.append(f"{name}:{inclusion.line}: include target missing: {inclusion.target}")

    # Model the same effective geographic partition as the exporter.
    # Attribute-filtered overlaps are intentional derivative inputs. Any
    # remaining exact overlap is deterministically owned by the CN root.
    cn_rules, cn_errors = resolve(lists, GEO_CN, set())
    not_cn_rules, not_cn_errors = resolve(lists, GEO_NOT_CN, set())
    errors.extend(cn_errors)
    errors.extend(not_cn_errors)
    cn_effective = [
        rule
        for rule in cn_rules
        if GEOGRAPHIC_BASE_EXCLUDED_ATTRS[GEO_CN].isdisjoint(rule.attrs)
    ]
    not_cn_effective = [
        rule
        for rule in not_cn_rules
        if GEOGRAPHIC_BASE_EXCLUDED_ATTRS[GEO_NOT_CN].isdisjoint(rule.attrs)
    ]
    cn_keys = {(rule.kind, rule.value) for rule in cn_effective}
    not_cn_effective = [
        rule for rule in not_cn_effective if (rule.kind, rule.value) not in cn_keys
    ]

    # Hard: both effective partitions must remain populated after filtering
    # and precedence, not merely resolve to raw include-graph entries.
    if not cn_effective:
        errors.append(f"{GEO_CN} resolves to no effective base rules")
    if not not_cn_effective:
        errors.append(f"{GEO_NOT_CN} resolves to no effective base rules")

    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_dir", type=Path)
    parser.add_argument("--warn-only", action="store_true", help="report soft issues without failing")
    args = parser.parse_args()

    errors, warnings = audit(args.data_dir)
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if errors:
        print(f"DLC data audit found {len(errors)} hard problem(s):", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(f"DLC data audit passed ({len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
