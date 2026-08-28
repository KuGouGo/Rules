#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
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
        "cn-ipv46-apnic": ("text", "cidr-text"),
        "cn-clang-ipv4": ("text", "cidr-text"),
        "cn-clang-ipv6": ("text", "cidr-text"),
        "google": ("json", "google-json"),
        "telegram": ("text", "telegram"),
        "cloudflare-ipv4": ("text", "cidr-text"),
        "cloudflare-ipv6": ("text", "cidr-text"),
        "cloudfront": ("json", "cloudfront-json"),
        "fastly": ("json", "fastly-json"),
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
ALLOWED_FALLBACK_POLICIES = {"none", "ordered"}
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
    """Lint the publish policy through the shared strict loader.

    The exporter parses this file with domain_publish_policy.parse_publish_policy,
    so linting the same bytes through a second hand-written schema copy would
    only guarantee drift. Checks below the loader are repo-level invariants the
    shared loader deliberately does not own.
    """
    location = "domain_publish_policy"
    try:
        policy = parse_publish_policy(data, location)
    except ValueError as exc:
        reporter.error(location, str(exc))
        return
    if not policy.common_geolocation_not_cn:
        reporter.error(
            f"{location}.common.geolocation_not_cn",
            "must be a list (common geographic list cannot be empty)",
        )
        return
    required = {"apple", "google", "telegram"}
    missing = sorted(required - policy.common_geolocation_not_cn)
    if missing:
        reporter.error(
            f"{location}.common.geolocation_not_cn",
            f"missing README-promised common lists: {missing}",
        )


def validate_upstream_pins(data: dict, reporter: Reporter) -> None:
    location = "upstream_pins"
    if data.get("schema_version") != 1:
        reporter.error(f"{location}.schema_version", "must equal 1")
    pins = data.get("pins")
    if not isinstance(pins, dict):
        reporter.error(f"{location}.pins", "must be an object")
        return
    for key in sorted(pins):
        pin = pins[key]
        pin_location = f"{location}.pins.{key}"
        if not isinstance(pin, dict):
            reporter.error(pin_location, "must be an object")
            continue
        if set(pin) != {"commit", "note"}:
            reporter.error(pin_location, "must contain exactly commit and note")
            continue
        commit = pin["commit"]
        if not isinstance(commit, str) or not COMMIT_RE.fullmatch(commit):
            reporter.error(f"{pin_location}.commit", "must be a lowercase 40-character Git commit")
        if not isinstance(pin["note"], str) or not pin["note"]:
            reporter.error(f"{pin_location}.note", "must be a non-empty string")


def validate_tools_lock(data: dict, reporter: Reporter) -> None:
    if data.get("schema_version") != 2:
        reporter.error("tools_lock.schema_version", "must equal 2")

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
            if set(asset_entry) != {"asset", "sha256", "binary_sha256", "attestation"}:
                reporter.error(
                    asset_location,
                    "must contain exactly asset, sha256, binary_sha256, and attestation",
                )
            if asset_entry.get("attestation") not in ("verified", "unavailable"):
                reporter.error(
                    f"{asset_location}.attestation",
                    "must equal verified or unavailable",
                )
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
        "--domain-platform-capabilities",
        default=str(ROOT / "config" / "domain-platform-capabilities.json"),
    )
    parser.add_argument(
        "--domain-publish-policy",
        default=str(ROOT / "config" / "domain-publish-policy.json"),
    )
    parser.add_argument("--tools-lock", default=str(ROOT / "config" / "tools-lock.json"))
    parser.add_argument("--upstream-pins", default=str(ROOT / "config" / "upstream-pins.json"))
    args = parser.parse_args()

    reporter = Reporter()
    validate_upstreams(load_json_object(Path(args.upstreams), reporter), reporter)
    # load_platform_capabilities is the strict shared loader and already
    # covers everything a plain JSON re-read could report.
    try:
        load_platform_capabilities(Path(args.domain_platform_capabilities))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        reporter.error("domain_platform_capabilities", str(exc))
    validate_domain_publish_policy(
        load_json_object(Path(args.domain_publish_policy), reporter),
        reporter,
    )
    validate_tools_lock(load_json_object(Path(args.tools_lock), reporter), reporter)
    validate_upstream_pins(load_json_object(Path(args.upstream_pins), reporter), reporter)

    if not reporter.ok:
        reporter.emit()
        return 1

    print("config lint passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
