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
        prefix = prefix.lower()
        if prefix in RULE_KIND_MAP:
            return prefix, value
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

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw_line)
        if not line:
            continue

        tokens = line.split()
        head = tokens[0]
        tail = tokens[1:]

        if head.startswith("include:"):
            includes.append(Include(head.split(":", 1)[1], tuple(token[1:] for token in tail if token.startswith("@"))))
            continue

        kind, value = parse_rule_token(head)
        attrs = tuple(token[1:] for token in tail if token.startswith("@"))
        value = normalize_rule_value(kind, value)
        if not value:
            continue
        rule = Rule(kind=RULE_KIND_MAP[kind], value=value, attrs=attrs)
        rules.append(rule)

        for token in tail:
          if token.startswith("&"):
              affiliations.append((token[1:], rule))

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
    for name in names:
        rendered = sorted({render_rule(rule) for rule in resolve(name)})
        if not rendered:
            continue
        (output_dir / f"{name}.list").write_text("\n".join(rendered) + "\n", encoding="utf-8")


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

    data = {"version": 3, "rules": [payload]}
    output_file.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("data_dir")
    export_parser.add_argument("output_dir")

    singbox_parser = subparsers.add_parser("singbox-json")
    singbox_parser.add_argument("input_file")
    singbox_parser.add_argument("output_file")

    args = parser.parse_args()

    try:
        if args.command == "export":
            export_lists(Path(args.data_dir), Path(args.output_dir))
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
