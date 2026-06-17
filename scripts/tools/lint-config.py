#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from urllib.parse import urlparse


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
SUPPORTED_IP_PARSERS = {"google-json", "github-json", "telegram"}
SUPPORTED_DOMAIN_RULE_TYPES = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX"}
REQUIRED_DOMAIN_PLATFORMS = {"surge", "quanx", "egern", "sing-box", "mihomo-mrs"}
ALLOWED_TRUST_VALUES = {"community", "official", "registry"}
ALLOWED_KINDS = {
    "domain": {"git", "text", "yaml"},
    "ip": {"html", "json", "json-api", "text"},
}


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
    if parser is not None and parser not in SUPPORTED_IP_PARSERS:
        reporter.error(f"{location}.parser", f"unsupported parser {parser!r}")

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


def validate_domain_platform_capabilities(data: dict, reporter: Reporter) -> None:
    missing = REQUIRED_DOMAIN_PLATFORMS - set(data)
    if missing:
        reporter.error("domain_platform_capabilities", f"missing platforms: {sorted(missing)}")

    for platform, values in sorted(data.items()):
        location = f"domain_platform_capabilities.{platform}"
        if not isinstance(values, list) or not values:
            reporter.error(location, "must be a non-empty list")
            continue

        seen: set[str] = set()
        for index, value in enumerate(values):
            item_location = f"{location}[{index}]"
            if value not in SUPPORTED_DOMAIN_RULE_TYPES:
                reporter.error(item_location, f"unsupported domain rule type {value!r}")
                continue
            if value in seen:
                reporter.error(item_location, f"duplicate rule type {value}")
            seen.add(value)


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
    args = parser.parse_args()

    reporter = Reporter()
    validate_upstreams(load_json_object(Path(args.upstreams), reporter), reporter)
    validate_first_batch_baselines(load_json_object(Path(args.first_batch_baselines), reporter), reporter)
    validate_domain_platform_capabilities(load_json_object(Path(args.domain_platform_capabilities), reporter), reporter)

    if not reporter.ok:
        reporter.emit()
        return 1

    print("config lint passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
