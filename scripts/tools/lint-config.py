#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

from platform_capabilities import load_platform_capabilities


ROOT = Path(__file__).resolve().parents[2]

REQUIRED_DOMAIN_SOURCES = {"dlc"}
REQUIRED_IP_SOURCES = {
    "cn-ipv46",
    "cn-ipv46-apnic",
    "loyalsoldier-geoip-cn",
    "loyalsoldier-geoip-private",
    "google",
    "telegram",
    "cloudflare-ipv4",
    "cloudflare-ipv6",
    "aws",
    "fastly",
    "github",
    "apple",
    "ripe-stat",
}
REQUIRED_ASN_GROUPS = {"telegram", "netflix", "spotify", "disney"}
REQUIRED_FIRST_BATCH_SOURCES = {"google-json", "github-json", "telegram"}
SUPPORTED_PARSERS = {
    "git-tree", "cidr-text", "google-json", "github-json", "telegram",
    "aws-json", "fastly-json", "html-cidr", "ripe-stat-json",
}
ALLOWED_REQUIREMENTS = {"required", "optional"}
ALLOWED_FAMILIES = {"any", "ipv4", "ipv6", "dual"}
ALLOWED_FALLBACK_POLICIES = {"none", "ordered"}
SUPPORTED_RULE_TYPES = {
    "domain": {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX"},
    "ip": {"IP-CIDR", "IP-CIDR6"},
}
REQUIRED_PLATFORMS = {"surge", "quanx", "egern", "sing-box", "mihomo"}
CAPABILITY_SECTIONS = {"domain", "ip"}
ALLOWED_CAPABILITY_FORMATS = {"binary", "classical", "yaml"}
ALLOWED_EMPTY_POLICIES = {"omit"}
ALLOWED_COMPILERS = {"none", "sing-box", "mihomo-domain", "mihomo-ipcidr"}
ALLOWED_VERIFIERS = {"classical-domain", "classical-ip", "egern-yaml", "sing-box", "mihomo"}
PLATFORM_BRANCH_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
PLATFORM_EXTENSION_RE = re.compile(r"^[a-z0-9]+$")
ALLOWED_TRUST_VALUES = {"community", "official", "registry"}
ALLOWED_KINDS = {
    "domain": {"git", "text", "yaml"},
    "ip": {"html", "json", "json-api", "text"},
}
REQUIRED_TOOLS = {"sing-box", "mihomo"}
REQUIRED_TOOL_PLATFORMS = {"linux-amd64", "linux-arm64"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


class Reporter:
    def __init__(self) -> None:
        self.errors: list[str] = []

    def error(self, location: str, message: str) -> None:
        self.errors.append(f"{location}: {message}")

    def emit(self) -> None:
        for error in self.errors:
            print(error, file=sys.stderr)

    @property
    def ok(self) -> bool:
        return not self.errors


def load_json_object(path: Path, reporter: Reporter) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        reporter.error(str(path), "file does not exist")
        return {}
    except json.JSONDecodeError as exc:
        reporter.error(str(path), f"invalid JSON: {exc.msg}")
        return {}

    if not isinstance(data, dict):
        reporter.error(str(path), "top-level value must be a JSON object")
        return {}

    return data


def is_positive_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def validate_https_url(location: str, value: object, reporter: Reporter) -> None:
    if not isinstance(value, str) or not value:
        reporter.error(location, "URL must be a non-empty string")
        return

    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        reporter.error(location, f"URL must be absolute https: {value}")


def validate_positive_int(location: str, value: object, reporter: Reporter) -> None:
    if not is_positive_int(value):
        reporter.error(location, f"must be a positive integer, got {value!r}")


def validate_source(section: str, name: str, item: object, reporter: Reporter) -> None:
    location = f"upstreams.{section}.{name}"
    if not isinstance(item, dict):
        reporter.error(location, "source entry must be an object")
        return

    kind = item.get("kind")
    trust = item.get("trust")
    if kind not in ALLOWED_KINDS[section]:
        reporter.error(f"{location}.kind", f"unsupported kind {kind!r}")
    if trust not in ALLOWED_TRUST_VALUES:
        reporter.error(f"{location}.trust", f"unsupported trust value {trust!r}")

    if "url" not in item and "base_url" not in item:
        reporter.error(location, "must declare url or base_url")

    for key, value in item.items():
        key_location = f"{location}.{key}"
        if key == "url" or key == "base_url" or key.endswith("_url"):
            validate_https_url(key_location, value, reporter)
        elif key.startswith("min_") or key.endswith("_min_bytes"):
            validate_positive_int(key_location, value, reporter)

    parser = item.get("parser")
    if parser not in SUPPORTED_PARSERS:
        reporter.error(f"{location}.parser", f"unsupported or missing parser {parser!r}")

    health = item.get("health")
    if not isinstance(health, dict):
        reporter.error(f"{location}.health", "must be an object")
    else:
        required_health = {"requirement", "min_raw_bytes", "min_entries", "family", "fallback_policy"}
        if set(health) != required_health:
            reporter.error(f"{location}.health", f"must contain exactly {sorted(required_health)}")
        if health.get("requirement") not in ALLOWED_REQUIREMENTS:
            reporter.error(f"{location}.health.requirement", "must be required or optional")
        validate_positive_int(f"{location}.health.min_raw_bytes", health.get("min_raw_bytes"), reporter)
        validate_positive_int(f"{location}.health.min_entries", health.get("min_entries"), reporter)
        if health.get("family") not in ALLOWED_FAMILIES:
            reporter.error(f"{location}.health.family", f"unsupported family {health.get('family')!r}")
        fallback_policy = health.get("fallback_policy")
        if fallback_policy not in ALLOWED_FALLBACK_POLICIES:
            reporter.error(f"{location}.health.fallback_policy", f"unsupported policy {fallback_policy!r}")
        has_fallback = "fallback_url" in item
        if (fallback_policy == "ordered") != has_fallback:
            reporter.error(f"{location}.health.fallback_policy", "ordered requires fallback_url and fallback_url requires ordered")

    for key in item:
        if not key.endswith("_fallback_url"):
            continue
        source_url_key = key.removesuffix("_fallback_url") + "_url"
        if source_url_key not in item:
            reporter.error(f"{location}.{key}", f"fallback URL has no paired {source_url_key}")


def validate_upstreams(data: dict, reporter: Reporter) -> None:
    domain = data.get("domain")
    ip = data.get("ip")
    asn_groups = data.get("asn_groups")

    if not isinstance(domain, dict):
        reporter.error("upstreams.domain", "must be an object")
        domain = {}
    if not isinstance(ip, dict):
        reporter.error("upstreams.ip", "must be an object")
        ip = {}
    if not isinstance(asn_groups, dict):
        reporter.error("upstreams.asn_groups", "must be an object")
        asn_groups = {}

    missing_domain = REQUIRED_DOMAIN_SOURCES - set(domain)
    missing_ip = REQUIRED_IP_SOURCES - set(ip)
    missing_asn_groups = REQUIRED_ASN_GROUPS - set(asn_groups)
    if missing_domain:
        reporter.error("upstreams.domain", f"missing required sources: {sorted(missing_domain)}")
    if missing_ip:
        reporter.error("upstreams.ip", f"missing required sources: {sorted(missing_ip)}")
    if missing_asn_groups:
        reporter.error("upstreams.asn_groups", f"missing required groups: {sorted(missing_asn_groups)}")

    for name, item in sorted(domain.items()):
        validate_source("domain", name, item, reporter)
    for name, item in sorted(ip.items()):
        validate_source("ip", name, item, reporter)

    for name, values in sorted(asn_groups.items()):
        location = f"upstreams.asn_groups.{name}"
        if not isinstance(values, list) or not values:
            reporter.error(location, "must be a non-empty integer list")
            continue
        for index, value in enumerate(values):
            if not is_positive_int(value):
                reporter.error(f"{location}[{index}]", f"ASN must be a positive integer, got {value!r}")


def validate_first_batch_baselines(data: dict, reporter: Reporter) -> None:
    missing = REQUIRED_FIRST_BATCH_SOURCES - set(data)
    if missing:
        reporter.error("first_batch_baselines", f"missing required sources: {sorted(missing)}")

    for source, item in sorted(data.items()):
        location = f"first_batch_baselines.{source}"
        if source not in REQUIRED_FIRST_BATCH_SOURCES:
            reporter.error(location, "unsupported first-batch source")
        if not isinstance(item, dict):
            reporter.error(location, "baseline entry must be an object")
            continue
        validate_positive_int(f"{location}.secondary_min_total", item.get("secondary_min_total"), reporter)
        if "minimum_nonempty_list_sections" in item:
            validate_positive_int(
                f"{location}.minimum_nonempty_list_sections",
                item["minimum_nonempty_list_sections"],
                reporter,
            )
        update_policy = item.get("update_policy")
        if not isinstance(update_policy, str) or not update_policy.strip():
            reporter.error(f"{location}.update_policy", "must be a non-empty string")


def validate_string_enum(location: str, value: object, allowed: set[str], reporter: Reporter) -> None:
    if value not in allowed:
        reporter.error(location, f"unsupported value {value!r}; expected one of {sorted(allowed)}")


def validate_rule_kind_list(
    location: str,
    value: object,
    allowed: set[str],
    reporter: Reporter,
) -> set[str]:
    if not isinstance(value, list):
        reporter.error(location, "must be a list")
        return set()

    seen: set[str] = set()
    for index, item in enumerate(value):
        item_location = f"{location}[{index}]"
        if item not in allowed:
            reporter.error(item_location, f"unsupported rule kind {item!r}")
            continue
        if item in seen:
            reporter.error(item_location, f"duplicate rule kind {item}")
        seen.add(item)
    return seen


def validate_platform_capability_section(
    platform: str,
    section: str,
    value: object,
    declared_kinds: set[str],
    reporter: Reporter,
) -> None:
    location = f"domain_platform_capabilities.platforms.{platform}.{section}"
    if not isinstance(value, dict):
        reporter.error(location, "must be an object")
        return

    required_fields = {
        "extension",
        "format",
        "rule_mappings",
        "unsupported_kinds",
        "empty_policy",
        "compiler",
        "verifier",
    }
    if set(value) != required_fields:
        reporter.error(location, f"must contain exactly {sorted(required_fields)}")

    extension = value.get("extension")
    if not isinstance(extension, str) or not PLATFORM_EXTENSION_RE.fullmatch(extension):
        reporter.error(f"{location}.extension", "must be a lowercase alphanumeric extension without a dot")
    validate_string_enum(f"{location}.format", value.get("format"), ALLOWED_CAPABILITY_FORMATS, reporter)
    validate_string_enum(f"{location}.empty_policy", value.get("empty_policy"), ALLOWED_EMPTY_POLICIES, reporter)
    validate_string_enum(f"{location}.compiler", value.get("compiler"), ALLOWED_COMPILERS, reporter)
    validate_string_enum(f"{location}.verifier", value.get("verifier"), ALLOWED_VERIFIERS, reporter)

    mappings = value.get("rule_mappings")
    mapped_kinds: set[str] = set()
    if not isinstance(mappings, dict) or not mappings:
        reporter.error(f"{location}.rule_mappings", "must be a non-empty object")
    else:
        for kind, target in sorted(mappings.items()):
            kind_location = f"{location}.rule_mappings.{kind}"
            if kind not in declared_kinds:
                reporter.error(kind_location, f"unsupported {section} rule kind")
                continue
            mapped_kinds.add(kind)
            if not isinstance(target, str) or not target:
                reporter.error(kind_location, "mapping target must be a non-empty string")

    unsupported = validate_rule_kind_list(
        f"{location}.unsupported_kinds",
        value.get("unsupported_kinds"),
        declared_kinds,
        reporter,
    )
    overlap = mapped_kinds & unsupported
    if overlap:
        reporter.error(location, f"mapped and unsupported kinds overlap: {sorted(overlap)}")
    missing = declared_kinds - mapped_kinds - unsupported
    if missing:
        reporter.error(location, f"rule kinds must fail closed; unclassified kinds: {sorted(missing)}")


def validate_domain_platform_capabilities(data: dict, reporter: Reporter) -> None:
    if data.get("schema_version") != 1:
        reporter.error("domain_platform_capabilities.schema_version", "must equal 1")
    if set(data) != {"schema_version", "rule_kinds", "platforms"}:
        reporter.error(
            "domain_platform_capabilities",
            "must contain exactly schema_version, rule_kinds, and platforms",
        )

    rule_kinds = data.get("rule_kinds")
    declared: dict[str, set[str]] = {}
    if not isinstance(rule_kinds, dict):
        reporter.error("domain_platform_capabilities.rule_kinds", "must be an object")
    else:
        if set(rule_kinds) != CAPABILITY_SECTIONS:
            reporter.error(
                "domain_platform_capabilities.rule_kinds",
                f"must contain exactly {sorted(CAPABILITY_SECTIONS)}",
            )
        for section in sorted(CAPABILITY_SECTIONS):
            declared[section] = validate_rule_kind_list(
                f"domain_platform_capabilities.rule_kinds.{section}",
                rule_kinds.get(section),
                SUPPORTED_RULE_TYPES[section],
                reporter,
            )
            if declared[section] != SUPPORTED_RULE_TYPES[section]:
                reporter.error(
                    f"domain_platform_capabilities.rule_kinds.{section}",
                    f"must declare exactly {sorted(SUPPORTED_RULE_TYPES[section])}",
                )

    platforms = data.get("platforms")
    if not isinstance(platforms, dict):
        reporter.error("domain_platform_capabilities.platforms", "must be an object")
        return
    if set(platforms) != REQUIRED_PLATFORMS:
        reporter.error(
            "domain_platform_capabilities.platforms",
            f"must contain exactly {sorted(REQUIRED_PLATFORMS)}",
        )

    seen_branches: set[str] = set()
    for platform in sorted(REQUIRED_PLATFORMS):
        entry = platforms.get(platform)
        location = f"domain_platform_capabilities.platforms.{platform}"
        if not isinstance(entry, dict):
            reporter.error(location, "must be an object")
            continue
        if set(entry) != {"public_name", "branch", "domain", "ip"}:
            reporter.error(location, "must contain exactly public_name, branch, domain, and ip")
        public_name = entry.get("public_name")
        if not isinstance(public_name, str) or not public_name.strip():
            reporter.error(f"{location}.public_name", "must be a non-empty string")
        branch = entry.get("branch")
        if not isinstance(branch, str) or not PLATFORM_BRANCH_RE.fullmatch(branch):
            reporter.error(f"{location}.branch", "must be a lowercase kebab-case branch")
        elif branch in seen_branches:
            reporter.error(f"{location}.branch", f"duplicate branch {branch}")
        else:
            seen_branches.add(branch)
        for section in sorted(CAPABILITY_SECTIONS):
            validate_platform_capability_section(
                platform,
                section,
                entry.get(section),
                declared.get(section, SUPPORTED_RULE_TYPES[section]),
                reporter,
            )


def validate_tools_lock(data: dict, reporter: Reporter) -> None:
    if data.get("schema_version") != 1:
        reporter.error("tools_lock.schema_version", "must equal 1")

    tools = data.get("tools")
    if not isinstance(tools, dict):
        reporter.error("tools_lock.tools", "must be an object")
        return
    if set(tools) != REQUIRED_TOOLS:
        reporter.error("tools_lock.tools", f"must contain exactly {sorted(REQUIRED_TOOLS)}")

    repositories = {"sing-box": "SagerNet/sing-box", "mihomo": "MetaCubeX/mihomo"}
    for tool in sorted(REQUIRED_TOOLS):
        entry = tools.get(tool)
        location = f"tools_lock.tools.{tool}"
        if not isinstance(entry, dict):
            reporter.error(location, "must be an object")
            continue
        if set(entry) != {"repository", "version", "tag", "tag_commit", "platforms"}:
            reporter.error(location, "must contain exactly repository, version, tag, tag_commit, and platforms")
        version = entry.get("version")
        if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
            reporter.error(f"{location}.version", "must be a semantic x.y.z version")
            version = ""
        if entry.get("repository") != repositories[tool]:
            reporter.error(f"{location}.repository", f"must equal {repositories[tool]}")
        if entry.get("tag") != f"v{version}":
            reporter.error(f"{location}.tag", "must equal v followed by the locked version")
        tag_commit = entry.get("tag_commit")
        if not isinstance(tag_commit, str) or not COMMIT_RE.fullmatch(tag_commit):
            reporter.error(f"{location}.tag_commit", "must be a lowercase 40-character Git commit")

        platforms = entry.get("platforms")
        if not isinstance(platforms, dict):
            reporter.error(f"{location}.platforms", "must be an object")
            continue
        if set(platforms) != REQUIRED_TOOL_PLATFORMS:
            reporter.error(
                f"{location}.platforms",
                f"must contain exactly {sorted(REQUIRED_TOOL_PLATFORMS)}",
            )
        for platform in sorted(REQUIRED_TOOL_PLATFORMS):
            asset_entry = platforms.get(platform)
            asset_location = f"{location}.platforms.{platform}"
            if not isinstance(asset_entry, dict):
                reporter.error(asset_location, "must be an object")
                continue
            if set(asset_entry) != {"asset", "sha256", "binary_sha256"}:
                reporter.error(asset_location, "must contain exactly asset, sha256, and binary_sha256")
            arch = platform.removeprefix("linux-")
            if tool == "sing-box":
                expected_asset = f"sing-box-{version}-linux-{arch}.tar.gz"
            elif arch == "amd64":
                expected_asset = f"mihomo-linux-amd64-compatible-v{version}.gz"
            else:
                expected_asset = f"mihomo-linux-arm64-v{version}.gz"
            if asset_entry.get("asset") != expected_asset:
                reporter.error(f"{asset_location}.asset", f"must equal {expected_asset}")
            for digest_field in ("sha256", "binary_sha256"):
                digest = asset_entry.get(digest_field)
                if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
                    reporter.error(
                        f"{asset_location}.{digest_field}",
                        "must be a lowercase 64-character SHA-256",
                    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate repository config files.")
    parser.add_argument("--upstreams", default=str(ROOT / "config" / "upstreams.json"))
    parser.add_argument(
        "--first-batch-baselines",
        default=str(ROOT / "config" / "upstream-first-batch-baselines.json"),
    )
    parser.add_argument(
        "--domain-platform-capabilities",
        default=str(ROOT / "config" / "domain-platform-capabilities.json"),
    )
    parser.add_argument("--tools-lock", default=str(ROOT / "config" / "tools-lock.json"))
    args = parser.parse_args()

    reporter = Reporter()
    validate_upstreams(load_json_object(Path(args.upstreams), reporter), reporter)
    validate_first_batch_baselines(load_json_object(Path(args.first_batch_baselines), reporter), reporter)
    capabilities_path = Path(args.domain_platform_capabilities)
    capability_data = load_json_object(capabilities_path, reporter)
    if capability_data:
        try:
            load_platform_capabilities(capabilities_path)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            reporter.error("domain_platform_capabilities", str(exc))
    validate_tools_lock(load_json_object(Path(args.tools_lock), reporter), reporter)

    if not reporter.ok:
        reporter.emit()
        return 1

    print("config lint passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
