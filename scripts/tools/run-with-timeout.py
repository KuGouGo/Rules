#!/usr/bin/env python3
"""Run one command with a deadline and propagate a useful exit status."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    if not args.command:
        parser.error("a command is required")

    process = subprocess.Popen(
        args.command,
        start_new_session=(os.name == "posix"),
    )
    try:
        return process.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
            process.wait()
        return 124


if __name__ == "__main__":
    sys.exit(main())
