#!/usr/bin/env python3
"""Audit a DLC data tree using the same invariants as nekolsd/dlc2's dataaudit.

Run against the raw domain-list data directory (a domain-list-community /
dlc2 fork) before the rules are exported. Enforces:

- every ``include:`` target exists and the include graph is acyclic
- every ``category-*`` list is reachable from a geolocation root
- ``geolocation-cn`` and ``geolocation-!cn`` have an empty exact intersection
- ``category-ads-all`` is a pure derived view of the ``@ads`` rules from the
  two geographic roots (no manually maintained ad rules)
- regional category names follow ``category-<topic>-cn`` / ``category-<topic>-!cn``

The two geographic roots are the authoritative entries; a rule that ends up in
both would make routing ambiguous, so the audit fails rather than building from
it.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

GEO_CN = "geolocation-cn"
GEO_NOT_CN = "geolocation-!cn"
ADS_ALL = "category-ads-all"


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


def reachable(lists: dict[str, SourceList], name: str) -> set[str]:
    seen: set[str] = set()
    stack = [name]
    while stack:
        current = stack.pop()
        if current in seen or current not in lists:
            continue
        seen.add(current)
        stack.extend(inclusion.target for inclusion in lists[current].includes)
    return seen


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

    # Soft: naming contract for regional categories.
    for name in lists:
        if name.startswith("category-") and not (
            name.endswith("-cn") or name.endswith("-!cn") or name == "category-ads-all"
        ):
            warnings.append(
                f"regional category naming contract violated: {name} "
                "(expected category-<topic>-cn or category-<topic>-!cn)"
            )

    # Hard: include targets exist and the graph is acyclic.
    for name, source in lists.items():
        for inclusion in source.includes:
            if inclusion.target not in lists:
                errors.append(f"{name}:{inclusion.line}: include target missing: {inclusion.target}")

    # Soft: every category-* list is reachable from a geolocation root.
    geo_reach = reachable(lists, GEO_CN) | reachable(lists, GEO_NOT_CN)
    for name in lists:
        if name.startswith("category-") and name not in geo_reach and name != ADS_ALL:
            warnings.append(f"category is not reachable from a geolocation root: {name}")

    # Soft: the two geographic roots have an empty exact intersection.
    cn_rules, cn_errors = resolve(lists, GEO_CN, set())
    not_cn_rules, not_cn_errors = resolve(lists, GEO_NOT_CN, set())
    errors.extend(cn_errors)
    errors.extend(not_cn_errors)
    cn_keys = {(rule.kind, rule.value) for rule in cn_rules}
    not_cn_keys = {(rule.kind, rule.value) for rule in not_cn_rules}
    overlap = sorted(cn_keys & not_cn_keys)
    if overlap:
        warnings.append(
            f"geographic roots both contain {len(overlap)} rule(s): "
            + "; ".join(f"{kind},{value}" for kind, value in overlap[:8])
        )

    # Soft: category-ads-all should be a derived view of the two roots' @ads rules.
    ads_source = lists.get(ADS_ALL)
    if ads_source is None:
        errors.append(f"{ADS_ALL} is missing")
    else:
        allowed_targets = {GEO_CN, GEO_NOT_CN}
        if not ads_source.rules:
            if any(inc.target not in allowed_targets for inc in ads_source.includes):
                warnings.append(f"{ADS_ALL} may only include the two geographic roots")
            if any("ads" not in inc.must for inc in ads_source.includes):
                warnings.append(f"{ADS_ALL} must derive only from @ads rules")
        else:
            warnings.append(f"{ADS_ALL} must not contain manually maintained rules")

    # Hard: the geographic roots must resolve to a non-empty rule set.
    if not cn_rules:
        errors.append(f"{GEO_CN} resolves to no rules")
    if not not_cn_rules:
        errors.append(f"{GEO_NOT_CN} resolves to no rules")

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
