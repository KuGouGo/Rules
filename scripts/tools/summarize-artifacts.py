#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

TEXT_EXTENSIONS = {".list", ".yaml", ".yml", ".txt", ".json"}
DOMAIN_KINDS = ("DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX")
IP_KINDS = ("IP-CIDR", "IP-CIDR6", "IP6-CIDR")


def non_comment_lines(path: Path) -> list[str]:
    lines: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            lines.append(line)
    return lines


def summarize_domain_text(path: Path) -> dict[str, int]:
    counts = {kind: 0 for kind in DOMAIN_KINDS}
    for line in non_comment_lines(path):
        kind = line.split(",", 1)[0].strip().upper().replace("_", "-")
        if kind in counts:
            counts[kind] += 1
        elif line.startswith("- '") or line.startswith('- "') or line.startswith("- "):
            # Egern YAML entries are section-based; count them as generic entries.
            counts.setdefault("YAML-ENTRY", 0)
            counts["YAML-ENTRY"] += 1
    return {kind: count for kind, count in counts.items() if count}


def summarize_ip_text(path: Path) -> dict[str, int]:
    counts = {kind: 0 for kind in IP_KINDS}
    for line in non_comment_lines(path):
        kind = line.split(",", 1)[0].strip().upper()
        if kind in counts:
            counts[kind] += 1
        elif line.startswith("- '") or line.startswith('- "') or line.startswith("- "):
            counts.setdefault("YAML-ENTRY", 0)
            counts["YAML-ENTRY"] += 1
    return {kind: count for kind, count in counts.items() if count}


def summarize_dir(root: Path, rule_type: str, platform: str) -> dict:
    directory = root / rule_type / platform
    files = sorted(path for path in directory.iterdir() if path.is_file()) if directory.exists() else []
    by_kind: dict[str, int] = {}
    text_files = 0

    for path in files:
        if path.suffix not in TEXT_EXTENSIONS:
            continue
        text_files += 1
        counts = summarize_domain_text(path) if rule_type == "domain" else summarize_ip_text(path)
        for kind, count in counts.items():
            by_kind[kind] = by_kind.get(kind, 0) + count

    return {
        "files": len(files),
        "text_files": text_files,
        "rules": sum(by_kind.values()),
        "by_kind": dict(sorted(by_kind.items())),
    }


def build_summary(root: Path) -> dict:
    platforms = ["surge", "quanx", "egern", "sing-box", "mihomo"]
    return {
        rule_type: {platform: summarize_dir(root, rule_type, platform) for platform in platforms}
        for rule_type in ("domain", "ip")
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact_root", nargs="?", default=".output")
    parser.add_argument("--output", default=".output/build-summary.json")
    args = parser.parse_args()

    root = Path(args.artifact_root)
    summary = build_summary(root)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
