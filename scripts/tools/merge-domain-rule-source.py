#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from domain_rules import (
    ParsedDomainRule,
    compact_domain_rules,
    domain_value_errors,
    normalize_domain_value,
    parse_classical_domain_file,
)


_DOMAIN_CHARS = set("abcdefghijklmnopqrstuvwxyz0123456789.-+*")


def _looks_like_domain(line: str) -> bool:
    """True when *line* resembles a domain entry (not a category label)."""
    return bool(line) and all(c in _DOMAIN_CHARS for c in line.lower()) and "." in line


def parse_source(path: Path) -> tuple[list[ParsedDomainRule], int]:
    rules: list[ParsedDomainRule] = []
    seen: set[tuple[str, str]] = set()
    skipped = 0

    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if "," in line:
            raise ValueError(f"{path}:{line_no} invalid domain-set rule: {line}")
        if line.startswith("+") and not line.startswith("+."):
            raise ValueError(f"{path}:{line_no} malformed domain-set rule: {line}")
        if line == "*" or not _looks_like_domain(line):
            skipped += 1
            continue
        stripped = line
        if stripped.startswith("*.") or stripped.startswith("+."):
            stripped = stripped[2:]
        elif stripped.startswith("."):
            stripped = stripped[1:]
        if "*" in stripped:
            kind = "DOMAIN-REGEX"
            value = "^" + stripped.replace(".", r"\.").replace("*", "[^.]+") + "$"
        elif stripped == line:
            if "." not in line:
                skipped += 1
                continue
            kind, value = "DOMAIN", line
        else:
            kind, value = "DOMAIN-SUFFIX", stripped

        value = normalize_domain_value(kind, value)
        errors = domain_value_errors(
            kind,
            value,
            require_canonical=True,
            allow_single_label_suffix=True,
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize and merge a domain-set rule source.")
    parser.add_argument("source")
    parser.add_argument("target")
    parser.add_argument("normalized_output")
    args = parser.parse_args()

    rules, skipped = parse_source(Path(args.source))
    normalized = Path(args.normalized_output)
    normalized.parent.mkdir(parents=True, exist_ok=True)
    normalized.write_text("\n".join(rule.text for rule in rules) + "\n", encoding="utf-8")
    added, removed = merge_rules(Path(args.target), rules)
    print(
        f"source={len(rules)} skipped={skipped} "
        f"added={added} compacted={removed}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
