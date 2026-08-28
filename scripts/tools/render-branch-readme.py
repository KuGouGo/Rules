#!/usr/bin/env python3
"""Render a publish-branch README with a generated artifact stats table.

The table lists every artifact actually present for the platform with its
entry count, so subscribers can see what a branch contains and when data
changed (counts move only when the underlying rule data moves, keeping the
publish cohort's "unchanged tree" optimization meaningful).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

MARKER = "<!-- artifact-table -->"


def non_comment_line_count(path: Path) -> int:
    return sum(
        1
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    )


def yaml_entry_count(path: Path) -> int:
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip().startswith("- "))


def text_entries(path: Path) -> int:
    return non_comment_line_count(path)


def collect_rows(platform: str, artifact_root: Path) -> list[tuple[str, int]]:
    rows: list[tuple[str, int]] = []

    if platform in {"surge", "quanx"}:
        for section in ("domain", "ip"):
            directory = artifact_root / section / platform
            for path in sorted(directory.glob("*.list")):
                rows.append((f"{section}/{path.name}", text_entries(path)))
    elif platform == "egern":
        for section in ("domain", "ip"):
            directory = artifact_root / section / platform
            for path in sorted(directory.glob("*.yaml")):
                rows.append((f"{section}/{path.name}", yaml_entry_count(path)))
    elif platform in {"sing-box", "mihomo"}:
        # Binary artifacts carry no countable plaintext; the canonical tree is
        # the exact compiled input, keyed by the same list name. Only list
        # names whose artifact actually exists on the branch are shown:
        # compilers skip lists they cannot represent (e.g. mihomo skips
        # DOMAIN-KEYWORD-only lists), and the table must not advertise files
        # a subscriber cannot download.
        for section in ("domain", "ip"):
            extension = "srs" if platform == "sing-box" else "mrs"
            artifact_dir = artifact_root / section / platform
            canonical_dir = artifact_root / ".canonical" / section
            if not canonical_dir.is_dir():
                continue
            for path in sorted(canonical_dir.glob("*.list")):
                if not (artifact_dir / f"{path.stem}.{extension}").exists():
                    continue
                rows.append((f"{section}/{path.stem}", text_entries(path)))
    else:
        raise ValueError(f"unsupported platform: {platform}")
    return rows


def render_table(rows: list[tuple[str, int]]) -> str:
    lines = ["## 产物清单", "", "| 列表 | 条目数 |", "| --- | ---: |"]
    lines.extend(f"| {name} | {count} |" for name, count in rows)
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--artifact-root", required=True, type=Path)
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    rows = collect_rows(args.platform, args.artifact_root)
    if not rows:
        print(f"no artifacts found for platform {args.platform} under {args.artifact_root}", file=sys.stderr)
        return 1

    template = args.template.read_text(encoding="utf-8")
    table = render_table(rows)
    if MARKER in template:
        rendered = template.replace(MARKER, table.rstrip("\n"))
    else:
        rendered = template.rstrip("\n") + "\n\n" + table
    args.output.write_text(rendered, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
