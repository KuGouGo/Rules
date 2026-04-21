#!/usr/bin/env python3

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


RULE_KIND_MAP = {
    "domain": "DOMAIN-SUFFIX",
    "full": "DOMAIN",
    "keyword": "DOMAIN-KEYWORD",
    "regexp": "DOMAIN-REGEX",
}

RULE_KIND_ALIASES = {
    "domain": "domain",
    "domain-suffix": "domain",
    "domain_suffix": "domain",
    "suffix": "domain",
    "full": "full",
    "domain-full": "full",
    "domain_full": "full",
    "keyword": "keyword",
    "domain-keyword": "keyword",
    "domain_keyword": "keyword",
    "regexp": "regexp",
    "regex": "regexp",
    "domain-regex": "regexp",
    "domain_regex": "regexp",
}

SINGBOX_KIND_MAP = {
    "DOMAIN": "domain",
    "DOMAIN-SUFFIX": "domain_suffix",
    "DOMAIN-KEYWORD": "domain_keyword",
    "DOMAIN-REGEX": "domain_regex",
}


@dataclass(frozen=True)
class Rule:
    kind: str
    value: str
    attrs: tuple[str, ...]


@dataclass(frozen=True)
class Include:
    target: str
    filters: tuple[str, ...]


def strip_comment(line: str) -> str:
    return line.split("#", 1)[0].strip()


def parse_rule_token(token: str) -> tuple[str, str]:
    if ":" in token:
        prefix, value = token.split(":", 1)
        kind = RULE_KIND_ALIASES.get(prefix.lower())
        if kind:
            return kind, value
        raise ValueError(f"unsupported rule prefix: {prefix}")
    return "domain", token


def normalize_rule_value(kind: str, value: str) -> str:
    if kind in ("domain", "full"):
        return value.strip().lower().rstrip(".")
    if kind == "keyword":
        return value.strip().lower()
    return value.strip()


def parse_data_file(path: Path) -> tuple[list[Rule], list[Include], list[tuple[str, Rule]]]:
    rules: list[Rule] = []
    includes: list[Include] = []
    affiliations: list[tuple[str, Rule]] = []

    with path.open("r", encoding="utf-8") as fh:
        for line_no, raw_line in enumerate(fh, start=1):
            line = strip_comment(raw_line)
            if not line:
                continue

            head, _, tail_text = line.partition(" ")
            tail_tokens = tail_text.split() if tail_text else []
            attrs: list[str] = []
            affiliate_targets: list[str] = []
            for token in tail_tokens:
                if token.startswith("@"):
                    attrs.append(token[1:])
                elif token.startswith("&"):
                    affiliate_targets.append(token[1:])

            if head.startswith("include:"):
                includes.append(Include(head.split(":", 1)[1], tuple(attrs)))
                continue

            try:
                kind, value = parse_rule_token(head)
            except ValueError as exc:
                raise ValueError(f"{path}:{line_no} {exc}") from exc
            value = normalize_rule_value(kind, value)
            if not value:
                continue
            rule = Rule(kind=RULE_KIND_MAP[kind], value=value, attrs=tuple(attrs))
            rules.append(rule)

            for target in affiliate_targets:
                # &name is the v2fly affiliation extension: the rule is also added
                # to the list named <name>, enabling cross-list rule sharing without
                # explicit include: directives.
                affiliations.append((target, rule))

    return rules, includes, affiliations


def include_matches(rule: Rule, filters: tuple[str, ...]) -> bool:
    attrs = set(rule.attrs)
    for item in filters:
        if item.startswith("-"):
            if item[1:] in attrs:
                return False
            continue
        if item not in attrs:
            return False
    return True


def render_rule(rule: Rule) -> str:
    return f"{rule.kind},{rule.value}"


def export_lists(data_dir: Path, output_dir: Path) -> None:
    direct_rules: dict[str, list[Rule]] = {}
    include_rules: dict[str, list[Include]] = {}
    affiliated_rules: dict[str, list[Rule]] = {}

    for path in sorted(data_dir.iterdir(), key=lambda item: item.name):
        if not path.is_file():
            continue
        rules, includes, affiliations = parse_data_file(path)
        direct_rules[path.name] = rules
        include_rules[path.name] = includes
        for target, rule in affiliations:
            affiliated_rules.setdefault(target, []).append(rule)

    cache: dict[str, list[Rule]] = {}
    visiting: set[str] = set()

    def resolve(name: str) -> list[Rule]:
        if name in cache:
            return cache[name]
        if name in visiting:
            raise RuntimeError(f"cyclic include detected for {name}")

        visiting.add(name)
        combined: list[Rule] = []
        combined.extend(direct_rules.get(name, []))
        combined.extend(affiliated_rules.get(name, []))

        for include in include_rules.get(name, []):
            for rule in resolve(include.target):
                if include_matches(rule, include.filters):
                    combined.append(rule)

        visiting.remove(name)
        cache[name] = combined
        return combined

    output_dir.mkdir(parents=True, exist_ok=True)
    names = sorted(set(direct_rules) | set(affiliated_rules))

    # Track which rule sets have @cn attributes
    cn_attr_sets: dict[str, list[Rule]] = {}

    for name in names:
        all_rules = resolve(name)
        rendered = sorted({render_rule(rule) for rule in all_rules})
        if not rendered:
            continue
        (output_dir / f"{name}.list").write_text("\n".join(rendered) + "\n", encoding="utf-8")

        # Check if any rules have @cn attribute (exact match only, not !cn or -!cn)
        cn_rules = [rule for rule in all_rules if "cn" in rule.attrs]
        if cn_rules:
            cn_attr_sets[name] = cn_rules

    # Generate @cn filtered versions
    # Only generate if there are Surge-compatible rules (DOMAIN/DOMAIN-SUFFIX/DOMAIN-KEYWORD)
    for name, cn_rules in cn_attr_sets.items():
        rendered = sorted({render_rule(rule) for rule in cn_rules})
        # Filter to only Surge-compatible rule types
        surge_compatible = [r for r in rendered if any(r.startswith(prefix) for prefix in ["DOMAIN,", "DOMAIN-SUFFIX,", "DOMAIN-KEYWORD,"])]
        if surge_compatible:
            output_file = output_dir / f"{name}@cn.list"
            output_file.write_text("\n".join(surge_compatible) + "\n", encoding="utf-8")
            print(f"Generated {name}@cn.list with {len(surge_compatible)} Surge-compatible rules")


def build_singbox_json(input_file: Path, output_file: Path) -> None:
    payload: dict[str, list[str]] = {}

    for raw_line in input_file.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw_line)
        if not line:
            continue
        if "," not in line:
            raise ValueError(f"invalid classical domain rule: {line}")
        kind, value = line.split(",", 1)
        kind = kind.strip().upper()
        value = value.strip()
        if kind not in SINGBOX_KIND_MAP:
            raise ValueError(f"unsupported classical domain rule type: {kind}")
        payload.setdefault(SINGBOX_KIND_MAP[kind], []).append(value)

    # version 3 is the current sing-box rule-set format (introduced in sing-box 1.8).
    data = {"version": 3, "rules": [payload]}
    output_file.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def export_filtered_list(input_file: Path, output_file: Path, filter_attr: str) -> None:
    rules, includes, affiliations = parse_data_file(input_file)

    # Filter rules that have the specified attribute
    filtered_rules = [rule for rule in rules if filter_attr in rule.attrs]

    # Render and write
    rendered = sorted({render_rule(rule) for rule in filtered_rules})
    if rendered:
        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_text("\n".join(rendered) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("data_dir")
    export_parser.add_argument("output_dir")

    filtered_parser = subparsers.add_parser("export-filtered")
    filtered_parser.add_argument("input_file")
    filtered_parser.add_argument("output_file")
    filtered_parser.add_argument("filter_attr")

    singbox_parser = subparsers.add_parser("singbox-json")
    singbox_parser.add_argument("input_file")
    singbox_parser.add_argument("output_file")

    args = parser.parse_args()

    try:
        if args.command == "export":
            export_lists(Path(args.data_dir), Path(args.output_dir))
            return 0
        if args.command == "export-filtered":
            export_filtered_list(Path(args.input_file), Path(args.output_file), args.filter_attr)
            return 0
        if args.command == "singbox-json":
            build_singbox_json(Path(args.input_file), Path(args.output_file))
            return 0
    except Exception as exc:  # pragma: no cover - surfaced to shell
        print(str(exc), file=sys.stderr)
        return 1

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
