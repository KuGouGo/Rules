#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ipaddress
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DOMAIN_RULE_TYPES = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX"}
IP_RULE_TYPES = {"IP-CIDR", "IP-CIDR6"}
DOMAIN_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
RULE_FILE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


@dataclass(frozen=True)
class Location:
    path: Path
    line_no: int

    def __str__(self) -> str:
        return f"{self.path}:{self.line_no}"


@dataclass(frozen=True)
class DomainRule:
    kind: str
    value: str
    location: Location


@dataclass(frozen=True)
class IpRule:
    kind: str
    network: ipaddress._BaseNetwork
    location: Location


class Reporter:
    def __init__(self) -> None:
        self.errors: list[str] = []

    def error(self, location: Location, message: str) -> None:
        self.errors.append(f"{location} {message}")

    def emit(self) -> None:
        for error in self.errors:
            print(error, file=sys.stderr)

    @property
    def ok(self) -> bool:
        return not self.errors


def iter_rule_files(directory: Path) -> list[Path]:
    if not directory.exists():
        return []
    return sorted(path for path in directory.glob("*.list") if path.is_file())


def validate_rule_file_name(path: Path, reporter: Reporter) -> None:
    if not RULE_FILE_NAME_RE.fullmatch(path.stem):
        reporter.error(Location(path, 0), "invalid custom rule filename; use lowercase letters, digits, and hyphens only")


def strip_inline_comment(line: str) -> str:
    return line.split("#", 1)[0].strip()


def iter_effective_lines(path: Path) -> list[tuple[Location, str]]:
    lines: list[tuple[Location, str]] = []
    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        value = strip_inline_comment(line)
        if value:
            lines.append((Location(path, line_no), value))
    return lines


def normalize_rule_type(value: str) -> str:
    return value.strip().upper().replace("_", "-")


def normalize_domain_value(kind: str, value: str) -> str:
    value = value.strip()
    if kind in {"DOMAIN", "DOMAIN-SUFFIX"}:
        return value.lower().rstrip(".")
    if kind == "DOMAIN-KEYWORD":
        return value.lower()
    return value


def validate_domain_name(location: Location, kind: str, value: str, reporter: Reporter) -> None:
    if value.startswith("."):
        reporter.error(location, f"{kind} value must not start with a dot: {value}")
        return
    if value.endswith("."):
        reporter.error(location, f"{kind} value must not end with a dot: {value}")
        return
    if "," in value:
        reporter.error(location, f"{kind} value must not contain commas: {value}")
    if any(char.isspace() for char in value):
        reporter.error(location, f"{kind} value must not contain whitespace: {value}")
    if value != value.lower():
        reporter.error(location, f"{kind} value must be lowercase: {value}")
    canonical = value.lower()
    if len(canonical) > 253:
        reporter.error(location, f"{kind} value is longer than 253 characters: {value}")
        return
    if "." not in canonical:
        reporter.error(location, f"{kind} value is too broad; use a fully qualified domain: {value}")
        return
    for label in canonical.split("."):
        if not label:
            reporter.error(location, f"{kind} value contains an empty label: {value}")
            return
        if not DOMAIN_LABEL_RE.fullmatch(label):
            reporter.error(location, f"{kind} value has an invalid label: {value}")
            return


def validate_domain_keyword(location: Location, value: str, reporter: Reporter) -> None:
    if "," in value:
        reporter.error(location, f"DOMAIN-KEYWORD value must not contain commas: {value}")
    if any(char.isspace() for char in value):
        reporter.error(location, f"DOMAIN-KEYWORD value must not contain whitespace: {value}")
    if value != value.lower():
        reporter.error(location, f"DOMAIN-KEYWORD value must be lowercase: {value}")


def validate_domain_regex(location: Location, value: str, reporter: Reporter) -> None:
    try:
        re.compile(value)
    except re.error as exc:
        reporter.error(location, f"invalid DOMAIN-REGEX pattern: {exc}")


def parse_domain_file(path: Path, reporter: Reporter) -> list[DomainRule]:
    rules: list[DomainRule] = []
    seen: dict[tuple[str, str], Location] = {}

    for location, line in iter_effective_lines(path):
        if "," not in line:
            reporter.error(location, f"invalid domain rule syntax: {line}")
            continue

        kind_raw, value_raw = line.split(",", 1)
        kind = normalize_rule_type(kind_raw)
        value = normalize_domain_value(kind, value_raw)

        if kind not in DOMAIN_RULE_TYPES:
            reporter.error(location, f"invalid domain rule type: {kind_raw.strip()}")
            continue
        if not value:
            reporter.error(location, "rule value must not be empty")
            continue

        if kind in {"DOMAIN", "DOMAIN-SUFFIX"}:
            validate_domain_name(location, kind, value_raw.strip(), reporter)
        elif kind == "DOMAIN-KEYWORD":
            validate_domain_keyword(location, value_raw.strip(), reporter)
        else:
            validate_domain_regex(location, value, reporter)

        key = (kind, value)
        if key in seen:
            reporter.error(location, f"duplicate rule; first seen at {seen[key]}: {kind},{value}")
            continue
        seen[key] = location
        rules.append(DomainRule(kind, value, location))

    return rules


def domain_is_covered_by_suffix(domain: str, suffix: str) -> bool:
    return domain == suffix or domain.endswith(f".{suffix}")


def check_domain_redundancy(rules: list[DomainRule], reporter: Reporter) -> None:
    suffixes = [rule for rule in rules if rule.kind == "DOMAIN-SUFFIX"]

    for rule in rules:
        if rule.kind not in {"DOMAIN", "DOMAIN-SUFFIX"}:
            continue
        for suffix_rule in suffixes:
            if rule == suffix_rule:
                continue
            if domain_is_covered_by_suffix(rule.value, suffix_rule.value):
                reporter.error(
                    rule.location,
                    f"{rule.kind},{rule.value} is covered by "
                    f"DOMAIN-SUFFIX,{suffix_rule.value} at {suffix_rule.location}",
                )
                break


def lint_domain_dir(directory: Path, reporter: Reporter) -> None:
    for path in iter_rule_files(directory):
        validate_rule_file_name(path, reporter)
        rules = parse_domain_file(path, reporter)
        if not rules:
            reporter.error(Location(path, 0), "has no effective rules")
        check_domain_redundancy(rules, reporter)


def parse_ip_file(path: Path, reporter: Reporter) -> list[IpRule]:
    rules: list[IpRule] = []
    seen: dict[str, Location] = {}

    for location, line in iter_effective_lines(path):
        if "," not in line:
            reporter.error(location, f"invalid IP rule syntax: {line}")
            continue

        kind_raw, value_raw = line.split(",", 1)
        kind = normalize_rule_type(kind_raw)
        value = value_raw.strip()

        if kind not in IP_RULE_TYPES:
            reporter.error(location, f"invalid IP rule type: {kind_raw.strip()}")
            continue
        if not value:
            reporter.error(location, "CIDR value must not be empty")
            continue
        if "," in value or any(char.isspace() for char in value):
            reporter.error(location, f"CIDR value must not contain commas or whitespace: {value}")
            continue

        try:
            network = ipaddress.ip_network(value, strict=False)
        except ValueError as exc:
            reporter.error(location, f"invalid CIDR value: {value} ({exc})")
            continue

        if kind == "IP-CIDR" and network.version != 4:
            reporter.error(location, f"IP-CIDR requires an IPv4 CIDR: {value}")
            continue
        if kind == "IP-CIDR6" and network.version != 6:
            reporter.error(location, f"IP-CIDR6 requires an IPv6 CIDR: {value}")
            continue

        canonical = str(network)
        if value != canonical:
            reporter.error(location, f"CIDR must be canonical; use {canonical} instead of {value}")
            continue

        if canonical in seen:
            reporter.error(location, f"duplicate CIDR; first seen at {seen[canonical]}: {value}")
            continue
        seen[canonical] = location
        rules.append(IpRule(kind, network, location))

    return rules


def check_ip_redundancy(rules: list[IpRule], reporter: Reporter) -> None:
    for rule in rules:
        for candidate in rules:
            if rule == candidate or rule.network.version != candidate.network.version:
                continue
            if rule.network.subnet_of(candidate.network):
                reporter.error(
                    rule.location,
                    f"{rule.kind},{rule.network} is covered by "
                    f"{candidate.kind},{candidate.network} at {candidate.location}",
                )
                break


def lint_ip_dir(directory: Path, reporter: Reporter) -> None:
    for path in iter_rule_files(directory):
        validate_rule_file_name(path, reporter)
        rules = parse_ip_file(path, reporter)
        if not rules:
            reporter.error(Location(path, 0), "has no effective rules")
        check_ip_redundancy(rules, reporter)


def main() -> int:
    parser = argparse.ArgumentParser(description="Lint custom rule source quality.")
    parser.add_argument("--domain-dir", default=str(ROOT / "sources" / "custom" / "domain"))
    parser.add_argument("--ip-dir", default=str(ROOT / "sources" / "custom" / "ip"))
    args = parser.parse_args()

    reporter = Reporter()
    lint_domain_dir(Path(args.domain_dir), reporter)
    lint_ip_dir(Path(args.ip_dir), reporter)

    if not reporter.ok:
        reporter.emit()
        return 1

    print("custom rule quality checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
