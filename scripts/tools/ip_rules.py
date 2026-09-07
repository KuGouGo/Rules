#!/usr/bin/env python3
from __future__ import annotations

import ipaddress
from dataclasses import dataclass
from pathlib import Path


IP_RULE_TYPES = {"IP-CIDR", "IP-CIDR6"}


@dataclass(frozen=True)
class ParsedIpRule:
    kind: str
    network: ipaddress.IPv4Network | ipaddress.IPv6Network
    line_no: int

    @property
    def value(self) -> str:
        return str(self.network)

    @property
    def text(self) -> str:
        return f"{self.kind},{self.network}"


def strip_inline_comment(line: str) -> str:
    value, marker, _ = line.partition("#")
    return value.rstrip() if marker else value.rstrip("\r")


def parse_classical_ip_file(path: Path, *, require_canonical: bool = True) -> tuple[list[ParsedIpRule], list[str]]:
    rules: list[ParsedIpRule] = []
    errors: list[str] = []
    seen: dict[str, int] = {}

    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = strip_inline_comment(raw_line)
        if not line.strip():
            continue
        if line.count(",") != 1:
            errors.append(f"{path}:{line_no} invalid IP rule syntax: {line}")
            continue
        kind_raw, value_raw = line.split(",", 1)
        kind = kind_raw.strip().upper().replace("_", "-")
        if kind not in IP_RULE_TYPES:
            errors.append(f"{path}:{line_no} invalid IP rule type: {kind_raw}")
            continue
        if require_canonical and kind_raw != kind:
            errors.append(f"{path}:{line_no} rule type must be canonical; use {kind} instead of {kind_raw}")
            continue
        if require_canonical and value_raw != value_raw.strip():
            errors.append(f"{path}:{line_no} CIDR value must not have surrounding whitespace: {value_raw!r}")
            continue
        value = value_raw.strip()
        if not value:
            errors.append(f"{path}:{line_no} CIDR value must not be empty")
            continue
        if any(char.isspace() for char in value):
            errors.append(f"{path}:{line_no} CIDR value must not contain whitespace: {value}")
            continue
        try:
            network = ipaddress.ip_network(value, strict=False)
        except ValueError as exc:
            errors.append(f"{path}:{line_no} invalid CIDR value: {value} ({exc})")
            continue
        if kind == "IP-CIDR" and network.version != 4:
            errors.append(f"{path}:{line_no} IP-CIDR requires an IPv4 CIDR: {value}")
            continue
        if kind == "IP-CIDR6" and network.version != 6:
            errors.append(f"{path}:{line_no} IP-CIDR6 requires an IPv6 CIDR: {value}")
            continue
        canonical = str(network)
        if require_canonical and value != canonical:
            errors.append(f"{path}:{line_no} CIDR must be canonical; use {canonical} instead of {value}")
            continue
        if canonical in seen:
            errors.append(f"{path}:{line_no} duplicate CIDR; first seen at {path}:{seen[canonical]}: {canonical}")
            continue
        seen[canonical] = line_no
        rules.append(ParsedIpRule(kind, network, line_no))
    return rules, errors


def write_plain_cidrs(rules: list[ParsedIpRule], output_file: Path) -> None:
    text = "\n".join(rule.value for rule in rules)
    output_file.write_text(text + ("\n" if text else ""), encoding="utf-8")
