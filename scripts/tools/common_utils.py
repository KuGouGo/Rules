#!/usr/bin/env python3

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path, PurePosixPath


class Reporter:


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

    lines: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            lines.append(line)
    return lines


def safe_publish_path(value: str) -> bool:

    path = PurePosixPath(value)
    return (
        value == path.as_posix()
        and not path.is_absolute()
        and len(path.parts) == 3
        and path.parts[0] in {"domain", "ip"}
        and all(part not in {"", ".", ".."} for part in path.parts)
        and "\\" not in value
    )


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
