#!/usr/bin/env python3

import argparse
import html
import ipaddress
import json
import re
import sys
from pathlib import Path


# IPv4: strict dotted-quad/prefix. IPv6: must contain at least one colon to
# avoid false-positive matches on non-CIDR hex strings; validated by
# ipaddress.ip_network() afterwards.
CIDR_RE = re.compile(r"(?:\d{1,3}\.){3}\d{1,3}/\d{1,2}|[0-9a-fA-F]*:[0-9a-fA-F:]+/[0-9]{1,3}")


def write_deduplicated_cidrs(values: list[str], output_file: Path) -> None:
    seen: set[str] = set()
    normalized: list[str] = []

    for value in values:
        cidr = value.strip()
        if not cidr:
            continue
        try:
            # strict=False silently masks host bits (e.g. 192.168.1.1/24 → 192.168.1.0/24).
            network = ipaddress.ip_network(cidr, strict=False)
        except ValueError:
            continue
        text = str(network)
        if text in seen:
            continue
        seen.add(text)
        normalized.append(text)

    output_text = "\n".join(normalized)
    if output_text:
        output_text += "\n"
    output_file.write_text(output_text, encoding="utf-8")


def extract_text_cidrs(input_file: Path, output_file: Path) -> None:
    lines = []
    for raw_line in input_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if line:
            lines.append(line)
    write_deduplicated_cidrs(lines, output_file)


def extract_google_json_cidrs(input_file: Path, output_file: Path) -> None:
    data = json.loads(input_file.read_text(encoding="utf-8"))
    values = []
    for item in data.get("prefixes", []):
        if "ipv4Prefix" in item:
            values.append(item["ipv4Prefix"])
        if "ipv6Prefix" in item:
            values.append(item["ipv6Prefix"])
    write_deduplicated_cidrs(values, output_file)


def extract_aws_cloudfront_json_cidrs(input_file: Path, output_file: Path) -> None:
    data = json.loads(input_file.read_text(encoding="utf-8"))
    values = []

    for item in data.get("prefixes", []):
        if item.get("service") == "CLOUDFRONT" and "ip_prefix" in item:
            values.append(item["ip_prefix"])

    for item in data.get("ipv6_prefixes", []):
        if item.get("service") == "CLOUDFRONT" and "ipv6_prefix" in item:
            values.append(item["ipv6_prefix"])

    write_deduplicated_cidrs(values, output_file)


def extract_fastly_json_cidrs(input_file: Path, output_file: Path) -> None:
    data = json.loads(input_file.read_text(encoding="utf-8"))
    values = []
    values.extend(data.get("addresses", []))
    values.extend(data.get("ipv6_addresses", []))
    write_deduplicated_cidrs(values, output_file)


def extract_github_json_cidrs(input_file: Path, output_file: Path) -> None:
    """Parse GitHub's official IP meta endpoint (https://api.github.com/meta).

    The response also contains non-CIDR list fields such as SSH public keys.
    Collect only top-level lists whose string values are all valid CIDRs.
    """
    data = json.loads(input_file.read_text(encoding="utf-8"))
    values = []
    for field_value in data.values():
        if not isinstance(field_value, list):
            continue

        section_values = [item.strip() for item in field_value if isinstance(item, str) and item.strip()]
        if not section_values:
            continue

        try:
            for item in section_values:
                ipaddress.ip_network(item, strict=False)
        except ValueError:
            continue

        values.extend(section_values)
    write_deduplicated_cidrs(values, output_file)


def extract_aws_all_json_cidrs(input_file: Path, output_file: Path) -> None:
    """Parse AWS's published IP ranges (https://ip-ranges.amazonaws.com/ip-ranges.json).

    Unlike the CloudFront-filtered variant, this collects *all* AWS service prefixes.
    """
    data = json.loads(input_file.read_text(encoding="utf-8"))
    values = []
    for item in data.get("prefixes", []):
        if "ip_prefix" in item:
            values.append(item["ip_prefix"])
    for item in data.get("ipv6_prefixes", []):
        if "ipv6_prefix" in item:
            values.append(item["ipv6_prefix"])
    write_deduplicated_cidrs(values, output_file)


def extract_ripe_stat_json_cidrs(input_file: Path, output_file: Path) -> None:
    """Parse a RIPE NCC Stat announced-prefixes response.

    Source URL pattern:
      https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS<asn>

    The response contains the set of prefixes currently announced by that ASN
    according to RIPE NCC's RPKI/routing data — authoritative registry data
    suitable for proxy rule sets.
    """
    data = json.loads(input_file.read_text(encoding="utf-8"))
    prefixes = data.get("data", {}).get("prefixes", [])
    write_deduplicated_cidrs([item["prefix"] for item in prefixes], output_file)


def extract_html_cidrs(input_file: Path, output_file: Path) -> None:
    values = CIDR_RE.findall(html.unescape(input_file.read_text(encoding="utf-8")))
    write_deduplicated_cidrs(values, output_file)


def run_single_task(source_type: str, input_file: Path, output_file: Path) -> None:
    source_to_handler = {
        "text": extract_text_cidrs,
        "google-json": extract_google_json_cidrs,
        "aws-cloudfront-json": extract_aws_cloudfront_json_cidrs,
        "aws-json": extract_aws_all_json_cidrs,
        "fastly-json": extract_fastly_json_cidrs,
        "github-json": extract_github_json_cidrs,
        "ripe-stat-json": extract_ripe_stat_json_cidrs,
        "html": extract_html_cidrs,
    }
    source_to_handler[source_type](input_file, output_file)


def run_batch_tasks(manifest_file: Path) -> None:
    tasks = json.loads(manifest_file.read_text(encoding="utf-8"))
    if not isinstance(tasks, list):
        raise ValueError("batch manifest must be a JSON array")

    for index, task in enumerate(tasks, start=1):
        if not isinstance(task, dict):
            raise ValueError(f"batch task #{index} must be an object")

        try:
            source_type = str(task["source_type"])
            input_file = Path(task["input_file"])
            output_file = Path(task["output_file"])
        except KeyError as exc:
            raise ValueError(f"batch task #{index} missing field: {exc.args[0]}") from exc

        run_single_task(source_type, input_file, output_file)


def main() -> int:
    legacy_source_types = {
        "text",
        "google-json",
        "aws-cloudfront-json",
        "aws-json",
        "fastly-json",
        "github-json",
        "ripe-stat-json",
        "html",
    }

    if len(sys.argv) == 4 and sys.argv[1] in legacy_source_types:
        try:
            run_single_task(sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]))
            return 0
        except Exception as exc:  # pragma: no cover - surfaced to shell
            print(str(exc), file=sys.stderr)
            return 1

    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    single_parser = subparsers.add_parser("single")
    single_parser.add_argument(
        "source_type",
        choices=tuple(sorted(legacy_source_types)),
    )
    single_parser.add_argument("input_file")
    single_parser.add_argument("output_file")

    batch_parser = subparsers.add_parser("batch")
    batch_parser.add_argument("manifest_file")

    args = parser.parse_args()

    try:
        if args.command == "single":
            run_single_task(args.source_type, Path(args.input_file), Path(args.output_file))
        else:
            run_batch_tasks(Path(args.manifest_file))
        return 0
    except Exception as exc:  # pragma: no cover - surfaced to shell
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
