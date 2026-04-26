#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CAPABILITIES_FILE = ROOT / "config" / "domain-platform-capabilities.json"


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


def load_platform_capabilities(path: Path = CAPABILITIES_FILE) -> dict[str, set[str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {platform: set(kinds) for platform, kinds in data.items()}


PLATFORM_CAPABILITIES = load_platform_capabilities()
SURGE_KIND_SET = PLATFORM_CAPABILITIES["surge"]
MIHOMO_MRS_KIND_SET = PLATFORM_CAPABILITIES["mihomo-mrs"]
MIHOMO_MRS_SKIP_WARN_PERCENT = int(os.environ.get("MIHOMO_MRS_SKIP_WARN_PERCENT", "30"))
DEFAULT_SINGBOX_RULE_SET_VERSION = 4
SINGBOX_RULE_SET_VERSION = int(os.environ.get("SINGBOX_RULE_SET_VERSION", DEFAULT_SINGBOX_RULE_SET_VERSION))


def count_rule_kinds(rules: list[Rule]) -> dict[str, int]:
    counts = {kind: 0 for kind in SINGBOX_KIND_MAP}
    for rule in rules:
        counts[rule.kind] = counts.get(rule.kind, 0) + 1
    return counts


def print_platform_skip_summary(name: str, rules: list[Rule]) -> None:
    counts = count_rule_kinds(rules)
    for platform, supported in PLATFORM_CAPABILITIES.items():
        skipped = {kind: count for kind, count in counts.items() if count and kind not in supported}
        if skipped:
            details = ", ".join(f"{kind}={count}" for kind, count in sorted(skipped.items()))
            print(f"domain summary: {name} skips unsupported rules for {platform}: {details}", file=sys.stderr)


def print_mihomo_mrs_skip_summary(input_file: Path, rules: list[Rule]) -> None:
    skipped = {
        kind: count
        for kind, count in count_rule_kinds(rules).items()
        if count and kind not in MIHOMO_MRS_KIND_SET
    }
    if skipped:
        details = ", ".join(f"{kind}={count}" for kind, count in sorted(skipped.items()))
        skipped_total = sum(skipped.values())
        total = len(rules)
        skipped_percent = skipped_total * 100 // total if total else 0
        print(f"mihomo mrs summary: {input_file.name} skips unsupported rules: {details}", file=sys.stderr)
        if skipped_percent > MIHOMO_MRS_SKIP_WARN_PERCENT:
            print(
                f"mihomo mrs warning: {input_file.name} skips {skipped_percent}% unsupported rules "
                f"(threshold {MIHOMO_MRS_SKIP_WARN_PERCENT}%)",
                file=sys.stderr,
            )


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


@dataclass(frozen=True)
class RuleSetOutput:
    rules: list[Rule]
    rules_by_attr: dict[str, list[Rule]]


def collect_rule_set_output(rules: list[Rule]) -> RuleSetOutput:
    unique_rules: list[Rule] = []
    rules_by_attr: dict[str, list[Rule]] = {}
    seen_rules: set[tuple[str, str]] = set()
    seen_by_attr: dict[str, set[tuple[str, str]]] = {}

    for rule in rules:
        key = (rule.kind, rule.value)
        if key not in seen_rules:
            seen_rules.add(key)
            unique_rules.append(rule)

        for attr in rule.attrs:
            attr_seen = seen_by_attr.setdefault(attr, set())
            if key in attr_seen:
                continue
            attr_seen.add(key)
            rules_by_attr.setdefault(attr, []).append(rule)

    return RuleSetOutput(unique_rules, rules_by_attr)


def is_region_named_list(name: str) -> bool:
    return name == "cn" or name.endswith("-cn") or name.endswith("-!cn")


def split_attr_rule_set_name(name: str) -> tuple[str, str] | None:
    if name.count("@") != 1:
        return None
    base, separator, attr = name.partition("@")
    if not separator or not base or not attr:
        return None
    return base, attr


def last_rule_set_name_segment(name: str) -> str:
    parts = name.split("-")
    if len(parts) > 1:
        return parts[-1]
    return name


def is_redundant_attr_rule_set_name(base: str, attr: str) -> bool:
    return last_rule_set_name_segment(base) == attr


def classify_rule_set_name(name: str) -> dict[str, object]:
    attr_parts = split_attr_rule_set_name(name)
    if attr_parts:
        base, attr = attr_parts
        return {
            "kind": "attr",
            "base": base,
            "attr": attr,
            "base_kind": "regional" if is_region_named_list(base) else "base",
        }
    if is_region_named_list(name):
        return {"kind": "regional"}
    return {"kind": "base"}


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


def write_text_lines_if_nonempty(lines: list[str], output_file: Path) -> bool:
    if not lines:
        return False
    write_text_lines(lines, output_file)
    return True


def write_normalized_classical_rules(input_file: Path, output_file: Path) -> None:
    write_text_lines([render_rule(rule) for rule in parse_classical_domain_rules(input_file)], output_file)


def build_surge_lines(rules: list[Rule]) -> list[str]:
    return [
        render_rule(rule)
        for rule in rules
        if rule.kind in SURGE_KIND_SET
    ]


def build_surge_list(input_file: Path, output_file: Path) -> None:
    write_text_lines(build_surge_lines(parse_classical_domain_rules(input_file)), output_file)


def build_quanx_lines(rules: list[Rule], policy_tag: str) -> list[str]:
    return [
        f"{QUANX_KIND_MAP[rule.kind]},{rule.value},{policy_tag}"
        for rule in rules
        if rule.kind in QUANX_KIND_MAP
    ]


def build_quanx_list(input_file: Path, output_file: Path, policy_tag: str) -> None:
    write_text_lines(build_quanx_lines(parse_classical_domain_rules(input_file), policy_tag), output_file)


def yaml_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def build_egern_yaml_text(rules: list[Rule]) -> str:
    sections: dict[str, list[str]] = {key: [] for key in EGERN_KIND_MAP.values()}
    seen: dict[str, set[str]] = {key: set() for key in EGERN_KIND_MAP.values()}

    for rule in rules:
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
        return "\n\n".join(chunks) + "\n"
    return ""


def build_egern_yaml(input_file: Path, output_file: Path) -> None:
    output_file.write_text(build_egern_yaml_text(parse_classical_domain_rules(input_file)), encoding="utf-8")


def build_mihomo_lines(input_file: Path, rules: list[Rule]) -> list[str]:
    entries: list[str] = []
    seen: set[str] = set()
    print_mihomo_mrs_skip_summary(input_file, rules)

    for rule in rules:
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

    return entries


def build_mihomo_text(input_file: Path, output_file: Path) -> None:
    rules = parse_classical_domain_rules(input_file)
    write_text_lines(build_mihomo_lines(input_file, rules), output_file)


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

    def write_rule_set(name: str, rules: list[Rule]) -> None:
        if not rules:
            return
        print_platform_skip_summary(name, rules)
        rendered = [render_rule(rule) for rule in rules]
        (output_dir / f"{name}.list").write_text("\n".join(rendered) + "\n", encoding="utf-8")

    for name in names:
        rule_set_output = collect_rule_set_output(resolve(name))
        write_rule_set(name, rule_set_output.rules)

        for attr, rules in sorted(rule_set_output.rules_by_attr.items()):
            if is_redundant_attr_rule_set_name(name, attr):
                continue
            write_rule_set(f"{name}@{attr}", rules)


def build_singbox_payload(rules: list[Rule]) -> dict[str, list[str]]:
    payload: dict[str, list[str]] = {}

    for rule in rules:
        kind = rule.kind
        value = rule.value
        payload.setdefault(SINGBOX_KIND_MAP[kind], []).append(value)

    return payload


def build_singbox_json_text(rules: list[Rule]) -> str:
    data = {"version": SINGBOX_RULE_SET_VERSION, "rules": [build_singbox_payload(rules)]}
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


def build_singbox_json(input_file: Path, output_file: Path) -> None:
    output_file.write_text(
        build_singbox_json_text(parse_classical_domain_rules(input_file)),
        encoding="utf-8",
    )


def sorted_classical_rule_files(rule_dir: Path) -> list[Path]:
    return sorted(rule_dir.glob("*.list"), key=lambda item: item.name)


def domain_rule_manifest(rule_dir: Path) -> dict[str, object]:
    lists: list[dict[str, object]] = []
    by_kind: dict[str, int] = {}
    by_attr: dict[str, int] = {}

    for input_file in sorted_classical_rule_files(rule_dir):
        name = input_file.stem
        rules = parse_classical_domain_rules(input_file)
        entry = {
            "name": name,
            "file": input_file.name,
            "rules": len(rules),
        }
        classification = classify_rule_set_name(name)
        entry.update(classification)
        lists.append(entry)

        kind = str(classification["kind"])
        by_kind[kind] = by_kind.get(kind, 0) + 1
        attr = classification.get("attr")
        if isinstance(attr, str):
            by_attr[attr] = by_attr.get(attr, 0) + 1

    return {
        "total": len(lists),
        "by_kind": dict(sorted(by_kind.items())),
        "by_attr": dict(sorted(by_attr.items())),
        "lists": lists,
    }


def write_domain_rule_manifest(rule_dir: Path, output_file: Path) -> None:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(
        json.dumps(domain_rule_manifest(rule_dir), ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def reset_output_dirs(*dirs: Path) -> None:
    for directory in dirs:
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True, exist_ok=True)


def render_text_platform_dirs(rule_dir: Path, surge_dir: Path, quanx_dir: Path, egern_dir: Path) -> None:
    reset_output_dirs(surge_dir, quanx_dir, egern_dir)

    for input_file in sorted_classical_rule_files(rule_dir):
        base = input_file.stem
        rules = parse_classical_domain_rules(input_file)

        surge_lines = build_surge_lines(rules)
        write_text_lines_if_nonempty(surge_lines, surge_dir / f"{base}.list")

        quanx_lines = build_quanx_lines(rules, base)
        write_text_lines_if_nonempty(quanx_lines, quanx_dir / f"{base}.list")

        egern_text = build_egern_yaml_text(rules)
        if egern_text:
            (egern_dir / f"{base}.yaml").write_text(egern_text, encoding="utf-8")


def build_binary_input_dir(rule_dir: Path, output_dir: Path) -> None:
    reset_output_dirs(output_dir)

    for input_file in sorted_classical_rule_files(rule_dir):
        base = input_file.stem
        rules = parse_classical_domain_rules(input_file)
        (output_dir / f"{base}.json").write_text(
            build_singbox_json_text(rules),
            encoding="utf-8",
        )
        write_text_lines(build_mihomo_lines(input_file, rules), output_dir / f"{base}.mihomo.txt")


def export_filtered_list(input_file: Path, output_file: Path, filter_attr: str) -> None:
    rules, includes, affiliations = parse_data_file(input_file)

    # Filter rules that have the specified attribute
    filtered_rules = [rule for rule in rules if filter_attr in rule.attrs]

    # Render and write while preserving upstream order.
    rendered = [render_rule(rule) for rule in filtered_rules]
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

    text_dirs_parser = subparsers.add_parser("text-platform-dirs")
    text_dirs_parser.add_argument("rule_dir")
    text_dirs_parser.add_argument("surge_dir")
    text_dirs_parser.add_argument("quanx_dir")
    text_dirs_parser.add_argument("egern_dir")

    binary_input_parser = subparsers.add_parser("binary-input-dir")
    binary_input_parser.add_argument("rule_dir")
    binary_input_parser.add_argument("output_dir")

    manifest_parser = subparsers.add_parser("domain-rule-manifest")
    manifest_parser.add_argument("rule_dir")
    manifest_parser.add_argument("output_file")

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
        if args.command == "text-platform-dirs":
            render_text_platform_dirs(
                Path(args.rule_dir),
                Path(args.surge_dir),
                Path(args.quanx_dir),
                Path(args.egern_dir),
            )
            return 0
        if args.command == "binary-input-dir":
            build_binary_input_dir(Path(args.rule_dir), Path(args.output_dir))
            return 0
        if args.command == "domain-rule-manifest":
            write_domain_rule_manifest(Path(args.rule_dir), Path(args.output_file))
            return 0
    except Exception as exc:  # pragma: no cover - surfaced to shell
        print(str(exc), file=sys.stderr)
        return 1

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
