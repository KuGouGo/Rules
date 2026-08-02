#!/usr/bin/env python3
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


DOMAIN_RULE_TYPES = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX"}
DOMAIN_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
SUKKA_MARKER_SUFFIX = ".skk.moe"


@dataclass(frozen=True)
class ParsedDomainRule:
    kind: str
    value: str
    line_no: int

    @property
    def text(self) -> str:
        return f"{self.kind},{self.value}"


def strip_inline_comment(line: str) -> str:
    """Ignore full-line comments while preserving literal '#' in rule values."""
    return "" if line.lstrip().startswith("#") else line.rstrip("\r")


def normalize_rule_type(value: str) -> str:
    return value.strip().upper().replace("_", "-")


def normalize_domain_value(kind: str, value: str) -> str:
    value = value.strip()
    if kind in {"DOMAIN", "DOMAIN-SUFFIX"}:
        return value.lower().rstrip(".")
    if kind == "DOMAIN-KEYWORD":
        return value.lower()
    return value


def is_sukka_marker_domain(value: str) -> bool:
    """Match Sukka ruleset watermark domains.

    Sukka embeds an un-routable fake domain as a copy-protection marker (e.g.
    ``7h15_ru1353t_1s_m4d3_by_5ukk4w.skk.moe``). The leetspeak payload changes
    between releases, so match on the stable ``.skk.moe`` suffix plus the
    underscore that always makes the domain an invalid DNS label.
    """
    lowered = value.strip().lower().rstrip(".")
    return lowered.endswith(SUKKA_MARKER_SUFFIX) and "_" in lowered


def domain_value_errors(
    kind: str,
    value: str,
    *,
    require_canonical: bool,
    allow_single_label_suffix: bool = False,
) -> list[str]:
    errors: list[str] = []
    if not value:
        return ["rule value must not be empty"]
    if kind in {"DOMAIN", "DOMAIN-SUFFIX"}:
        if value.startswith("."):
            errors.append(f"{kind} value must not start with a dot: {value}")
        if value.endswith("."):
            errors.append(f"{kind} value must not end with a dot: {value}")
        if "," in value:
            errors.append(f"{kind} value must not contain commas: {value}")
        if any(char.isspace() for char in value):
            errors.append(f"{kind} value must not contain whitespace: {value}")
        if require_canonical and value != value.lower():
            errors.append(f"{kind} value must be lowercase: {value}")
        canonical = value.lower().rstrip(".")
        if len(canonical) > 253:
            errors.append(f"{kind} value is longer than 253 characters: {value}")
        elif "." not in canonical and not (allow_single_label_suffix and kind == "DOMAIN-SUFFIX"):
            errors.append(f"{kind} value is too broad; use a fully qualified domain: {value}")
        else:
            for label in canonical.split("."):
                if not label:
                    errors.append(f"{kind} value contains an empty label: {value}")
                    break
                if not DOMAIN_LABEL_RE.fullmatch(label):
                    errors.append(f"{kind} value has an invalid label: {value}")
                    break
    elif kind == "DOMAIN-KEYWORD":
        if "," in value:
            errors.append(f"DOMAIN-KEYWORD value must not contain commas: {value}")
        if any(char.isspace() for char in value):
            errors.append(f"DOMAIN-KEYWORD value must not contain whitespace: {value}")
        if require_canonical and value != value.lower():
            errors.append(f"DOMAIN-KEYWORD value must be lowercase: {value}")
    else:
        try:
            re.compile(value)
        except re.error as exc:
            errors.append(f"invalid DOMAIN-REGEX pattern: {exc}")
    return errors


def compact_domain_rules(rules: list[ParsedDomainRule]) -> tuple[list[ParsedDomainRule], int]:
    """Remove rules made redundant by an equal or parent DOMAIN-SUFFIX.

    Keyword and regular-expression rules are intentionally opaque. The first
    occurrence order is preserved so canonical output remains deterministic.
    """
    suffixes = {rule.value for rule in rules if rule.kind == "DOMAIN-SUFFIX"}
    compacted: list[ParsedDomainRule] = []
    removed = 0

    for rule in rules:
        if rule.kind not in {"DOMAIN", "DOMAIN-SUFFIX"}:
            compacted.append(rule)
            continue
        labels = rule.value.split(".")
        start = 1 if rule.kind == "DOMAIN-SUFFIX" else 0
        covered = any(".".join(labels[index:]) in suffixes for index in range(start, len(labels)))
        if covered:
            removed += 1
        else:
            compacted.append(rule)
    return compacted, removed


def compact_classical_domain_file(path: Path) -> tuple[int, int]:
    rules, errors = parse_classical_domain_file(
        path,
        require_canonical=True,
        allow_single_label_suffix=True,
    )
    if errors:
        raise ValueError("\n".join(errors))
    compacted, removed = compact_domain_rules(rules)
    text = "\n".join(rule.text for rule in compacted)
    path.write_text(text + ("\n" if text else ""), encoding="utf-8")
    return len(rules), removed


def parse_classical_domain_file(
    path: Path,
    *,
    require_canonical: bool = True,
    allow_single_label_suffix: bool = False,
) -> tuple[list[ParsedDomainRule], list[str]]:
    rules: list[ParsedDomainRule] = []
    errors: list[str] = []
    seen: dict[tuple[str, str], int] = {}

    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = strip_inline_comment(raw_line)
        if not line.strip():
            continue
        if "," not in line:
            errors.append(f"{path}:{line_no} invalid domain rule syntax: {line}")
            continue
        kind_raw, value_raw = line.split(",", 1)
        kind = normalize_rule_type(kind_raw)
        if kind not in DOMAIN_RULE_TYPES:
            errors.append(f"{path}:{line_no} invalid domain rule type: {kind_raw}")
            continue
        if require_canonical and kind_raw != kind:
            errors.append(f"{path}:{line_no} rule type must be canonical; use {kind} instead of {kind_raw}")
            continue
        if require_canonical and value_raw != value_raw.strip():
            errors.append(f"{path}:{line_no} rule value must not have surrounding whitespace: {value_raw!r}")
            continue
        value_errors = domain_value_errors(
            kind,
            value_raw,
            require_canonical=require_canonical,
            allow_single_label_suffix=allow_single_label_suffix,
        )
        errors.extend(f"{path}:{line_no} {message}" for message in value_errors)
        if value_errors:
            continue
        value = normalize_domain_value(kind, value_raw)
        if require_canonical and value_raw != value:
            errors.append(f"{path}:{line_no} rule value must be canonical; use {value} instead of {value_raw}")
            continue
        key = (kind, value)
        if key in seen:
            errors.append(f"{path}:{line_no} duplicate rule; first seen at {path}:{seen[key]}: {kind},{value}")
            continue
        seen[key] = line_no
        rules.append(ParsedDomainRule(kind, value, line_no))
    return rules, errors
