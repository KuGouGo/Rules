#!/usr/bin/env python3
"""Audit a DLC data tree using the same invariants as nekolsd/dlc2's dataaudit.

Run against the raw domain-list-community data directory (v2fly source;
the dlc2 fork used the same layout) before the rules are exported. Enforces:

- rule tokens parse and validate under the same contract the exporter applies
  (kind aliases, value normalization, punycode-convertible domains), so invalid
  data fails here instead of after the more expensive export stage
- every ``include:`` target exists (directly or as an affiliation target) and
  the include graph is acyclic
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

from domain_rules import (
    GEOGRAPHIC_BASE_EXCLUDED_ATTRS,
    domain_value_errors,
    normalize_domain_value,
)

GEO_CN = "geolocation-cn"
GEO_NOT_CN = "geolocation-!cn"

# Mirrors the exporter's DLC token aliases (prefix -> canonical kind). The
# audit runs before the exporter; both must accept exactly the same data.
RULE_KIND_ALIASES = {
    "domain": "DOMAIN-SUFFIX",
    "domain-suffix": "DOMAIN-SUFFIX",
    "domain_suffix": "DOMAIN-SUFFIX",
    "suffix": "DOMAIN-SUFFIX",
    "full": "DOMAIN",
    "domain-full": "DOMAIN",
    "domain_full": "DOMAIN",
    "keyword": "DOMAIN-KEYWORD",
    "domain-keyword": "DOMAIN-KEYWORD",
    "domain_keyword": "DOMAIN-KEYWORD",
    "regexp": "DOMAIN-REGEX",
    "regex": "DOMAIN-REGEX",
    "domain-regex": "DOMAIN-REGEX",
    "domain_regex": "DOMAIN-REGEX",
}


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
    affiliations: list[tuple[str, Rule]] = field(default_factory=list)
    parse_errors: list[str] = field(default_factory=list)


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

        def reject(message: str, line_no: int = line_no) -> None:
            source.parse_errors.append(f"{name}:{line_no}: {message}")

        is_include = head.startswith("include:")
        attrs: set[str] = set()
        must: set[str] = set()
        affiliates: list[str] = []
        unsupported: list[str] = []
        for token in tail_text.split():
            if token.startswith("@") and len(token) > 1:
                if is_include:
                    must.add(token[1:])
                else:
                    attrs.add(token[1:])
            elif token.startswith("&") and len(token) > 1:
                if is_include:
                    unsupported.append(token)
                else:
                    affiliates.append(token[1:])
            else:
                unsupported.append(token)
        if unsupported:
            reject("unsupported trailing token(s): " + " ".join(unsupported))
            continue

        if is_include:
            target = head.split(":", 1)[1]
            if not target:
                reject("include target must not be empty")
                continue
            source.includes.append(Inclusion(target, frozenset(must), frozenset(), line_no))
            continue

        prefix, value = split_rule_token(head)
        kind = RULE_KIND_ALIASES.get(prefix.lower())
        if kind is None:
            reject(f"unsupported rule prefix: {prefix}")
            continue
        value = normalize_domain_value(kind, value)
        value_errors = domain_value_errors(
            kind,
            value,
            require_canonical=False,
            allow_single_label_suffix=True,
        )
        if value_errors:
            reject(value_errors[0])
            continue
        rule = Rule(kind, value, frozenset(attrs))
        source.rules.append(rule)
        # &name is the v2fly affiliation extension: the rule is also added to
        # the list named <name>, matching the exporter's include resolution.
        for target in affiliates:
            source.affiliations.append((target, rule))
    return source


def resolve(
    lists: dict[str, SourceList],
    affiliated: dict[str, list[Rule]],
    name: str,
    visiting: set[str],
    cache: dict[str, list[Rule]],
) -> tuple[list[Rule], list[str]]:
    """Resolve a list's effective rules, mirroring the exporter's traversal.

    Results are memoized per list. Only subtrees resolved without include
    errors are cached: error paths report context relative to the entry point,
    so their messages are not path-independent and must not be reused.
    """
    if name in cache:
        return cache[name], []
    if name not in lists:
        return [], [f"include target does not exist: {name}"]
    errors: list[str] = []
    if name in visiting:
        return [], [f"include cycle detected at {name}"]
    source = lists[name]
    resolved: list[Rule] = list(source.rules)
    resolved.extend(affiliated.get(name, ()))
    clean = True
    for inclusion in source.includes:
        if inclusion.target in visiting:
            errors.append(f"include cycle detected at {name} -> {inclusion.target}")
            clean = False
            continue
        child, child_errors = resolve(
            lists, affiliated, inclusion.target, visiting | {name}, cache
        )
        errors.extend(child_errors)
        if child_errors:
            clean = False
        for rule in child:
            if inclusion.must.issubset(rule.attrs) and inclusion.ban.isdisjoint(rule.attrs):
                resolved.append(rule)
    if clean and not errors:
        cache[name] = resolved
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

    for source in lists.values():
        errors.extend(source.parse_errors)

    affiliated: dict[str, list[Rule]] = {}
    for source in lists.values():
        for target, rule in source.affiliations:
            affiliated.setdefault(target, []).append(rule)

    # Hard: include targets exist and the graph is acyclic.
    for name, source in lists.items():
        for inclusion in source.includes:
            if inclusion.target not in lists and inclusion.target not in affiliated:
                errors.append(f"{name}:{inclusion.line}: include target missing: {inclusion.target}")

    # Model the same effective geographic partition as the exporter.
    # Attribute-filtered overlaps are intentional derivative inputs. Any
    # remaining exact overlap is deterministically owned by the CN root.
    cache: dict[str, list[Rule]] = {}
    cn_rules, cn_errors = resolve(lists, affiliated, GEO_CN, set(), cache)
    not_cn_rules, not_cn_errors = resolve(lists, affiliated, GEO_NOT_CN, set(), cache)
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
    parser.add_argument(
        "--warn-only",
        action="store_true",
        help="report problems without failing; for triaging broken trees",
    )
    args = parser.parse_args()

    errors, warnings = audit(args.data_dir)
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if errors:
        print(f"DLC data audit found {len(errors)} hard problem(s):", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        if args.warn_only:
            print("DLC data audit problems reported in warn-only mode")
            return 0
        return 1

    print(f"DLC data audit passed ({len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
