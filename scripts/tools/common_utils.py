#!/usr/bin/env python3
"""Shared utilities for lint tools and artifact validation."""
from __future__ import annotations

import sys
from pathlib import Path, PurePosixPath


class Reporter:
    """Collect and emit validation errors with optional location context."""

    def __init__(self) -> None:
        self.errors: list[str] = []

    def error(self, *parts: str) -> None:
        self.errors.append(": ".join(parts))

    def emit(self) -> None:
        for error in self.errors:
            print(error, file=sys.stderr)

    @property
    def ok(self) -> bool:
        return not self.errors


def non_comment_lines(path: Path) -> list[str]:
    """Return a text file's non-blank lines with comments stripped."""
    lines: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            lines.append(line)
    return lines


def safe_publish_path(value: str) -> bool:
    """True when *value* is a relative path like domain/<platform>/<name>.<ext>."""
    path = PurePosixPath(value)
    return (
        value == path.as_posix()
        and not path.is_absolute()
        and len(path.parts) == 3
        and path.parts[0] in {"domain", "ip"}
        and all(part not in {"", ".", ".."} for part in path.parts)
        and "\\" not in value
    )
