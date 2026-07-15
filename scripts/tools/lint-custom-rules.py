#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

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

    @property
    def key(self) -> tuple[str, str, str, str, str]:
        return (self.family, self.covered.file, self.covered.text, self.covering.file, self.covering.text)


class Reporter:
    def __init__(self) -> None:
        self.errors: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

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
        reporter.error(f"{path}:0 invalid custom rule filename; use lowercase letters, digits, and hyphens only")


def load_domain_rules(directory: Path, reporter: Reporter) -> list[LocatedRule]:
    result: list[LocatedRule] = []
    for path in iter_rule_files(directory):
        validate_rule_file_name(path, reporter)
        rules, errors = parse_classical_domain_file(
            path,
            require_canonical=True,
            allow_single_label_suffix=path.name == "fakeip-filter.list",
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
            if covered.text == covering.text:
                conflicts.append(Conflict("domain", covered, covering))
            elif domain_covers(covering, covered):
                conflicts.append(Conflict("domain", covered, covering))
            elif domain_covers(covered, covering):
                conflicts.append(Conflict("domain", covering, covered))
    return unique_conflicts(conflicts)


def find_ip_conflicts(rules: list[LocatedRule]) -> list[Conflict]:
    conflicts: list[Conflict] = []
    for index, right in enumerate(rules):
        for left in rules[:index]:
            if left.network == right.network:
                conflicts.append(Conflict("ip", right, left))
            elif left.network.version == right.network.version and right.network.subnet_of(left.network):
                conflicts.append(Conflict("ip", right, left))
            elif left.network.version == right.network.version and left.network.subnet_of(right.network):
                conflicts.append(Conflict("ip", left, right))
    return unique_conflicts(conflicts)


def unique_conflicts(conflicts: list[Conflict]) -> list[Conflict]:
    result: list[Conflict] = []
    seen: set[tuple[str, str, str, str, str]] = set()
    for conflict in conflicts:
        if conflict.key not in seen:
            seen.add(conflict.key)
            result.append(conflict)
    return result


def parse_endpoint(value: object, location: str, reporter: Reporter) -> tuple[str, str] | None:
    if not isinstance(value, dict) or set(value) != {"file", "rule"}:
        reporter.error(f"{location} must contain exactly 'file' and 'rule'")
        return None
    file = value.get("file")
    rule = value.get("rule")
    if (
        not isinstance(file, str)
        or not file.endswith(".list")
        or "/" in file
        or "\\" in file
        or Path(file).name != file
        or not RULE_FILE_NAME_RE.fullmatch(Path(file).stem)
    ):
        reporter.error(f"{location}.file must be a bare .list filename")
        return None
    if not isinstance(rule, str) or not rule or rule != rule.strip():
        reporter.error(f"{location}.rule must be a non-empty canonical rule string")
        return None
    return file, rule


def load_allowlist(path: Path, reporter: Reporter) -> set[tuple[str, str, str, str, str]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        reporter.error(f"{path} conflict allowlist does not exist")
        return set()
    except json.JSONDecodeError as exc:
        reporter.error(f"{path} invalid JSON: {exc.msg}")
        return set()
    if (
        not isinstance(data, dict)
        or set(data) != {"version", "relations"}
        or type(data.get("version")) is not int
        or data.get("version") != 1
    ):
        reporter.error(f"{path} must be an object with version 1 and relations only; broad pair-wide allowlists are forbidden")
        return set()
    relations = data.get("relations")
    if not isinstance(relations, list):
        reporter.error(f"{path}.relations must be an array")
        return set()

    result: set[tuple[str, str, str, str, str]] = set()
    for index, item in enumerate(relations):
        location = f"{path}.relations[{index}]"
        if not isinstance(item, dict) or set(item) != {"family", "covered", "covering"}:
            reporter.error(f"{location} must contain exactly family, covered, and covering")
            continue
        family = item.get("family")
        if family not in {"domain", "ip"}:
            reporter.error(f"{location}.family must be domain or ip")
            continue
        covered = parse_endpoint(item.get("covered"), f"{location}.covered", reporter)
        covering = parse_endpoint(item.get("covering"), f"{location}.covering", reporter)
        if covered is None or covering is None:
            continue
        key = (family, covered[0], covered[1], covering[0], covering[1])
        if key in result:
            reporter.error(f"{location} duplicates an earlier allowlisted relation")
            continue
        result.add(key)
    return result


def report_conflicts(conflicts: list[Conflict], allowlist: set[tuple[str, str, str, str, str]], reporter: Reporter) -> None:
    actual = {conflict.key for conflict in conflicts}
    for conflict in conflicts:
        if conflict.key in allowlist:
            continue
        if conflict.covered.text == conflict.covering.text:
            message = f"duplicate {conflict.family} rule; first seen at {conflict.covering.location}: {conflict.covered.text}"
        else:
            message = f"{conflict.covered.text} is covered by {conflict.covering.text} at {conflict.covering.location}"
        reporter.error(f"{conflict.covered.location} {message}")
    for stale in sorted(allowlist - actual):
        family, covered_file, covered_rule, covering_file, covering_rule = stale
        reporter.error(
            f"stale conflict allowlist relation: {family} {covered_file}:{covered_rule} covered by "
            f"{covering_file}:{covering_rule}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Strictly lint all custom rule sources and global conflicts.")
    parser.add_argument("--domain-dir", default=str(ROOT / "sources" / "custom" / "domain"))
    parser.add_argument("--ip-dir", default=str(ROOT / "sources" / "custom" / "ip"))
    parser.add_argument("--conflicts", default=str(ROOT / "config" / "custom-rule-conflicts.json"))
    args = parser.parse_args()

    reporter = Reporter()
    domain_rules = load_domain_rules(Path(args.domain_dir), reporter)
    ip_rules = load_ip_rules(Path(args.ip_dir), reporter)
    allowlist = load_allowlist(Path(args.conflicts), reporter)
    conflicts = find_domain_conflicts(domain_rules) + find_ip_conflicts(ip_rules)
    report_conflicts(conflicts, allowlist, reporter)

    if not reporter.ok:
        reporter.emit()
        return 1
    print("custom rule quality checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
