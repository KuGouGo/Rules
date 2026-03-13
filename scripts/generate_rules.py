#!/usr/bin/env python3
"""Generate sing-box / Clash / Surge rules from .list source files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

SUPPORTED_TYPES = {"DOMAIN-SUFFIX", "DOMAIN", "DOMAIN-KEYWORD", "IP-CIDR"}


def parse_rule_line(line: str) -> tuple[str, str]:
    """Parse one rule line and return (rule_type, value)."""
    parts = [p.strip() for p in line.split(",") if p.strip()]
    if len(parts) < 2:
        raise ValueError(f"invalid rule line: {line}")

    rule_type, value = parts[0], parts[1]
    if rule_type not in SUPPORTED_TYPES:
        raise ValueError(f"unsupported rule type: {rule_type}")

    return rule_type, value


def load_list_rules(path: Path) -> dict[str, list[str]]:
    buckets = {
        "DOMAIN-SUFFIX": [],
        "DOMAIN": [],
        "DOMAIN-KEYWORD": [],
        "IP-CIDR": [],
    }

    with path.open("r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            rule_type, value = parse_rule_line(line)
            buckets[rule_type].append(value)

    return buckets


def build_singbox(name: str, outbound: str, rules: dict[str, list[str]]) -> dict[str, Any]:
    return {
        "version": 1,
        "name": name,
        "rules": [
            {"domain_suffix": rules["DOMAIN-SUFFIX"], "outbound": outbound},
            {"domain": rules["DOMAIN"], "outbound": outbound},
            {"domain_keyword": rules["DOMAIN-KEYWORD"], "outbound": outbound},
            {"ip_cidr": rules["IP-CIDR"], "outbound": outbound},
        ],
    }


def build_clash(outbound: str, rules: dict[str, list[str]]) -> str:
    lines = ["rules:"]
    for rule_type in ("DOMAIN-SUFFIX", "DOMAIN", "DOMAIN-KEYWORD", "IP-CIDR"):
        for value in rules[rule_type]:
            suffix = ",no-resolve" if rule_type == "IP-CIDR" else ""
            lines.append(f"  - {rule_type},{value},{outbound}{suffix}")
    return "\n".join(lines) + "\n"


def build_surge(outbound: str, rules: dict[str, list[str]]) -> str:
    lines: list[str] = []
    for rule_type in ("DOMAIN-SUFFIX", "DOMAIN", "DOMAIN-KEYWORD", "IP-CIDR"):
        for value in rules[rule_type]:
            suffix = ",no-resolve" if rule_type == "IP-CIDR" else ""
            lines.append(f"{rule_type},{value},{outbound}{suffix}")
    return "\n".join(lines) + "\n"


def infer_outbound_from_name(stem: str) -> str:
    # 约定：名称以 -cn / _cn / _direct 结尾走 DIRECT；emby 走 Emby；其余走 PROXY
    if stem.endswith(("-cn", "_cn", "_direct")):
        return "DIRECT"
    if stem == "emby":
        return "Emby"
    return "PROXY"


def write_profile_outputs(source_file: Path, out_dir: Path) -> None:
    profile = source_file.stem
    outbound = infer_outbound_from_name(profile)
    rules = load_list_rules(source_file)

    with (out_dir / f"{profile}.sing-box.json").open("w", encoding="utf-8") as f:
        json.dump(build_singbox(profile, outbound, rules), f, ensure_ascii=False, indent=2)
        f.write("\n")

    with (out_dir / f"{profile}.clash.yaml").open("w", encoding="utf-8") as f:
        f.write(build_clash(outbound, rules))

    with (out_dir / f"{profile}.surge.list").open("w", encoding="utf-8") as f:
        f.write(build_surge(outbound, rules))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate sing-box / Clash / Surge rules from .list source files"
    )
    parser.add_argument(
        "--input-dir",
        default="data",
        type=Path,
        help="directory that contains .list source files",
    )
    parser.add_argument(
        "--output-dir",
        default="output",
        type=Path,
        help="output directory",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    source_files = sorted(args.input_dir.glob("*.list"))
    if not source_files:
        raise FileNotFoundError(f"no .list source files found in: {args.input_dir}")

    for source_file in source_files:
        write_profile_outputs(source_file, args.output_dir)

    print(f"Generated profiles: {', '.join(f.stem for f in source_files)}")
    print(f"Generated files in: {args.output_dir}")


if __name__ == "__main__":
    main()
