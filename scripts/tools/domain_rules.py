#!/usr/bin/env python3
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


DOMAIN_RULE_TYPES = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX"}
DOMAIN_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


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


def domain_value_errors(kind: str, value: str, *, require_canonical: bool) -> list[str]:
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
        elif "." not in canonical:
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


def parse_classical_domain_file(path: Path, *, require_canonical: bool = True) -> tuple[list[ParsedDomainRule], list[str]]:
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
        value_errors = domain_value_errors(kind, value_raw, require_canonical=require_canonical)
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
