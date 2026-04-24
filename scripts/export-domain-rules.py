#!/usr/bin/env python3

import argparse
import json
import os
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

SURGE_KIND_SET = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD"}

QUANX_KIND_MAP = {
    "DOMAIN": "HOST",
    "DOMAIN-SUFFIX": "HOST-SUFFIX",
    "DOMAIN-KEYWORD": "HOST-KEYWORD",
}

EGERN_KIND_MAP = {
    "DOMAIN": "domain_set",
    "DOMAIN-SUFFIX": "domain_suffix_set",
    "DOMAIN-KEYWORD": "domain_keyword_set",
    "DOMAIN-REGEX": "domain_regex_set",
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


def parse_classical_domain_rules(input_file: Path) -> list[Rule]:
    rules: list[Rule] = []
    seen: set[tuple[str, str]] = set()
    allowed = set(SINGBOX_KIND_MAP)

    for raw_line in input_file.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw_line)
        if not line or "," not in line:
            continue

        kind, value = line.split(",", 1)
        kind = kind.strip().upper().replace("_", "-")
        value = value.strip()
        if kind not in allowed or not value:
            continue

        if kind in {"DOMAIN", "DOMAIN-SUFFIX"}:
            value = value.lower().rstrip(".")
        elif kind == "DOMAIN-KEYWORD":
            value = value.lower()

        if not value:
            continue

        key = (kind, value)
        if key in seen:
            continue
        seen.add(key)
        rules.append(Rule(kind=kind, value=value, attrs=tuple()))

    return rules


def write_text_lines(lines: list[str], output_file: Path) -> None:
    if lines:
        output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return
    output_file.write_text("", encoding="utf-8")


def write_normalized_classical_rules(input_file: Path, output_file: Path) -> None:
    write_text_lines([render_rule(rule) for rule in parse_classical_domain_rules(input_file)], output_file)


def build_surge_list(input_file: Path, output_file: Path) -> None:
    rules = [
        render_rule(rule)
        for rule in parse_classical_domain_rules(input_file)
        if rule.kind in SURGE_KIND_SET
    ]
    write_text_lines(rules, output_file)


def build_quanx_list(input_file: Path, output_file: Path, policy_tag: str) -> None:
    rules = [
        f"{QUANX_KIND_MAP[rule.kind]},{rule.value},{policy_tag}"
        for rule in parse_classical_domain_rules(input_file)
        if rule.kind in QUANX_KIND_MAP
    ]
    write_text_lines(rules, output_file)


def yaml_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def build_egern_yaml(input_file: Path, output_file: Path) -> None:
    sections: dict[str, list[str]] = {key: [] for key in EGERN_KIND_MAP.values()}
    seen: dict[str, set[str]] = {key: set() for key in EGERN_KIND_MAP.values()}

    for rule in parse_classical_domain_rules(input_file):
        target = EGERN_KIND_MAP.get(rule.kind)
        if not target or rule.value in seen[target]:
            continue
        seen[target].add(rule.value)
        sections[target].append(rule.value)

    chunks: list[str] = []
    for key in ("domain_set", "domain_suffix_set", "domain_keyword_set", "domain_regex_set"):
        values = sections[key]
        if not values:
            continue
        lines = [f"{key}:"]
        lines.extend(f"  - {yaml_quote(value)}" for value in values)
        chunks.append("\n".join(lines))

    if chunks:
        output_file.write_text("\n\n".join(chunks) + "\n", encoding="utf-8")
        return
    output_file.write_text("", encoding="utf-8")


def build_mihomo_text(input_file: Path, output_file: Path) -> None:
    entries: list[str] = []
    seen: set[str] = set()

    for rule in parse_classical_domain_rules(input_file):
        if rule.kind == "DOMAIN":
            normalized = rule.value
        elif rule.kind == "DOMAIN-SUFFIX":
            normalized = f".{rule.value}"
        else:
            continue

        if normalized in seen:
            continue
        seen.add(normalized)
        entries.append(normalized)

    write_text_lines(entries, output_file)


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
    not_cn_attr_sets: dict[str, list[Rule]] = {}

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

        # Check if any rules have @!cn attribute (non-CN rules)
        not_cn_rules = [rule for rule in all_rules if "!cn" in rule.attrs]
        if not_cn_rules:
            not_cn_attr_sets[name] = not_cn_rules

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

    # Generate @!cn filtered versions
    for name, not_cn_rules in not_cn_attr_sets.items():
        rendered = sorted({render_rule(rule) for rule in not_cn_rules})
        # Filter to only Surge-compatible rule types
        surge_compatible = [r for r in rendered if any(r.startswith(prefix) for prefix in ["DOMAIN,", "DOMAIN-SUFFIX,", "DOMAIN-KEYWORD,"])]
        if surge_compatible:
            output_file = output_dir / f"{name}@!cn.list"
            output_file.write_text("\n".join(surge_compatible) + "\n", encoding="utf-8")
            print(f"Generated {name}@!cn.list with {len(surge_compatible)} Surge-compatible rules")


def build_singbox_json(input_file: Path, output_file: Path) -> None:
    payload: dict[str, list[str]] = {}

    for rule in parse_classical_domain_rules(input_file):
        kind = rule.kind
        value = rule.value
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


def trace_cli_invocation(command: str) -> None:
    trace_file = os.environ.get("RULES_TRACE_DOMAIN_CLI_FILE")
    if not trace_file:
        return
    Path(trace_file).parent.mkdir(parents=True, exist_ok=True)
    with Path(trace_file).open("a", encoding="utf-8") as fh:
        fh.write(f"{command}\n")


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

    normalize_parser = subparsers.add_parser("normalize-classical")
    normalize_parser.add_argument("input_file")
    normalize_parser.add_argument("output_file")

    surge_parser = subparsers.add_parser("surge-list")
    surge_parser.add_argument("input_file")
    surge_parser.add_argument("output_file")

    quanx_parser = subparsers.add_parser("quanx-list")
    quanx_parser.add_argument("input_file")
    quanx_parser.add_argument("output_file")
    quanx_parser.add_argument("policy_tag")

    egern_parser = subparsers.add_parser("egern-yaml")
    egern_parser.add_argument("input_file")
    egern_parser.add_argument("output_file")

    mihomo_parser = subparsers.add_parser("mihomo-text")
    mihomo_parser.add_argument("input_file")
    mihomo_parser.add_argument("output_file")

    singbox_parser = subparsers.add_parser("singbox-json")
    singbox_parser.add_argument("input_file")
    singbox_parser.add_argument("output_file")

    args = parser.parse_args()
    trace_cli_invocation(args.command)

    try:
        if args.command == "export":
            export_lists(Path(args.data_dir), Path(args.output_dir))
            return 0
        if args.command == "export-filtered":
            export_filtered_list(Path(args.input_file), Path(args.output_file), args.filter_attr)
            return 0
        if args.command == "normalize-classical":
            write_normalized_classical_rules(Path(args.input_file), Path(args.output_file))
            return 0
        if args.command == "surge-list":
            build_surge_list(Path(args.input_file), Path(args.output_file))
            return 0
        if args.command == "quanx-list":
            build_quanx_list(Path(args.input_file), Path(args.output_file), args.policy_tag)
            return 0
        if args.command == "egern-yaml":
            build_egern_yaml(Path(args.input_file), Path(args.output_file))
            return 0
        if args.command == "mihomo-text":
            build_mihomo_text(Path(args.input_file), Path(args.output_file))
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
