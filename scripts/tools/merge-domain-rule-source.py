#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from domain_rules import (
    ParsedDomainRule,
    compact_domain_rules,
    domain_value_errors,
    is_sukka_marker_domain,
    normalize_domain_value,
    normalize_rule_type,
    parse_classical_domain_file,
)


SUPPORTED_FORMATS = {"classical", "domain-set"}
SUPPORTED_KINDS = {"DOMAIN", "DOMAIN-SUFFIX"}


def parse_source(
    path: Path,
    source_format: str,
    allowed_unsupported_rules: set[tuple[str, str]],
    ignored_domains: set[str],
) -> tuple[list[ParsedDomainRule], int]:
    rules: list[ParsedDomainRule] = []
    seen: set[tuple[str, str]] = set()
    skipped = 0

    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if source_format == "classical":
            if "," not in line:
                raise ValueError(f"{path}:{line_no} invalid classical domain rule: {line}")
            kind_raw, value_raw = line.split(",", 1)
            kind = normalize_rule_type(kind_raw)
            value = value_raw.split(",", 1)[0].strip()
            if kind not in SUPPORTED_KINDS:
                unsupported_key = (kind, value.lower().rstrip("."))
                if unsupported_key in allowed_unsupported_rules:
                    skipped += 1
                    continue
                raise ValueError(f"{path}:{line_no} unsupported domain rule type: {kind}")
        else:
            if "," in line:
                raise ValueError(f"{path}:{line_no} invalid domain-set rule: {line}")
            if line.startswith("+."):
                kind, value = "DOMAIN-SUFFIX", line[2:]
            elif line.startswith("."):
                kind, value = "DOMAIN-SUFFIX", line[1:]
            else:
                kind, value = "DOMAIN", line

        value = normalize_domain_value(kind, value)
        if value in ignored_domains:
            skipped += 1
            continue
        if is_sukka_marker_domain(value):
            skipped += 1
            continue
        errors = domain_value_errors(
            kind,
            value,
            require_canonical=True,
            allow_single_label_suffix=False,
        )
        if errors:
            raise ValueError(f"{path}:{line_no} {'; '.join(errors)}")
        key = (kind, value)
        if key not in seen:
            seen.add(key)
            rules.append(ParsedDomainRule(kind, value, line_no))

    if not rules:
        raise ValueError(f"{path}: source contains no supported domain rules")
    return rules, skipped


def merge_rules(target: Path, additions: list[ParsedDomainRule]) -> tuple[int, int]:
    current, errors = parse_classical_domain_file(
        target,
        require_canonical=True,
        allow_single_label_suffix=True,
    )
    if errors:
        raise ValueError("\n".join(errors))

    existing = {(rule.kind, rule.value) for rule in current}
    appended = [rule for rule in additions if (rule.kind, rule.value) not in existing]
    compacted, removed = compact_domain_rules(current + appended)
    target.write_text("\n".join(rule.text for rule in compacted) + "\n", encoding="utf-8")
    return len(appended), removed


def rule_conflicts_with_exclusion(rule: ParsedDomainRule, exclusions: list[ParsedDomainRule]) -> bool:
    for excluded in exclusions:
        if excluded.kind == "DOMAIN-SUFFIX" and (
            rule.value == excluded.value or rule.value.endswith(f".{excluded.value}")
        ):
            return True
        if excluded.kind == "DOMAIN" and rule.kind == "DOMAIN" and rule.value == excluded.value:
            return True
        if rule.kind == "DOMAIN-SUFFIX" and (
            excluded.value == rule.value or excluded.value.endswith(f".{rule.value}")
        ):
            return True
    return False


def parse_allowed_unsupported_rule(value: str) -> tuple[str, str]:
    kind_raw, separator, rule_value = value.partition(",")
    kind = normalize_rule_type(kind_raw)
    normalized_value = rule_value.strip().lower().rstrip(".")
    if not separator or not kind or not normalized_value or "," in rule_value:
        raise ValueError(f"invalid unsupported-rule exception: {value!r}; expected KIND,VALUE")
    if kind in SUPPORTED_KINDS:
        raise ValueError(f"unsupported-rule exception uses supported kind: {kind}")
    return kind, normalized_value


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize and merge a narrow domain rule source.")
    parser.add_argument("source")
    parser.add_argument("target")
    parser.add_argument("normalized_output")
    parser.add_argument("--format", choices=sorted(SUPPORTED_FORMATS), required=True)
    parser.add_argument("--allow-unsupported-rule", action="append", default=[])
    parser.add_argument("--ignore-domain", action="append", default=[])
    parser.add_argument("--exclude-file", action="append", default=[])
    args = parser.parse_args()

    allowed_unsupported_rules = {
        parse_allowed_unsupported_rule(value) for value in args.allow_unsupported_rule
    }
    ignored_domains = {value.lower().rstrip(".") for value in args.ignore_domain}
    rules, skipped = parse_source(
        Path(args.source),
        args.format,
        allowed_unsupported_rules,
        ignored_domains,
    )
    exclusions: list[ParsedDomainRule] = []
    for exclude_name in args.exclude_file:
        exclude_rules, errors = parse_classical_domain_file(
            Path(exclude_name),
            require_canonical=True,
            allow_single_label_suffix=True,
        )
        if errors:
            raise ValueError("\n".join(errors))
        exclusions.extend(exclude_rules)
    selected = [rule for rule in rules if not rule_conflicts_with_exclusion(rule, exclusions)]
    excluded_count = len(rules) - len(selected)

    normalized = Path(args.normalized_output)
    normalized.parent.mkdir(parents=True, exist_ok=True)
    normalized.write_text("\n".join(rule.text for rule in selected) + "\n", encoding="utf-8")
    added, removed = merge_rules(Path(args.target), selected)
    print(
        f"source={len(rules)} skipped={skipped} excluded={excluded_count} "
        f"added={added} compacted={removed}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
