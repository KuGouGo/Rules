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


def canonical_cidrs(values: list[str]) -> list[str]:
    return collapsed_cidrs(values)


def write_canonical_cidrs(values: list[str], output_file: Path) -> None:
    output_text = "\n".join(canonical_cidrs(values))
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
    write_canonical_cidrs(lines, output_file)


def parse_asn_group_specs(group_specs: list[str]) -> dict[str, set[str]]:
    groups: dict[str, set[str]] = {}
    for spec in group_specs:
        name, separator, asns_text = spec.partition("=")
        if not separator or not name:
            raise ValueError(f"invalid ASN group spec (expected name=asn,asn,...): {spec!r}")
        asns = {item.strip() for item in asns_text.split(",") if item.strip()}
        if not asns:
            raise ValueError(f"ASN group {name!r} requires at least one ASN")
        if name in groups:
            raise ValueError(f"duplicate ASN group: {name}")
        groups[name] = asns
    if not groups:
        raise ValueError("multi-group ASN extraction requires at least one group spec")
    return groups


def _iptoasn_endpoint(text: str, source: Path, row_no: int) -> ipaddress._BaseAddress:
    try:
        if ":" in text:
            return ipaddress.IPv6Address(text)
        if "." in text:
            return ipaddress.IPv4Address(text)
        return ipaddress.IPv4Address(int(text))
    except ValueError as exc:
        raise ValueError(f"{source}:{row_no} invalid iptoasn range endpoint: {text}") from exc


def extract_iptoasn_tsv_groups(
    input_file: Path,
    output_template: str,
    group_specs: list[str],
) -> None:
    import gzip

    groups = parse_asn_group_specs(group_specs)
    asn_to_group = {asn: name for name, asns in groups.items() for asn in asns}
    values_by_group: dict[str, list[str]] = {name: [] for name in groups}

    opener = gzip.open if input_file.suffix == ".gz" else open
    with opener(input_file, "rt", encoding="utf-8") as handle:
        for row_no, line in enumerate(handle, start=1):
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                raise ValueError(f"{input_file}:{row_no} malformed iptoasn row: {line.strip()!r}")
            group = asn_to_group.get(parts[2].strip())
            if group is None:
                continue
            start = _iptoasn_endpoint(parts[0].strip(), input_file, row_no)
            end = _iptoasn_endpoint(parts[1].strip(), input_file, row_no)
            if start.version != end.version:
                raise ValueError(
                    f"{input_file}:{row_no} mixed address family in range: {start} - {end}"
                )
            values_by_group[group].extend(
                str(network) for network in ipaddress.summarize_address_range(start, end)
            )

    for name in sorted(values_by_group):
        normalized = [str(network) for network in normalize_networks(values_by_group[name])]
        output_text = "\n".join(canonical_cidrs(normalized))
        output_file = Path(output_template.replace("{name}", name))
        atomic_write_text(output_file, output_text + ("\n" if output_text else ""))


def classify_plain_cidr(value: str) -> str:
    return "IP-CIDR6" if ipaddress.ip_network(value, strict=False).version == 6 else "IP-CIDR"


def render_ip_classical_from_plain(
    platform: str,
    input_file: Path,
    output_file: Path,
    append_no_resolve: bool = True,
) -> None:
    capability = PLATFORM_CAPABILITIES[platform].ip
    if capability.format != "classical" or capability.compiler != "none":
        raise ValueError(f"unsupported {platform} IP renderer implementation")
    lines: list[str] = []
    for cidr in canonical_cidrs(input_file.read_text(encoding="utf-8").splitlines()):
        target = capability.mapping_for(classify_plain_cidr(cidr))
        fields = [target, cidr]
        if platform == "surge" and append_no_resolve:
            fields.append("no-resolve")
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
    }
    handler = source_to_handler.get(source_type)
    if handler is None:
        raise ValueError(f"unsupported normalize source type: {source_type}")
    handler(input_file, output_file)


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

    iptoasn_multi_parser = subparsers.add_parser("iptoasn-tsv-multi")
    iptoasn_multi_parser.add_argument("input_file")
    iptoasn_multi_parser.add_argument(
        "output_template",
        help="output path template containing a {name} placeholder",
    )
    iptoasn_multi_parser.add_argument(
        "groups",
        nargs="+",
        help="group specs: name=asn,asn,...",
    )

    custom_parser = subparsers.add_parser("custom-source")
    custom_parser.add_argument("input_file")
    custom_parser.add_argument("output_file")

    classical_parser = subparsers.add_parser("render-classical")
    classical_parser.add_argument("platform", choices=("surge",))
    classical_parser.add_argument("input_file")
    classical_parser.add_argument("output_file")
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
        elif args.command == "iptoasn-tsv-multi":
            extract_iptoasn_tsv_groups(
                Path(args.input_file), args.output_template, list(args.groups)
            )
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
