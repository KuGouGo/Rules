#!/usr/bin/env python3

import argparse
import ipaddress
import json
import sys
from pathlib import Path
from typing import Optional


STATUS_OK = "ok"
STATUS_TRANSPORT = "transport_incident"
STATUS_SEMANTIC = "semantic_regression"


def result(source: str, status: str, reason: str, details: Optional[dict] = None) -> dict:
    payload = {"source": source, "status": status, "reason": reason}
    if details:
        payload["details"] = details
    return payload


def read_baselines(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_cidrs(values: list[str]) -> list[ipaddress._BaseNetwork]:
    seen: set[str] = set()
    normalized: list[ipaddress._BaseNetwork] = []

    for value in values:
        cidr = value.strip()
        if not cidr:
            continue
        network = ipaddress.ip_network(cidr, strict=False)
        text = str(network)
        if text in seen:
            continue
        seen.add(text)
        normalized.append(network)

    return normalized


def github_cidr_sections(data: dict) -> list[list[str]]:
    sections: list[list[str]] = []

    for field_value in data.values():
        if not isinstance(field_value, list) or not field_value:
            continue

        section_values = [item.strip() for item in field_value if isinstance(item, str) and item.strip()]
        if not section_values:
            continue

        try:
            normalize_cidrs(section_values)
        except ValueError:
            continue

        sections.append(section_values)

    return sections


def classify_google(raw_file: Path, baseline: dict) -> dict:
    if not raw_file.exists() or raw_file.stat().st_size == 0:
        return result("google-json", STATUS_TRANSPORT, "raw payload missing or empty")

    try:
        data = json.loads(raw_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return result("google-json", STATUS_SEMANTIC, f"payload is not valid json: {exc.msg}")

    prefixes = data.get("prefixes")
    if not isinstance(prefixes, list) or not prefixes:
        return result("google-json", STATUS_SEMANTIC, "payload is missing a non-empty prefixes array")

    values: list[str] = []
    raw_has_ipv4 = False
    raw_has_ipv6 = False
    for item in prefixes:
        if not isinstance(item, dict):
            continue
        ipv4 = item.get("ipv4Prefix")
        ipv6 = item.get("ipv6Prefix")
        if isinstance(ipv4, str):
            raw_has_ipv4 = True
            values.append(ipv4)
        if isinstance(ipv6, str):
            raw_has_ipv6 = True
            values.append(ipv6)

    if not raw_has_ipv4 or not raw_has_ipv6:
        return result("google-json", STATUS_SEMANTIC, "payload no longer exposes both ipv4Prefix and ipv6Prefix entries")

    try:
        normalized = normalize_cidrs(values)
    except ValueError as exc:
        return result("google-json", STATUS_SEMANTIC, f"payload prefixes are not valid cidrs: {exc}")

    ipv4_count = sum(1 for network in normalized if network.version == 4)
    ipv6_count = sum(1 for network in normalized if network.version == 6)
    if ipv4_count == 0 or ipv6_count == 0:
        return result("google-json", STATUS_SEMANTIC, "normalization lost one address family unexpectedly")

    minimum_total = int(baseline["secondary_min_total"])
    if len(normalized) < minimum_total:
        return result(
            "google-json",
            STATUS_SEMANTIC,
            f"normalized cidr count {len(normalized)} is below secondary floor {minimum_total}",
            {"ipv4_count": ipv4_count, "ipv6_count": ipv6_count},
        )

    return result(
        "google-json",
        STATUS_OK,
        "payload keeps prefixes structure and both address families",
        {"ipv4_count": ipv4_count, "ipv6_count": ipv6_count},
    )


def classify_github(raw_file: Path, baseline: dict) -> dict:
    if not raw_file.exists() or raw_file.stat().st_size == 0:
        return result("github-json", STATUS_TRANSPORT, "raw payload missing or empty")

    try:
        data = json.loads(raw_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return result("github-json", STATUS_SEMANTIC, f"payload is not valid json: {exc.msg}")

    if not isinstance(data, dict):
        return result("github-json", STATUS_SEMANTIC, "payload is not a top-level json object")

    sections = github_cidr_sections(data)
    values = [cidr for section in sections for cidr in section]
    nonempty_sections = len(sections)

    minimum_sections = int(baseline["minimum_nonempty_list_sections"])
    if nonempty_sections < minimum_sections:
        return result(
            "github-json",
            STATUS_SEMANTIC,
            f"payload no longer yields cidrs from at least {minimum_sections} list-bearing sections",
            {"nonempty_sections": nonempty_sections},
        )

    normalized = normalize_cidrs(values)

    minimum_total = int(baseline["secondary_min_total"])
    if len(normalized) < minimum_total:
        return result(
            "github-json",
            STATUS_SEMANTIC,
            f"normalized cidr count {len(normalized)} is below secondary floor {minimum_total}",
            {"nonempty_sections": nonempty_sections},
        )

    return result(
        "github-json",
        STATUS_OK,
        "payload still yields cidrs from multiple list-bearing sections",
        {"nonempty_sections": nonempty_sections, "normalized_total": len(normalized)},
    )


def classify_telegram(raw_file: Path, baseline: dict) -> dict:
    if not raw_file.exists() or raw_file.stat().st_size == 0:
        return result("telegram", STATUS_TRANSPORT, "raw payload missing or empty")

    values: list[str] = []
    for raw_line in raw_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        values.append(line)

    if not values:
        return result("telegram", STATUS_TRANSPORT, "payload is empty after stripping blank lines and comments")

    try:
        normalized = normalize_cidrs(values)
    except ValueError as exc:
        return result("telegram", STATUS_SEMANTIC, f"payload is not a pure cidr list: {exc}")

    ipv4_count = sum(1 for network in normalized if network.version == 4)
    if ipv4_count == 0:
        return result("telegram", STATUS_SEMANTIC, "payload no longer contains any ipv4 cidrs")

    minimum_total = int(baseline["secondary_min_total"])
    if len(normalized) < minimum_total:
        return result(
            "telegram",
            STATUS_SEMANTIC,
            f"normalized cidr count {len(normalized)} is below secondary floor {minimum_total}",
            {"ipv4_count": ipv4_count},
        )

    return result(
        "telegram",
        STATUS_OK,
        "payload remains a pure cidr list with at least one ipv4 entry",
        {"ipv4_count": ipv4_count, "normalized_total": len(normalized)},
    )


def classify_source(source: str, raw_file: Path, baselines: dict) -> dict:
    if source not in baselines:
        raise ValueError(f"unsupported first-batch source: {source}")

    baseline = baselines[source]
    if source == "google-json":
        return classify_google(raw_file, baseline)
    if source == "github-json":
        return classify_github(raw_file, baseline)
    if source == "telegram":
        return classify_telegram(raw_file, baseline)

    raise ValueError(f"unsupported first-batch source: {source}")


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    classify_parser = subparsers.add_parser("classify")
    classify_parser.add_argument("source", choices=("google-json", "github-json", "telegram"))
    classify_parser.add_argument("raw_file")
    classify_parser.add_argument("baseline_file")

    args = parser.parse_args()

    try:
        baselines = read_baselines(Path(args.baseline_file))
        payload = classify_source(args.source, Path(args.raw_file), baselines)
        print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
        return 0
    except Exception as exc:  # pragma: no cover - surfaced to shell
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
