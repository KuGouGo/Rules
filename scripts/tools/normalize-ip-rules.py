#!/usr/bin/env python3

import argparse
import html
import ipaddress
import json
import os
import re
import sys
import tempfile
from pathlib import Path

from ip_rules import parse_classical_ip_file
from platform_capabilities import load_platform_capabilities


PLATFORM_CAPABILITIES = load_platform_capabilities().platforms


# IPv4: strict dotted-quad/prefix. IPv6: must contain at least one colon to
# avoid false-positive matches on non-CIDR hex strings; validated by
# ipaddress.ip_network() afterwards.
CIDR_RE = re.compile(r"(?:\d{1,3}\.){3}\d{1,3}/\d{1,2}|[0-9a-fA-F]*:[0-9a-fA-F:]+/[0-9]{1,3}")
DEFAULT_SINGBOX_RULE_SET_VERSION = 4
SINGBOX_RULE_SET_VERSION = int(os.environ.get("SINGBOX_RULE_SET_VERSION", DEFAULT_SINGBOX_RULE_SET_VERSION))


def atomic_write_text(output_file: Path, output_text: str) -> None:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=output_file.parent,
            prefix=f".{output_file.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temp_path = Path(handle.name)
            handle.write(output_text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, output_file)
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


def normalize_networks(values: list[str]) -> list[ipaddress._BaseNetwork]:
    networks: list[ipaddress._BaseNetwork] = []

    for value in values:
        cidr = value.strip()
        if not cidr:
            continue
        try:
            # strict=False silently masks host bits (e.g. 192.168.1.1/24 → 192.168.1.0/24).
            networks.append(ipaddress.ip_network(cidr, strict=False))
        except ValueError:
            continue

    return networks


def deduplicated_cidrs(values: list[str]) -> list[str]:
    seen: set[str] = set()
    normalized: list[str] = []

    for network in normalize_networks(values):
        text = str(network)
        if text in seen:
            continue
        seen.add(text)
        normalized.append(text)

    return normalized


def write_deduplicated_cidrs(values: list[str], output_file: Path) -> None:
    normalized = deduplicated_cidrs(values)
    output_text = "\n".join(normalized)
    if output_text:
        output_text += "\n"
    atomic_write_text(output_file, output_text)


def collapsed_cidrs(values: list[str]) -> list[str]:
    networks = normalize_networks(values)
    ipv4 = [network for network in networks if network.version == 4]
    ipv6 = [network for network in networks if network.version == 6]
    collapsed = list(ipaddress.collapse_addresses(ipv4))
    collapsed.extend(ipaddress.collapse_addresses(ipv6))
    return [str(network) for network in collapsed]


def merge_plain_cidr_files(input_files: list[Path], output_file: Path) -> None:
    values: list[str] = []
    for input_file in input_files:
        values.extend(input_file.read_text(encoding="utf-8").splitlines())

    output_text = "\n".join(collapsed_cidrs(values))
    if output_text:
        output_text += "\n"
    atomic_write_text(output_file, output_text)


def merge_plain_cidr_files_dedup(input_files: list[Path], output_file: Path) -> None:
    values: list[str] = []
    for input_file in input_files:
        values.extend(input_file.read_text(encoding="utf-8").splitlines())
    write_deduplicated_cidrs(values, output_file)


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


def classify_plain_cidr(value: str) -> str:
    return "IP-CIDR6" if ipaddress.ip_network(value, strict=False).version == 6 else "IP-CIDR"


def render_ip_classical_from_plain(
    platform: str,
    input_file: Path,
    output_file: Path,
    policy_tag: str = "",
    append_no_resolve: bool = True,
) -> None:
    capability = PLATFORM_CAPABILITIES[platform].ip
    if capability.format != "classical" or capability.compiler != "none":
        raise ValueError(f"unsupported {platform} IP renderer implementation")
    lines: list[str] = []
    for cidr in deduplicated_cidrs(input_file.read_text(encoding="utf-8").splitlines()):
        kind = classify_plain_cidr(cidr)
        target = capability.mapping_for(kind)
        fields = [target, cidr]
        if platform == "surge" and append_no_resolve:
            fields.append("no-resolve")
        elif platform == "quanx":
            if not policy_tag:
                raise ValueError("quanx IP rendering requires a non-empty policy tag")
            fields.append(policy_tag)
        elif platform != "surge":
            raise ValueError(f"unsupported classical IP renderer implementation for {platform}")
        lines.append(",".join(fields))
    atomic_write_text(output_file, "\n".join(lines) + ("\n" if lines else ""))


def render_ip_egern_from_plain(input_file: Path, output_file: Path) -> None:
    capability = PLATFORM_CAPABILITIES["egern"].ip
    if capability.format != "yaml" or capability.compiler != "none":
        raise ValueError("unsupported egern IP renderer implementation")
    sections: dict[str, list[str]] = {}
    for cidr in deduplicated_cidrs(input_file.read_text(encoding="utf-8").splitlines()):
        target = capability.mapping_for(classify_plain_cidr(cidr))
        sections.setdefault(target, []).append(cidr)
    chunks = [
        f"{target}:\n" + "\n".join(f"  - '{value}'" for value in values)
        for target, values in sections.items()
    ]
    text = "no_resolve: true\n\n" + "\n\n".join(chunks) + "\n" if chunks else ""
    atomic_write_text(output_file, text)


def build_singbox_json_from_plain(input_file: Path, output_file: Path) -> None:
    capability = PLATFORM_CAPABILITIES["sing-box"].ip
    if capability.format != "binary" or capability.compiler != "sing-box":
        raise ValueError("unsupported sing-box IP renderer implementation")
    mapped_targets = {capability.mapping_for(kind) for kind in ("IP-CIDR", "IP-CIDR6")}
    if mapped_targets != {"ip_cidr"}:
        raise ValueError(f"unsupported sing-box IP rule mappings: {sorted(mapped_targets)}")
    cidrs = deduplicated_cidrs(input_file.read_text(encoding="utf-8").splitlines())
    data = {"version": SINGBOX_RULE_SET_VERSION, "rules": [{"ip_cidr": cidrs}]}
    atomic_write_text(output_file, json.dumps(data, separators=(",", ":")))


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

    staged_outputs: list[tuple[Path, Path]] = []
    try:
        for index, task in enumerate(tasks, start=1):
            if not isinstance(task, dict):
                raise ValueError(f"batch task #{index} must be an object")

            try:
                source_type = str(task["source_type"])
                input_file = Path(task["input_file"])
                output_file = Path(task["output_file"])
            except KeyError as exc:
                raise ValueError(f"batch task #{index} missing field: {exc.args[0]}") from exc

            output_file.parent.mkdir(parents=True, exist_ok=True)
            descriptor, staged_name = tempfile.mkstemp(
                dir=output_file.parent,
                prefix=f".{output_file.name}.batch.",
                suffix=".tmp",
            )
            os.close(descriptor)
            staged_output = Path(staged_name)
            staged_outputs.append((staged_output, output_file))
            run_single_task(source_type, input_file, staged_output)

        for staged_output, output_file in staged_outputs:
            os.replace(staged_output, output_file)
    finally:
        for staged_output, _ in staged_outputs:
            staged_output.unlink(missing_ok=True)


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

    merge_parser = subparsers.add_parser("merge")
    merge_parser.add_argument("output_file")
    merge_parser.add_argument("input_files", nargs="+")

    merge_dedupe_parser = subparsers.add_parser("merge-dedupe")
    merge_dedupe_parser.add_argument("output_file")
    merge_dedupe_parser.add_argument("input_files", nargs="+")

    custom_parser = subparsers.add_parser("custom-source")
    custom_parser.add_argument("input_file")
    custom_parser.add_argument("output_file")

    classical_parser = subparsers.add_parser("render-classical")
    classical_parser.add_argument("platform", choices=("surge", "quanx"))
    classical_parser.add_argument("input_file")
    classical_parser.add_argument("output_file")
    classical_parser.add_argument("--policy-tag", default="")
    classical_parser.add_argument("--omit-no-resolve", action="store_true")

    egern_parser = subparsers.add_parser("render-egern")
    egern_parser.add_argument("input_file")
    egern_parser.add_argument("output_file")

    singbox_parser = subparsers.add_parser("singbox-json")
    singbox_parser.add_argument("input_file")
    singbox_parser.add_argument("output_file")

    args = parser.parse_args()

    try:
        if args.command == "single":
            run_single_task(args.source_type, Path(args.input_file), Path(args.output_file))
        elif args.command == "batch":
            run_batch_tasks(Path(args.manifest_file))
        elif args.command == "merge":
            merge_plain_cidr_files([Path(path) for path in args.input_files], Path(args.output_file))
        elif args.command == "merge-dedupe":
            merge_plain_cidr_files_dedup([Path(path) for path in args.input_files], Path(args.output_file))
        elif args.command == "custom-source":
            input_file = Path(args.input_file)
            rules, errors = parse_classical_ip_file(input_file, require_canonical=True)
            if errors:
                raise ValueError("\n".join(errors))
            output_text = "\n".join(rule.value for rule in rules)
            atomic_write_text(Path(args.output_file), output_text + ("\n" if output_text else ""))
        elif args.command == "render-classical":
            render_ip_classical_from_plain(
                args.platform,
                Path(args.input_file),
                Path(args.output_file),
                policy_tag=args.policy_tag,
                append_no_resolve=not args.omit_no_resolve,
            )
        elif args.command == "render-egern":
            render_ip_egern_from_plain(Path(args.input_file), Path(args.output_file))
        else:
            build_singbox_json_from_plain(Path(args.input_file), Path(args.output_file))
        return 0
    except Exception as exc:  # pragma: no cover - surfaced to shell
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
