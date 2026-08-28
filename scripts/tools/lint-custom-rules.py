#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

from common_utils import Reporter
from domain_rules import parse_classical_domain_file
from ip_rules import parse_classical_ip_file


ROOT = Path(__file__).resolve().parents[2]
RULE_FILE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


@dataclass(frozen=True)
class LocatedRule:
    family: str
    file: str
    path: Path
    line_no: int
    text: str
    value: str
    network: object | None = None

    @property
    def location(self) -> str:
        return f"{self.path}:{self.line_no}"


@dataclass(frozen=True)
class Conflict:
    family: str
    covered: LocatedRule
    covering: LocatedRule


def iter_rule_files(directory: Path) -> list[Path]:
    if not directory.exists():
        return []
    return sorted(path for path in directory.glob("*.list") if path.is_file())


def validate_rule_file_name(path: Path, reporter: Reporter) -> None:
    if not RULE_FILE_NAME_RE.fullmatch(path.stem):
        reporter.error(f"{path}:0 invalid custom rule filename; use lowercase letters, digits, and hyphens only")


def load_domain_rules(directory: Path, reporter: Reporter) -> list[LocatedRule]:
    result: list[LocatedRule] = []
    for path in iter_rule_files(directory):
        validate_rule_file_name(path, reporter)
        rules, errors = parse_classical_domain_file(
            path,
            require_canonical=True,
        )
        reporter.errors.extend(errors)
        if not rules:
            reporter.error(f"{path}:0 has no effective rules")
        result.extend(
            LocatedRule("domain", path.name, path, rule.line_no, rule.text, rule.value)
            for rule in rules
        )
    return result


def load_ip_rules(directory: Path, reporter: Reporter) -> list[LocatedRule]:
    result: list[LocatedRule] = []
    for path in iter_rule_files(directory):
        validate_rule_file_name(path, reporter)
        rules, errors = parse_classical_ip_file(path, require_canonical=True)
        reporter.errors.extend(errors)
        if not rules:
            reporter.error(f"{path}:0 has no effective rules")
        result.extend(
            LocatedRule("ip", path.name, path, rule.line_no, rule.text, rule.value, rule.network)
            for rule in rules
        )
    return result


def domain_covers(covering: LocatedRule, covered: LocatedRule) -> bool:
    if not covering.text.startswith("DOMAIN-SUFFIX,"):
        return False
    if not covered.text.startswith(("DOMAIN,", "DOMAIN-SUFFIX,")):
        return False
    return covered.value == covering.value or covered.value.endswith("." + covering.value)


def find_domain_conflicts(rules: list[LocatedRule]) -> list[Conflict]:
    conflicts: list[Conflict] = []
    for index, covered in enumerate(rules):
        for covering in rules[:index]:
            if covered.file != covering.file:
                continue
            # Equal duplicate rules cannot reach here: the parser rejects and
            # drops them while reading the file.
            if domain_covers(covering, covered):
                conflicts.append(Conflict("domain", covered, covering))
            elif domain_covers(covered, covering):
                conflicts.append(Conflict("domain", covering, covered))
    return conflicts


def find_ip_conflicts(rules: list[LocatedRule]) -> list[Conflict]:
    conflicts: list[Conflict] = []
    for index, right in enumerate(rules):
        for left in rules[:index]:
            if right.file != left.file:
                continue
            if left.network.version == right.network.version and right.network.subnet_of(left.network):
                conflicts.append(Conflict("ip", right, left))
            elif left.network.version == right.network.version and left.network.subnet_of(right.network):
                conflicts.append(Conflict("ip", left, right))
    return conflicts


def report_conflicts(conflicts: list[Conflict], reporter: Reporter) -> None:
    # find_*_conflicts only yields same-file pairs: different files may
    # intentionally overlap because they can be assigned to different policies.
    for conflict in conflicts:
        reporter.error(
            f"{conflict.covered.location} {conflict.covered.text} is covered by "
            f"{conflict.covering.text} at {conflict.covering.location}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Lint custom rule syntax and within-file redundancy.")
    parser.add_argument("--domain-dir", default=str(ROOT / "sources" / "custom" / "domain"))
    parser.add_argument("--ip-dir", default=str(ROOT / "sources" / "custom" / "ip"))
    args = parser.parse_args()

    reporter = Reporter()
    domain_rules = load_domain_rules(Path(args.domain_dir), reporter)
    ip_rules = load_ip_rules(Path(args.ip_dir), reporter)
    conflicts = find_domain_conflicts(domain_rules) + find_ip_conflicts(ip_rules)
    report_conflicts(conflicts, reporter)

    if not reporter.ok:
        reporter.emit()
        return 1
    print("custom rule quality checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
