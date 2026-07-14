#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path, PurePosixPath

from platform_capabilities import load_platform_capabilities

ALLOWED_ORIGINS = {"generated-custom", "generated-upstream", "restored-published-branch"}


def origins_path(artifact_root: Path) -> Path:
    return artifact_root / "artifact-origins.json"


def safe_origin_path(value: str) -> bool:
    path = PurePosixPath(value)
    return (
        value == path.as_posix()
        and not path.is_absolute()
        and len(path.parts) == 3
        and path.parts[0] in {"domain", "ip"}
        and all(part not in {"", ".", ".."} for part in path.parts)
        and "\\" not in value
    )


def load_origin_file(path: Path, *, require_nonempty: bool = False) -> dict[str, str]:
    if not path.is_file() and not require_nonempty:
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if (
        not isinstance(data, dict)
        or (require_nonempty and not data)
        or any(
            not isinstance(key, str)
            or not safe_origin_path(key)
            or value not in ALLOWED_ORIGINS
            for key, value in data.items()
        )
    ):
        raise SystemExit(f"invalid artifact origin map: {path}")
    return data


def load_origins(artifact_root: Path) -> dict[str, str]:
    return load_origin_file(origins_path(artifact_root))


def write_origins(artifact_root: Path, origins: dict[str, str]) -> None:
    artifact_root.mkdir(parents=True, exist_ok=True)
    target = origins_path(artifact_root)
    payload = json.dumps(origins, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=artifact_root, prefix=".artifact-origins.", delete=False
        ) as handle:
            temporary = Path(handle.name)
            handle.write(payload)
        os.replace(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def publishable_files(artifact_root: Path):
    for section in ("domain", "ip"):
        base = artifact_root / section
        if not base.is_dir():
            continue
        for path in sorted(base.glob("*/*")):
            if path.is_file():
                yield path


def reset_origins(args: argparse.Namespace) -> None:
    artifact_root = args.artifact_root.resolve()
    origins = {
        path.relative_to(artifact_root).as_posix(): args.origin
        for path in publishable_files(artifact_root)
    }
    write_origins(artifact_root, origins)


def list_origins(args: argparse.Namespace) -> None:
    for path, origin in sorted(load_origins(args.artifact_root.resolve()).items()):
        if args.origin is None or origin == args.origin:
            print(path)


def mark_custom(args: argparse.Namespace) -> None:
    artifact_root = args.artifact_root.resolve()
    origins = load_origins(artifact_root)
    capabilities = load_platform_capabilities()
    source_roots = {
        "domain": args.domain_sources.resolve(),
        "ip": args.ip_sources.resolve(),
    }

    for section, source_root in source_roots.items():
        if not source_root.is_dir():
            continue
        for source in sorted(source_root.glob("*.list")):
            for platform, _details, capability_section, capability in capabilities.iter_capabilities(section):
                if capability_section != section or (args.text_only and capability.format == "binary"):
                    continue
                relative = f"{section}/{platform}/{source.stem}.{capability.extension}"
                origins.pop(relative, None)
                if (artifact_root / relative).is_file():
                    origins[relative] = "generated-custom"

    write_origins(artifact_root, origins)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    subparsers = result.add_subparsers(dest="command", required=True)

    reset = subparsers.add_parser("reset")
    reset.add_argument("artifact_root", type=Path)
    reset.add_argument("origin", choices=sorted(ALLOWED_ORIGINS))
    reset.set_defaults(func=reset_origins)

    listing = subparsers.add_parser("list")
    listing.add_argument("artifact_root", type=Path)
    listing.add_argument("--origin", choices=sorted(ALLOWED_ORIGINS))
    listing.set_defaults(func=list_origins)

    custom = subparsers.add_parser("mark-custom")
    custom.add_argument("artifact_root", type=Path)
    custom.add_argument("domain_sources", type=Path)
    custom.add_argument("ip_sources", type=Path)
    custom.add_argument("--text-only", action="store_true")
    custom.set_defaults(func=mark_custom)
    return result


def main() -> None:
    args = parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
