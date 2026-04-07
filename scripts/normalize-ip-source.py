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

    output_file.write_text("\n".join(normalized) + "\n", encoding="utf-8")


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

    The response is a JSON object whose top-level values are either scalars or
    lists of CIDR strings.  Collect every CIDR from every list field.
    """
    data = json.loads(input_file.read_text(encoding="utf-8"))
    values = []
    for field_value in data.values():
        if isinstance(field_value, list):
            values.extend(str(item) for item in field_value)
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


def extract_html_cidrs(input_file: Path, output_file: Path) -> None:
    values = CIDR_RE.findall(html.unescape(input_file.read_text(encoding="utf-8")))
    write_deduplicated_cidrs(values, output_file)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "source_type",
        choices=("text", "google-json", "aws-cloudfront-json", "aws-json", "fastly-json", "github-json", "html"),
    )
    parser.add_argument("input_file")
    parser.add_argument("output_file")
    args = parser.parse_args()

    try:
        source_to_handler = {
            "text": extract_text_cidrs,
            "google-json": extract_google_json_cidrs,
            "aws-cloudfront-json": extract_aws_cloudfront_json_cidrs,
            "aws-json": extract_aws_all_json_cidrs,
            "fastly-json": extract_fastly_json_cidrs,
            "github-json": extract_github_json_cidrs,
            "html": extract_html_cidrs,
        }
        source_to_handler[args.source_type](Path(args.input_file), Path(args.output_file))
        return 0
    except Exception as exc:  # pragma: no cover - surfaced to shell
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
