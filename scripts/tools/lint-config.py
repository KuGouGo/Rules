#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlparse

from common_utils import Reporter
from domain_publish_policy import parse_publish_policy
from platform_capabilities import load_platform_capabilities


ROOT = Path(__file__).resolve().parents[2]

SOURCE_IMPLEMENTATIONS = {
    "domain": {
        "dlc": ("git", "git-tree"),
        "shellcrash-fakeip": ("text", "domain-set-text"),
    },
    "ip": {
        "cn-17mon-ipv4": ("text", "cidr-text"),
        "cn-ipv46-apnic": ("text", "cidr-text"),
        "cn-clang-ipv4": ("text", "cidr-text"),
        "cn-clang-ipv6": ("text", "cidr-text"),
        "google": ("json", "google-json"),
        "loyalsoldier-geoip-cn": ("text", "cidr-text"),
        "telegram": ("text", "telegram"),
        "ripe-stat": ("json-api", "ripe-stat-json"),
    },
}
REQUIRED_DOMAIN_SOURCES = set(SOURCE_IMPLEMENTATIONS["domain"])
REQUIRED_IP_SOURCES = set(SOURCE_IMPLEMENTATIONS["ip"])
REQUIRED_ASN_GROUPS = {"telegram"}
SUPPORTED_PARSERS = {
    parser
    for section in SOURCE_IMPLEMENTATIONS.values()
    for _, parser in section.values()
}
ALLOWED_REQUIREMENTS = {"required", "optional"}
ALLOWED_FAMILIES = {"any", "ipv4", "ipv6", "dual"}
ALLOWED_TRUST_VALUES = {"community", "official", "registry"}
ALLOWED_KINDS = {
    "domain": {"git", "text", "yaml"},
    "ip": {"html", "json", "json-api", "text"},
}

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

    expected_implementation = SOURCE_IMPLEMENTATIONS.get(section, {}).get(name)
    if expected_implementation is not None:
        expected_kind, expected_parser = expected_implementation
        if kind in ALLOWED_KINDS[section] and kind != expected_kind:
            reporter.error(
                f"{location}.kind",
                f"must equal {expected_kind!r} for source {name!r}, got {kind!r}",
            )
        if parser in SUPPORTED_PARSERS and parser != expected_parser:
            reporter.error(
                f"{location}.parser",
                f"must equal {expected_parser!r} for source {name!r}, got {parser!r}",
            )

    health = item.get("health")
    if not isinstance(health, dict):
        reporter.error(f"{location}.health", "must be an object")
    else:
        required_health = {"requirement", "min_raw_bytes", "min_entries", "family"}
        if set(health) != required_health:
            reporter.error(f"{location}.health", f"must contain exactly {sorted(required_health)}")
        if health.get("requirement") not in ALLOWED_REQUIREMENTS:
            reporter.error(f"{location}.health.requirement", "must be required or optional")
        validate_positive_int(f"{location}.health.min_raw_bytes", health.get("min_raw_bytes"), reporter)
        validate_positive_int(f"{location}.health.min_entries", health.get("min_entries"), reporter)
        if health.get("family") not in ALLOWED_FAMILIES:
            reporter.error(f"{location}.health.family", f"unsupported family {health.get('family')!r}")


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
    unexpected_domain = set(domain) - REQUIRED_DOMAIN_SOURCES
    unexpected_ip = set(ip) - REQUIRED_IP_SOURCES
    unexpected_asn_groups = set(asn_groups) - REQUIRED_ASN_GROUPS
    if missing_domain:
        reporter.error("upstreams.domain", f"missing required sources: {sorted(missing_domain)}")
    if missing_ip:
        reporter.error("upstreams.ip", f"missing required sources: {sorted(missing_ip)}")
    if missing_asn_groups:
        reporter.error("upstreams.asn_groups", f"missing required groups: {sorted(missing_asn_groups)}")
    if unexpected_domain:
        reporter.error("upstreams.domain", f"unsupported sources: {sorted(unexpected_domain)}")
    if unexpected_ip:
        reporter.error("upstreams.ip", f"unsupported sources: {sorted(unexpected_ip)}")
    if unexpected_asn_groups:
        reporter.error("upstreams.asn_groups", f"unsupported groups: {sorted(unexpected_asn_groups)}")

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


def validate_domain_publish_policy(data: dict, reporter: Reporter) -> None:


    location = "domain_publish_policy"
    try:
        policy = parse_publish_policy(data, location)
    except ValueError as exc:
        reporter.error(location, str(exc))
        return
    if not policy.geolocation_not_cn:
        reporter.error(
            f"{location}.geolocation_not_cn",
            "must be a list (geographic list cannot be empty)",
        )
        return
    required = {"apple", "google", "telegram"}
    missing = sorted(required - policy.geolocation_not_cn)
    if missing:
        reporter.error(
            f"{location}.geolocation_not_cn",
            f"missing README-promised lists: {missing}",
        )



def main() -> int:
    parser = argparse.ArgumentParser(description="Validate repository config files.")
    parser.add_argument("--upstreams", default=str(ROOT / "config" / "upstreams.json"))
    parser.add_argument(
        "--domain-platform-capabilities",
        default=str(ROOT / "config" / "domain-platform-capabilities.json"),
    )
    parser.add_argument(
        "--domain-publish-policy",
        default=str(ROOT / "config" / "domain-publish-policy.json"),
    )
    args = parser.parse_args()

    reporter = Reporter()
    validate_upstreams(load_json_object(Path(args.upstreams), reporter), reporter)


    try:
        load_platform_capabilities(Path(args.domain_platform_capabilities))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        reporter.error("domain_platform_capabilities", str(exc))
    validate_domain_publish_policy(
        load_json_object(Path(args.domain_publish_policy), reporter),
        reporter,
    )

    if not reporter.ok:
        reporter.emit()
        return 1

    print("config lint passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
