from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CAPABILITIES_FILE = ROOT / "config" / "domain-platform-capabilities.json"
SCHEMA_VERSION = 1
SECTIONS = ("domain", "ip")
CANONICAL_PLATFORMS = ("surge", "quanx", "egern", "sing-box", "mihomo")
PLATFORM_BRANCH_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
PLATFORM_EXTENSION_RE = re.compile(r"^[a-z0-9]+$")
KNOWN_RULE_KINDS = {
    "domain": {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX"},
    "ip": {"IP-CIDR", "IP-CIDR6"},
}
KNOWN_FORMATS = {"binary", "classical", "yaml"}
KNOWN_EMPTY_POLICIES = {"omit"}
KNOWN_COMPILERS = {"none", "sing-box", "mihomo-domain", "mihomo-ipcidr"}
KNOWN_VERIFIERS = {"classical-domain", "classical-ip", "egern-yaml", "sing-box", "mihomo"}


@dataclass(frozen=True)
class Capability:
    extension: str
    format: str
    rule_mappings: dict[str, str]
    unsupported_kinds: frozenset[str]
    empty_policy: str
    compiler: str
    verifier: str

    @property
    def supported_kinds(self) -> frozenset[str]:
        return frozenset(self.rule_mappings)

    def mapping_for(self, kind: str) -> str:
        if kind in self.unsupported_kinds:
            raise ValueError(f"rule kind {kind} is unsupported by this implementation")
        try:
            return self.rule_mappings[kind]
        except KeyError as exc:
            raise ValueError(f"rule kind {kind} is not classified by this implementation") from exc


@dataclass(frozen=True)
class Platform:
    public_name: str
    branch: str
    domain: Capability
    ip: Capability


@dataclass(frozen=True)
class PlatformCapabilities:
    schema_version: int
    rule_kinds: dict[str, frozenset[str]]
    platforms: dict[str, Platform]

    def iter_capabilities(self, section: str | None = None) -> Iterator[tuple[str, Platform, str, Capability]]:
        if section is not None and section not in SECTIONS:
            raise ValueError(f"unsupported capability section: {section}")
        for key, platform in self.platforms.items():
            for current_section in SECTIONS:
                if section is None or section == current_section:
                    yield key, platform, current_section, getattr(platform, current_section)

    def platform(self, name: str) -> Platform:
        try:
            return self.platforms[name]
        except KeyError as exc:
            raise ValueError(f"unknown platform capability: {name}") from exc


def _require_string(value: Any, location: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{location} must be a non-empty string")
    return value


def _load_capability(value: Any, section: str, declared: frozenset[str], location: str) -> Capability:
    if not isinstance(value, dict):
        raise ValueError(f"{location} must be an object")
    required = {
        "extension", "format", "rule_mappings", "unsupported_kinds",
        "empty_policy", "compiler", "verifier",
    }
    if set(value) != required:
        raise ValueError(f"{location} must contain exactly {sorted(required)}")
    mappings_raw = value["rule_mappings"]
    unsupported_raw = value["unsupported_kinds"]
    if not isinstance(mappings_raw, dict) or not mappings_raw:
        raise ValueError(f"{location}.rule_mappings must be a non-empty object")
    if not isinstance(unsupported_raw, list):
        raise ValueError(f"{location}.unsupported_kinds must be a list")
    mappings = {
        _require_string(kind, f"{location}.rule_mappings key"):
        _require_string(target, f"{location}.rule_mappings.{kind}")
        for kind, target in mappings_raw.items()
    }
    if not all(isinstance(kind, str) for kind in unsupported_raw):
        raise ValueError(f"{location}.unsupported_kinds must contain strings")
    if len(unsupported_raw) != len(set(unsupported_raw)):
        raise ValueError(f"{location}.unsupported_kinds must be unique")
    unsupported = frozenset(unsupported_raw)
    if set(mappings) & unsupported:
        raise ValueError(f"{location} maps kinds also declared unsupported")
    classified = set(mappings) | unsupported
    if classified != set(declared):
        raise ValueError(
            f"{location} must classify every declared {section} kind; "
            f"expected {sorted(declared)}, got {sorted(classified)}"
        )
    format_name = _require_string(value["format"], f"{location}.format")
    empty_policy = _require_string(value["empty_policy"], f"{location}.empty_policy")
    compiler = _require_string(value["compiler"], f"{location}.compiler")
    verifier = _require_string(value["verifier"], f"{location}.verifier")
    for item, allowed, item_location in (
        (format_name, KNOWN_FORMATS, f"{location}.format"),
        (empty_policy, KNOWN_EMPTY_POLICIES, f"{location}.empty_policy"),
        (compiler, KNOWN_COMPILERS, f"{location}.compiler"),
        (verifier, KNOWN_VERIFIERS, f"{location}.verifier"),
    ):
        if item not in allowed:
            raise ValueError(f"{item_location} has unsupported implementation {item!r}")
    extension = _require_string(value["extension"], f"{location}.extension")
    if not PLATFORM_EXTENSION_RE.fullmatch(extension):
        raise ValueError(f"{location}.extension must be lowercase alphanumeric without a dot")
    return Capability(
        extension=extension,
        format=format_name,
        rule_mappings=mappings,
        unsupported_kinds=unsupported,
        empty_policy=empty_policy,
        compiler=compiler,
        verifier=verifier,
    )


def load_platform_capabilities(path: Path = DEFAULT_CAPABILITIES_FILE) -> PlatformCapabilities:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or set(data) != {"schema_version", "rule_kinds", "platforms"}:
        raise ValueError("platform capability config has unsupported top-level structure")
    if data["schema_version"] != SCHEMA_VERSION:
        raise ValueError(f"unsupported platform capability schema_version: {data['schema_version']!r}")
    kinds_raw = data["rule_kinds"]
    if not isinstance(kinds_raw, dict) or set(kinds_raw) != set(SECTIONS):
        raise ValueError(f"platform capability rule_kinds must contain exactly {list(SECTIONS)}")
    rule_kinds: dict[str, frozenset[str]] = {}
    for section in SECTIONS:
        values = kinds_raw[section]
        if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
            raise ValueError(f"platform capability rule_kinds.{section} must be a string list")
        if len(values) != len(set(values)):
            raise ValueError(f"platform capability rule_kinds.{section} must be unique")
        declared = frozenset(values)
        if declared != KNOWN_RULE_KINDS[section]:
            raise ValueError(f"unsupported {section} rule-kind implementation: {sorted(declared)}")
        rule_kinds[section] = declared
    platforms_raw = data["platforms"]
    if not isinstance(platforms_raw, dict) or set(platforms_raw) != set(CANONICAL_PLATFORMS):
        raise ValueError(f"platform capability platforms must contain exactly {list(CANONICAL_PLATFORMS)}")
    platforms: dict[str, Platform] = {}
    for name in CANONICAL_PLATFORMS:
        value = platforms_raw[name]
        location = f"platforms.{name}"
        if not isinstance(value, dict) or set(value) != {"public_name", "branch", "domain", "ip"}:
            raise ValueError(f"{location} has unsupported structure")
        branch = _require_string(value["branch"], f"{location}.branch")
        if not PLATFORM_BRANCH_RE.fullmatch(branch):
            raise ValueError(f"{location}.branch must be lowercase kebab-case")
        platforms[name] = Platform(
            public_name=_require_string(value["public_name"], f"{location}.public_name"),
            branch=branch,
            domain=_load_capability(value["domain"], "domain", rule_kinds["domain"], f"{location}.domain"),
            ip=_load_capability(value["ip"], "ip", rule_kinds["ip"], f"{location}.ip"),
        )
    branches = [platform.branch for platform in platforms.values()]
    if len(branches) != len(set(branches)):
        raise ValueError("platform capability branches must be unique")
    return PlatformCapabilities(SCHEMA_VERSION, rule_kinds, platforms)


def shell_registry_rows(path: Path = DEFAULT_CAPABILITIES_FILE) -> Iterator[str]:
    registry = load_platform_capabilities(path)
    for key, platform, section, capability in registry.iter_capabilities():
        values = (
            key, platform.public_name, platform.branch, section,
            capability.extension, capability.format, capability.empty_policy,
            capability.compiler, capability.verifier,
        )
        if any("\t" in value or "\n" in value for value in values):
            raise ValueError(f"capability registry value is not shell-safe for {key}.{section}")
        yield "\t".join(values)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CAPABILITIES_FILE)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("shell-registry")
    args = parser.parse_args()
    try:
        if args.command == "shell-registry":
            print("\n".join(shell_registry_rows(args.config)))
            return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        parser.exit(1, f"{exc}\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
