#!/usr/bin/env python3

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import sys
import tempfile
from pathlib import Path

from common_utils import atomic_write_text
from ip_rules import parse_classical_ip_file
from platform_capabilities import load_platform_capabilities


PLATFORM_CAPABILITIES = load_platform_capabilities().platforms


DEFAULT_SINGBOX_RULE_SET_VERSION = 4


def _resolve_singbox_rule_set_version() -> int:
    raw = os.environ.get("SINGBOX_RULE_SET_VERSION")
    if raw is None:
        return DEFAULT_SINGBOX_RULE_SET_VERSION
    try:
        return int(raw)
    except ValueError:
        raise SystemExit(f"invalid SINGBOX_RULE_SET_VERSION environment value: {raw!r}")


SINGBOX_RULE_SET_VERSION = _resolve_singbox_rule_set_version()


def normalize_networks(values: list[str]) -> list[ipaddress._BaseNetwork]:


    networks: list[ipaddress._BaseNetwork] = []
    invalid: list[str] = []

    for value in values:
        cidr = value.strip()
        if not cidr:
            continue
        try:


            networks.append(ipaddress.ip_network(cidr, strict=False))
        except ValueError:
            invalid.append(cidr)
    if invalid:
        preview = ", ".join(repr(value) for value in invalid[:5])
        suffix = f" (and {len(invalid) - 5} more)" if len(invalid) > 5 else ""
        raise ValueError(f"invalid CIDR source entries: {preview}{suffix}")
    return networks


def validated_network(value: str, source: Path, label: str) -> ipaddress._BaseNetwork:
    try:
        return ipaddress.ip_network(value, strict=False)
    except ValueError as exc:
        raise ValueError(f"{source} {label} invalid CIDR value: {value}") from exc


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


def canonical_cidrs(values: list[str]) -> list[str]:

    return collapsed_cidrs(values)


def write_deduplicated_cidrs(values: list[str], output_file: Path) -> None:
    normalized = deduplicated_cidrs(values)
    output_text = "\n".join(normalized)
    if output_text:
        output_text += "\n"
    atomic_write_text(output_file, output_text)


def collapsed_cidrs(values: list[str]) -> list[str]:
    networks = normalize_networks(values)
    ipv4 = [network for network in networks if isinstance(network, ipaddress.IPv4Network)]
    ipv6 = [network for network in networks if isinstance(network, ipaddress.IPv6Network)]
    collapsed: list[ipaddress._BaseNetwork] = list(ipaddress.collapse_addresses(ipv4))
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


def extract_text_cidrs(input_file: Path, output_file: Path) -> None:
    lines = []
    for line_no, raw_line in enumerate(input_file.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        try:
            ipaddress.ip_network(line, strict=False)
        except ValueError as exc:
            raise ValueError(f"{input_file}:{line_no} invalid CIDR entry: {line}") from exc
        lines.append(line)
    write_deduplicated_cidrs(lines, output_file)


def require_object_list(data: object, field: str, source: Path) -> list[dict]:
    if not isinstance(data, dict) or field not in data or not isinstance(data[field], list):
        raise ValueError(f"{source} missing required JSON array: {field}")
    if not all(isinstance(item, dict) for item in data[field]):
        raise ValueError(f"{source} JSON array {field} must contain objects")
    return data[field]


def extract_google_json_cidrs(input_file: Path, output_file: Path) -> None:
    data = json.loads(input_file.read_text(encoding="utf-8"))
    values = []
    for index, item in enumerate(require_object_list(data, "prefixes", input_file), start=1):
        present = [key for key in ("ipv4Prefix", "ipv6Prefix") if key in item]
        if len(present) != 1 or not isinstance(item[present[0]], str):
            raise ValueError(f"{input_file} prefixes[{index}] must contain one string IP prefix")
        values.append(
            str(validated_network(item[present[0]], input_file, f"prefixes[{index}]"))
        )
    write_deduplicated_cidrs(values, output_file)


def extract_fastly_json_cidrs(input_file: Path, output_file: Path) -> None:
    data = json.loads(input_file.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{input_file} Fastly response must be an object")
    values = []
    for field in ("addresses", "ipv6_addresses"):
        entries = data.get(field)
        if not isinstance(entries, list) or not all(isinstance(value, str) for value in entries):
            raise ValueError(f"{input_file} missing required string array: {field}")
        for index, value in enumerate(entries, start=1):
            values.append(str(validated_network(value, input_file, f"{field}[{index}]")))
    write_deduplicated_cidrs(values, output_file)


def extract_cloudfront_json_cidrs(input_file: Path, output_file: Path) -> None:

    data = json.loads(input_file.read_text(encoding="utf-8"))
    values = []
    for field, prefix_key in (("prefixes", "ip_prefix"), ("ipv6_prefixes", "ipv6_prefix")):
        for index, item in enumerate(require_object_list(data, field, input_file), start=1):
            if item.get("service") != "CLOUDFRONT":
                continue
            value = item.get(prefix_key)
            if not isinstance(value, str):
                raise ValueError(f"{input_file} {field}[{index}] missing string {prefix_key}")
            values.append(str(validated_network(value, input_file, f"{field}[{index}]")))
    write_deduplicated_cidrs(values, output_file)


def extract_ripe_stat_json_cidrs(input_file: Path, output_file: Path) -> None:


    data = json.loads(input_file.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("data"), dict):
        raise ValueError(f"{input_file} missing RIPE Stat data object")
    prefixes = require_object_list(data["data"], "prefixes", input_file)
    values = []
    for index, item in enumerate(prefixes, start=1):
        value = item.get("prefix")
        if not isinstance(value, str):
            raise ValueError(f"{input_file} prefixes[{index}] missing string prefix")
        values.append(str(validated_network(value, input_file, f"prefixes[{index}]")))
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
    for cidr in canonical_cidrs(input_file.read_text(encoding="utf-8").splitlines()):
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
    for cidr in canonical_cidrs(input_file.read_text(encoding="utf-8").splitlines()):
        target = capability.mapping_for(classify_plain_cidr(cidr))
        sections.setdefault(target, []).append(cidr)
    chunks = [
        f"{target}:\n" + "\n".join(f"  - '{value}'" for value in values)
        for target, values in sections.items()
    ]
    text = ("no_resolve: true\n\n" + "\n\n".join(chunks) + "\n") if chunks else ""
    atomic_write_text(output_file, text)


def build_singbox_json_from_plain(input_file: Path, output_file: Path) -> None:
    capability = PLATFORM_CAPABILITIES["sing-box"].ip
    if capability.format != "binary" or capability.compiler != "sing-box":
        raise ValueError("unsupported sing-box IP renderer implementation")
    mapped_targets = {capability.mapping_for(kind) for kind in ("IP-CIDR", "IP-CIDR6")}
    if mapped_targets != {"ip_cidr"}:
        raise ValueError(f"unsupported sing-box IP rule mappings: {sorted(mapped_targets)}")
    cidrs = canonical_cidrs(input_file.read_text(encoding="utf-8").splitlines())
    if not cidrs:
        raise ValueError(f"no CIDR entries in sing-box JSON input: {input_file}")
    data = {"version": SINGBOX_RULE_SET_VERSION, "rules": [{"ip_cidr": cidrs}]}
    atomic_write_text(output_file, json.dumps(data, separators=(",", ":")))


def run_single_task(source_type: str, input_file: Path, output_file: Path) -> None:
    source_to_handler = {
        "text": extract_text_cidrs,
        "google-json": extract_google_json_cidrs,
        "cloudfront-json": extract_cloudfront_json_cidrs,
        "fastly-json": extract_fastly_json_cidrs,
        "ripe-stat-json": extract_ripe_stat_json_cidrs,
    }
    source_to_handler[source_type](input_file, output_file)


    values = output_file.read_text(encoding="utf-8").splitlines()
    normalize_networks(values)
    output_text = "\n".join(canonical_cidrs(values))
    atomic_write_text(output_file, output_text + ("\n" if output_text else ""))


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


def write_normalize_manifest(manifest_file: Path, triplets: list[str]) -> None:
    if len(triplets) % 3 != 0:
        raise ValueError(
            "normalize manifest generator expects triplets: source_type input_file output_file"
        )
    tasks = [
        {
            "source_type": triplets[index],
            "input_file": triplets[index + 1],
            "output_file": triplets[index + 2],
        }
        for index in range(0, len(triplets), 3)
    ]
    manifest_file.write_text(
        json.dumps(tasks, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    source_types = {
        "text",
        "google-json",
        "cloudfront-json",
        "fastly-json",
        "ripe-stat-json",
    }

    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    single_parser = subparsers.add_parser("single")
    single_parser.add_argument(
        "source_type",
        choices=tuple(sorted(source_types)),
    )
    single_parser.add_argument("input_file")
    single_parser.add_argument("output_file")

    batch_parser = subparsers.add_parser("batch")
    batch_parser.add_argument("manifest_file")

    manifest_parser = subparsers.add_parser("generate-manifest")
    manifest_parser.add_argument("manifest_file")
    manifest_parser.add_argument("triplets", nargs="+")

    merge_parser = subparsers.add_parser("merge")
    merge_parser.add_argument("output_file")
    merge_parser.add_argument("input_files", nargs="+")

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
        elif args.command == "generate-manifest":
            write_normalize_manifest(Path(args.manifest_file), args.triplets)
        elif args.command == "merge":
            merge_plain_cidr_files([Path(path) for path in args.input_files], Path(args.output_file))
        elif args.command == "custom-source":
            input_file = Path(args.input_file)
            rules, errors = parse_classical_ip_file(input_file, require_canonical=True)
            if errors:
                raise ValueError("\n".join(errors))
            output_text = "\n".join(canonical_cidrs([rule.value for rule in rules]))
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
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
