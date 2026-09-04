#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def file_info(path: Path) -> dict:

    info = {"path": str(path)}
    if path.is_file():
        content = path.read_bytes()
        info["bytes"] = len(content)
        info["sha256"] = hashlib.sha256(content).hexdigest()
        entries = [
            line
            for line in content.decode("utf-8", errors="ignore").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        info["entries"] = len(entries)
    elif path.is_dir():
        files = sorted(candidate for candidate in path.rglob("*") if candidate.is_file())
        digest = hashlib.sha256()
        total_bytes = 0
        for candidate in files:
            relative = candidate.relative_to(path).as_posix().encode()
            content = candidate.read_bytes()
            digest.update(relative + b"\0" + content + b"\0")
            total_bytes += len(content)
        info["bytes"] = total_bytes
        info["entries"] = len(files)
        info["sha256"] = digest.hexdigest()
    return info


def cmd_record(args: argparse.Namespace) -> int:
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    source = config.get(args.category, {}).get(args.name, {})
    payload = {
        "category": args.category,
        "name": args.name,
        "status": args.status,
        "kind": source.get("kind", ""),
        "trust": source.get("trust", ""),
        "url": args.url,
        "fallback_used": args.fallback_used == "1",
    }
    if args.detail:
        payload["detail"] = args.detail
    for key, file_name in (("raw", args.raw), ("normalized", args.normalized)):
        if not file_name:
            continue
        payload[key] = file_info(Path(file_name))

    summary_file = Path(args.summary)
    summary_file.parent.mkdir(parents=True, exist_ok=True)
    with summary_file.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
    return 0


def cmd_finalize(args: argparse.Namespace) -> int:
    jsonl_file = Path(args.jsonl)
    items: list[dict] = []
    if jsonl_file.exists():
        items = [
            json.loads(line)
            for line in jsonl_file.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    Path(args.json).write_text(
        json.dumps(items, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    record_parser = subparsers.add_parser("record", help="append one summary line")
    record_parser.add_argument("config")
    record_parser.add_argument("summary")
    record_parser.add_argument("category")
    record_parser.add_argument("name")
    record_parser.add_argument("status")
    record_parser.add_argument("url")
    record_parser.add_argument("raw", nargs="?", default="")
    record_parser.add_argument("normalized", nargs="?", default="")
    record_parser.add_argument("fallback_used", nargs="?", default="0")
    record_parser.add_argument("detail", nargs="?", default="")

    finalize_parser = subparsers.add_parser("finalize", help="convert JSONL to JSON")
    finalize_parser.add_argument("jsonl")
    finalize_parser.add_argument("json")

    args = parser.parse_args()
    if args.command == "record":
        return cmd_record(args)
    return cmd_finalize(args)


if __name__ == "__main__":
    raise SystemExit(main())
